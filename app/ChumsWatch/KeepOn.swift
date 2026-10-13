import Foundation
import HealthKit
import WatchKit

/// Keyring mode: keeps Chums on screen and running, like a Tamagotchi hanging from your keys.
///
/// watchOS sends any app back to the watch face after a while, and suspends it when the screen dims. The one thing
/// that keeps an app frontmost and running indefinitely is a workout session, so Chums runs one and never saves it:
/// no workout shows up in Health or Fitness. While it runs, waking the screen shows Chums, not the watch face; the
/// app keeps polling the hub when the screen dims (the character shows its always-on look) and can still tap your wrist.
/// If Chums crashes or is killed while the session runs, watchOS relaunches it (see `ChumsAppDelegate`).
/// Off the wrist, also turn off Wrist Detection (Settings › Passcode), or the watch locks and hides Chums.
@MainActor @Observable
final class KeepOn: NSObject {
    static let key = "keyring"
    static let shared = KeepOn()
    private(set) var running = false
    private(set) var problem: String?
    /// Reports what happens to the session (the hub logs it), so it can be checked without looking at the watch.
    var onEvent: ((String) -> Void)?
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var starting = false
    /// Another app started a workout: watchOS ended Chums's session. Don't take it back until Chums is opened again.
    private var yielded = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.key); Task { newValue ? await start() : stop() } }
    }

    /// Called each time Chums comes to the front.
    func start() async {
        yielded = false
        guard enabled, session == nil, !starting else { return }
        guard HKHealthStore.isHealthDataAvailable() else { problem = "Keyring mode needs Health, which this watch doesn't have."; return }
        starting = true; defer { starting = false }
        let type = HKObjectType.workoutType()
        do {
            // Only permission to write workouts is needed to run a session; Chums never saves one. Ask every time:
            // it's a no-op once answered, and watchOS can report "denied" for an app that was in fact allowed, so
            // the status is logged but never trusted; starting the session is the real test.
            let request = try await store.statusForAuthorizationRequest(toShare: [type], read: [])
            onEvent?("keyring health: request \(request == .shouldRequest ? "will show the sheet" : request == .unnecessary ? "already answered" : "unknown"), status \(Self.name(store.authorizationStatus(for: type)))")
            try await store.requestAuthorization(toShare: [type], read: [])
            onEvent?("keyring health after asking: \(Self.name(store.authorizationStatus(for: type)))")
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .indoor
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            begin(s)
            s.startActivity(with: Date())
            onEvent?("keyring starting")
        } catch {
            problem = "Keyring mode failed: \(error.localizedDescription)"
            onEvent?("keyring error: \(error.localizedDescription)")
            session = nil
        }
    }

    private static func name(_ s: HKAuthorizationStatus) -> String {
        switch s { case .sharingAuthorized: "allowed"; case .sharingDenied: "denied"; case .notDetermined: "not asked"; @unknown default: "unknown" }
    }

    /// watchOS relaunched Chums after it quit with a session running: take the session back.
    func recover() async {
        starting = true; defer { starting = false }          // start() waits while the old session is taken back
        do {
            if let s = try await store.recoverActiveWorkoutSession() { begin(s); running = s.state == .running; onEvent?("keyring recovered after relaunch") }
        } catch { onEvent?("keyring recovery failed: \(error.localizedDescription)") }
    }

    private func begin(_ s: HKWorkoutSession) {
        s.delegate = self
        session = s
        problem = nil
    }

    func stop() {
        session?.end()          // ending without a workout builder saves nothing
        session = nil
        running = false
        onEvent?("keyring stopped")
    }
}

extension KeepOn: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            running = to == .running
            onEvent?("keyring \(to == .running ? "running" : to == .ended ? "ended" : to == .stopped ? "stopped" : to == .paused ? "paused" : "state \(to.rawValue)")")
            if to == .ended || to == .stopped {
                session = nil
                if enabled && !yielded { try? await Task.sleep(for: .seconds(2)); if !yielded { await start() } }
            }
        }
    }

    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            // a workout started in another app wins; Chums takes the session back the next time it's opened
            if (error as? HKError)?.code == .errorAnotherWorkoutSessionStarted {
                yielded = true; problem = "Another workout is running. Keyring mode resumes when you open this app again."
                onEvent?("keyring yielded to another workout")
            } else {
                problem = "Keyring mode failed: \(error.localizedDescription)"
                onEvent?("keyring failed: \(error.localizedDescription)")
            }
            session = nil; running = false
        }
    }
}

/// Relaunched by watchOS because a workout session was running when Chums quit: recover it, so Chums stays in front.
final class ChumsAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await KeepOn.shared.recover() }
    }
}
