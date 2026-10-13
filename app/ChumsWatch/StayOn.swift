import Foundation
import ObjectiveC

#if os(watchOS)

/// Keeping the screen on while you hold the watch and look at it, and letting it sleep when it's put down.
///
/// watchOS has no public way to do this, and no way to fake a touch. But WatchKit's own `isAutorotating` works by
/// calling a method of the app object watchOS runs every watch app on (PepperUICore's PUICApplication):
/// `setExtendedIdleTime:disablesSleepGesture:wantsAutorotation:`, with 23 s and the wrist-down gesture off when on,
/// 15 s and the gesture on when off (WatchKit's disassembly). We call the same method with our own idle time, without
/// turning the picture. It's not public API, which is fine for an app you build and sign yourself (it never goes to the App Store).
///
/// Held: the watch moves a little all the time (your hand is never still) and its screen faces up toward you. Hanging
/// from the keys or in a pocket it faces sideways; on a table it doesn't move.
@MainActor
final class StayOn {
    static let shared = StayOn()
    var onEvent: ((String) -> Void)?
    var enabled = true { didSet { if !enabled { apply(held: false, force: true) } } }

    private var lastMoved = Date.distantPast, facingSince: Date?, notFacingSince: Date?, current: Bool?, lastSet = Date.distantPast, flip = false
    /// The last touch or crown (the app tells it): the idle countdown runs from there.
    var lastInput = Date()
    static let heldIdle = 600.0, restIdle = 20.0

    /// Every motion sample: rotation rate in rad/s, the watch's own acceleration in g, gravity's z (−1: screen up).
    func motion(rotation: Double, accel: Double, gravityZ: Double) {
        let now = Date()
        if rotation > 0.06 || accel > 0.03 { lastMoved = now }
        if gravityZ < -0.45 { facingSince = facingSince ?? now; notFacingSince = nil } else { notFacingSince = notFacingSince ?? now; if gravityZ > -0.3 { facingSince = nil } }
        guard enabled else { return }
        // quick to decide it's held, slow to decide it isn't (a glance away or a still moment isn't putting it down):
        // held once it faces you for half a second while moving; let go after 12 s without moving or 4 s facing away
        let moving = now.timeIntervalSince(lastMoved) < 12
        let held = current == true
            ? moving && (notFacingSince.map { now.timeIntervalSince($0) < 4 } ?? true)
            : moving && (facingSince.map { now.timeIntervalSince($0) > 0.5 } ?? false)
        // while held, set it again every 30 s (alternating a hair), in case a new value restarts the countdown
        if held != current || (held && now.timeIntervalSince(lastSet) > 30) { apply(held: held) }
    }

    /// The screen woke: start from the resting idle time until the motion says it's held.
    func woke() { current = nil }

    private func apply(held: Bool, force: Bool = false) {
        let first = current != held
        current = held; lastSet = Date(); flip.toggle()
        // put down, it sleeps 20 s from now (an idle time shorter than the time since your last touch sleeps at once)
        let rest = Date().timeIntervalSince(lastInput) + Self.restIdle
        let idle = held ? Self.heldIdle + (flip ? 0.5 : 0) : (enabled ? rest : 15)
        guard Self.set(idle: idle, sleepGesture: !held) else { if first { onEvent?("stay on: not available on this watchOS") }; return }
        if first || force { onEvent?(held ? "stay on: held and facing you, screen stays on (idle \(Int(idle)) s, no wrist-down dim)" : "stay on: put down, sleeps in \(Int(Self.restIdle)) s") }
    }

    private typealias SetIdle = @convention(c) (AnyObject, Selector, Double, Bool, Bool) -> Void
    /// PUICApplication.sharedPUICApplication.setExtendedIdleTime(idle, disablesSleepGesture: !sleepGesture, wantsAutorotation: false)
    @discardableResult static func set(idle: Double, sleepGesture: Bool) -> Bool {
        guard let cls = NSClassFromString("PUICApplication") as? NSObject.Type else { return false }
        let shared = NSSelectorFromString("sharedPUICApplication"), sel = NSSelectorFromString("setExtendedIdleTime:disablesSleepGesture:wantsAutorotation:")
        guard cls.responds(to: shared), let app = cls.perform(shared)?.takeUnretainedValue() as? NSObject, app.responds(to: sel) else { return false }
        unsafeBitCast(app.method(for: sel), to: SetIdle.self)(app, sel, idle, !sleepGesture, false)
        return true
    }
}

#else
/// The iPhone keeps its own screen on; the shared screen model only tells it things.
@MainActor
final class StayOn {
    static let shared = StayOn()
    var onEvent: ((String) -> Void)?
    var enabled = false
    var lastInput = Date()
    func woke() {}
    func motion(rotation: Double, accel: Double, gravityZ: Double) {}
    @discardableResult static func set(idle: Double, sleepGesture: Bool) -> Bool { false }
}
#endif
