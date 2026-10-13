import AVFoundation
import SwiftUI
import CoreMotion
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

// The screen's engine, the same on the watch and the iPhone: the character, the hub's state, holding to talk, the
// gestures on the character, approvals and the conversation. Each app draws it its own way (ChumsWatchApp, ChumsPhone).
// What a view shows from it (listening, the conversation) is tracked through the controller and the hub, which are
// observable; what changes every frame or every touch here is ignored, so it never makes a view redraw.

@MainActor @Observable
final class ScreenModel {
    let rig = Rig()
    let hub: HubClient
    let controller: Controller
    private let recorder = Recorder()
    private let speaker = Speaker()
    private let motion = CMMotionManager()
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var micAllowed = true
    /// Something that went wrong, in words, for a screen that doesn't draw the watch's caption (the iPhone shows it as a
    /// note in the conversation).
    @ObservationIgnored var onNotice: ((String) -> Void)?
    private func tell(_ s: String) { rig.caption = s; onNotice?(s) }
    /// The note when the microphone isn't allowed (the iPhone adds a way to Settings under it).
    static let micRefused = "Allow the microphone for Chums in Settings."
    @ObservationIgnored private var spokenKind: String?
    @ObservationIgnored private var dimmed = false
    @ObservationIgnored private var wokeAt = Date.distantPast

    struct Gesture {
        enum Mode { case none, talk, drag, pet, allow }
        var down = false, moved = false
        var level = false, jumped = false             // the touch is on a pixel level; it made the character jump
        var settings = false                          // it landed on the faces at the top left
        var approval: String?                         // the approval card under the finger, fixed at touch-down
        var target: Rig.TouchTarget = .none
        var mode: Mode = .none
        var t0 = Date(), start = CGPoint.zero, last = CGPoint.zero, lastT = Date()
        var vx = 0.0, vy = 0.0
        var timer: Task<Void, Never>?
    }
    @ObservationIgnored private var g = Gesture()

    /// Something it showed you arrived (the screen shows a pill for it).
    @ObservationIgnored var onArtifact: ((Artifact, String) -> Void)?

    /// Talk to another agent: what's on screen becomes its. A recording already going keeps the agent it started with.
    func setAgent(_ id: String) {
        guard id != controller.agent else { return }
        controller.agent = id
        if controller.talk == .speaking { controller.talk = .none }
        hub.event("agent: \(id)")
    }

    init(hub: HubClient) {
        self.hub = hub
        ArtifactImages.shared.hub = hub
        controller = Controller(rig: rig, hub: hub)
        rig.onHaptic = { Haptics.play($0) }
        rig.onAllow = { [weak self] in guard let self else { return }; self.answer(true, self.g.approval) }
        speaker.onFinish = { [weak self] in self?.controller.speechFinished(kind: self?.spokenKind) }
    }

    /// Runs once for the model SwiftUI keeps. SwiftUI may build and drop extra copies of the screen, so anything
    /// shared (the hub's callback, the motion manager, the iPhone's clock) is wired here and not in init.
    func prepare() async {
#if os(iOS)
        if clock == nil { clock = EngineClock(self, fast: fullRate) }
#endif
        // a new approval taps your wrist once, when it arrives from the hub (not when it's drawn)
        hub.onApproval = { [weak self] a in
            guard let self else { return }
            let who = self.controller.info(a.session)
            Alerts.post("\(who.name) needs approval", a.summary ?? a.description)
            if a.session == self.controller.agent { Haptics.play(.notification) }
            else {
                // another agent's: its pill (the card is there when you go to it)
                let line = Spoken(id: "approval-" + a.requestId, session: a.session, text: "Needs your OK: \(a.summary ?? a.description)",
                                  kind: "question", audio: nil, at: nil, artifact: nil, agent: a.session)
                self.controller.onBackground?(who, line)
            }
        }
        hub.onSpoken = { [weak self] line in
            guard let self else { return }
            self.spokenKind = line.kind
            if let a = line.artifact, line.owner == self.controller.agent { self.onArtifact?(a, line.text) }
            if let a = line.artifact { Task { _ = await ArtifactImages.shared.thumb(a) } }
            self.controller.spoken(line) { text in
                var voiceOn = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true      // Settings › Voice
#if targetEnvironment(simulator)
                voiceOn = false                       // the Simulator plays through the Mac's speakers; it never speaks
#endif
                if voiceOn && line.speaksHere && ["done", "question", "blocked", "working", "status", "ask", "info", "artifact"].contains(line.kind) && self.controller.talk != .listening {
                    // the Mac's voice when it rendered one (in the answer itself, else fetched), else the watch's own
                    if let b64 = line.audioData, let d = Data(base64Encoded: b64), self.speaker.play(d) {
                        self.hub.event("speech: \(line.agent ?? "?") inline \(d.count / 1024) KB")
                    } else if let path = line.audio {
                        Task {
                            if let d = await self.hub.speech(path), self.speaker.play(d) { self.hub.event("speech: \(line.agent ?? "?") fetched") }
                            else { self.speaker.speak(text); self.hub.event("speech: \(line.agent ?? "?") the watch's voice (no audio)") }
                        }
                    } else { self.speaker.speak(text) }
                } else { self.controller.speechFinished(kind: line.kind) }
            }
        }
        StayOn.shared.onEvent = { [hub] in hub.event($0) }
        startMotion()
        // its prompt would cover the self-test and Simulator captures (-quiet YES)
#if os(watchOS)
        // (the iPhone doesn't poll in the background, so it has nothing to notify you of)
        if !UserDefaults.standard.bool(forKey: "selftest") && !UserDefaults.standard.bool(forKey: "quiet") { Alerts.setUp() }
#endif
        if UserDefaults.standard.bool(forKey: "noodleBench") {                   // decode speed on this watch (-noodleBench YES)
            for clip in ["idle_rest", "work_read", "subagents_rest"] { StretchFrames.shared.bench(clip) { [hub] in hub.event($0) } }
        }
#if targetEnvironment(simulator)
        // Simulator captures (-quiet YES): no permission sheets over the recording (the capture's voice is made up anyway)
        if UserDefaults.standard.bool(forKey: "quiet") { Recorder.fake = true; micAllowed = true; hub.event("mic: not asked (capture)"); return }
#endif
#if os(watchOS)
        micAllowed = await Recorder.requestPermission()
#else
        micAllowed = AVAudioApplication.shared.recordPermission != .denied       // asked at the first hold, not at launch
#endif
    }

    /// The screen dims (always on) or wakes. Dimmed, the character draws as an outline once a second and motion
    /// stops; the hub still polls, so the character can still tap your wrist.
    @ObservationIgnored private var lastInput = Date()
    func setDimmed(_ dim: Bool) {
        rig.ao = dim; hub.screen = dim ? "dim" : "on"
        // how long since your last touch or crown: about 15 s (or 70) is watchOS's wake time running out; less is a turn
        if dim && !dimmed {
            motion.stopDeviceMotionUpdates()
            hub.event(String(format: "screen dim, %.1f s after the last touch or crown, %.1f s after it woke", Date().timeIntervalSince(lastInput), Date().timeIntervalSince(wokeAt)))
        }
        if !dim && dimmed { wokeAt = Date(); StayOn.shared.woke(); startMotion(); hub.event("screen on"); hub.nudge() }
        dimmed = dim
    }

    /// The crown turned: walk in a pixel level (or scrub). The first turn after a pause is logged, to check the crown reaches Chums.
    @ObservationIgnored private var lastCrown = Date.distantPast
    @ObservationIgnored private var crownBurst = (sum: 0.0, start: Date(), last: Date())
    func crown(_ delta: Double) {
        lastInput = Date(); StayOn.shared.lastInput = lastInput
        // each turn of the crown, in the log once it ends: how far and how fast (for tuning what the crown does)
        if Date().timeIntervalSince(crownBurst.last) > 0.6 {
            if crownBurst.sum != 0 { hub.event(String(format: "crown turn: %+.1f in %.1f s", crownBurst.sum, crownBurst.last.timeIntervalSince(crownBurst.start))) }
            crownBurst = (0, Date(), Date())
        }
        crownBurst.sum += delta; crownBurst.last = Date()
        if Date().timeIntervalSince(lastCrown) > 3 { hub.event("crown \(String(format: "%.2f", delta)), level \(rig.levelLive ? "live" : "off"), state \(rig.state), memory \(Self.memoryMB()) MB") }
        lastCrown = Date()
        rig.crown(delta)
    }

    func setDemo(_ on: Bool) {
        controller.demo = on ? DemoDriver() : nil
        rig.worlds.demo = on
    }

    /// The app's memory footprint, the number watchOS kills apps over (about 300 MB on this watch).
    static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
    @ObservationIgnored private var memAt = Date.distantPast
    @ObservationIgnored private var memLast = 0
    let perf = Perf()

#if os(iOS)
    /// The iPhone runs frame() on its own clock, whatever is on screen: a stage under a card, or scrolled out of the
    /// conversation, draws nothing, and the engine still goes on (a reply still finishes). The stages only draw the rig.
    @ObservationIgnored private var clock: EngineClock?
    /// The big stage draws a live character, at the screen's own rate: the clock runs at that rate too (else 30 a second).
    @ObservationIgnored var fullRate = false { didSet { clock?.fast = fullRate } }
#endif

    /// One frame: read the inputs, update the state, advance the rig. Called again with the same date, it does nothing.
    func frame(_ date: Date) {
        // frame rate and memory, in the hub's log every 30 s (config "diagnostics": for working on the app)
        if HubConfig.diagnostics && date.timeIntervalSince(memAt) > 30 {
            memAt = date
            let m = Self.memoryMB()
            if abs(m - memLast) >= 5 { memLast = m; hub.event("memory \(m) MB") }
            if let p = perf.take() { hub.event("\(p); \(rig.character.rawValue), memory \(m) MB") }
            if rig.character == .stretch, let s = StretchFrames.shared.takeStats() { hub.event(s) }
        }
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 1.0 / 60
        guard dt > 0 else { return }
        lastDate = date
        controller.update()
        let all = hub.state?.agents ?? Agents.known, me = controller.agent
        let mine = UserDefaults.standard.string(forKey: "character") ?? controller.info(me).character
        let fake = UserDefaults.standard.string(forKey: "fakeNeeds")      // Simulator captures: -fakeNeeds noodle
        // the faces at the top: the one you talk to, then at most two others, those that need you first (asking, stuck,
        // rate limited), then those at work, then the idle ones; never more than three
        func urgency(_ a: AgentInfo) -> Int {
            if a.needs || a.id == fake { return 0 }
            switch a.status { case "blocked": return 1; case "waiting", "limited": return 2; case "working", "compacting": return 3
                              case "offline": return 5; default: return 4 }
        }
        let others = all.filter { $0.id != me }.enumerated().sorted { (urgency($0.element), $0.offset) < (urgency($1.element), $1.offset) }.map(\.element)
        rig.faces = [(mine, false)] + others.prefix(2).map { ($0.character, $0.needs || $0.id == fake) }
        rig.voiceInput = rig.state == .listening ? (Self.fakeVoice ? Self.voiceLike(rig.t) : recorder.level) : nil
        rig.tick(dt)
    }

    /// Simulator captures (-fakeVoice YES): no one speaks into the Mac, so the waveform follows a made-up voice.
    static let fakeVoice = UserDefaults.standard.bool(forKey: "fakeVoice")
    /// Something like speech: syllables (~5 a second) of varying loudness, grouped into words with short gaps.
    static func voiceLike(_ t: Double) -> Double {
        let word = 0.5 + 0.5 * sin(t * 2.3) * sin(t * 1.1 + 1)
        let syllable = max(0, sin(t * TAU * 4.7)) * (0.6 + 0.4 * sin(t * 13.1))
        let level: Double = 0.12 + 0.75 * syllable * (0.35 + 0.65 * max(0, word))
        return clamp(level, 0, 1)
    }

    // MARK: touch

    private func design(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let f = Renderer.fit(size)
        return CGPoint(x: (p.x - f.ox) / f.s, y: (p.y - f.oy) / f.s)
    }

    func drag(_ loc: CGPoint, in size: CGSize) {
        let pt = design(loc, size), now = Date()
        lastInput = now; StayOn.shared.lastInput = now
        if !g.down {
            g = Gesture(); g.down = true; g.t0 = now; g.start = pt; g.last = pt; g.lastT = now
            // the faces at the top left belong to the agents' list: no ripple, no jump, no poke, no talking
            if SettingsButton.near(pt) && rig.state != .approval {
                g.settings = true
                hub.event("settings tap at \(Int(pt.x)),\(Int(pt.y))\(dimmed ? " on the dimmed screen" : "")")
                return
            }
            g.target = rig.touchDown(pt)
            onHandle = pt.y > 214 && abs(pt.x - 99) < 50 && rig.state != .approval
            if !onHandle { rig.staged?.touched(rig, at: pt) }   // Noodle: the glass ripples under your finger
            // just woken from the dimmed screen (the touch that woke it may never arrive): a touch held anywhere talks, sooner
            let fromSleep = now.timeIntervalSince(wokeAt) < 0.4 && g.target != .card && g.target != .deny   // the waking touch arrives within ~20 ms
            // a pixel level is a game: a tap jumps at once. In the lower part it waits for the release (it may be a hold to
            // talk), unless you're already playing; held anywhere, it talks either way
            g.level = !fromSleep && !onHandle && rig.levelLive
            if g.level && (g.target != .talkZone || rig.levelPlaying) { g.jumped = rig.levelPress() }
            if fromSleep { g.target = .talkZone }
            if now.timeIntervalSince(wokeAt) < 5 { hub.event("touch \(Int(now.timeIntervalSince(wokeAt) * 1000)) ms after the screen woke\(fromSleep ? ": talk from sleep" : "")") }
            if !hub.connected { hub.nudge() }                          // a touch while the Mac was out of reach: look again now
            g.approval = hub.state?.approvals.first(where: { $0.session == controller.agent })?.requestId
            switch g.target {
            case .card: g.mode = .allow
            case .deny: rig.staged?.deny(rig); answer(false, g.approval)
            case .talkZone, .character, .none:
                // held still anywhere (on the character, in the level, lower down), it talks
                let hold = fromSleep ? 150 : 450
                g.timer = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(hold))
                    guard let self, !Task.isCancelled, self.g.down, !self.g.moved else { return }
                    self.g.mode = .talk; self.beginTalk()
                }
            default: break
            }
            return
        }
        if g.settings { return }
        rig.touchMoved(pt)
        if g.mode != .talk && !onHandle { rig.staged?.dragged(rig, at: pt) }
        let dts = max(0.008, now.timeIntervalSince(g.lastT))
        g.vx = g.vx * 0.5 + (pt.x - g.last.x) / dts * 0.5; g.vy = g.vy * 0.5 + (pt.y - g.last.y) / dts * 0.5; g.lastT = now
        if !g.moved && hypot(pt.x - g.start.x, pt.y - g.start.y) > 6 {
            g.moved = true
            if g.mode != .talk { g.timer?.cancel() }
            if g.target == .character && g.mode != .talk { g.mode = rig.mode == .physics || rig.W.loose != nil ? .drag : .pet }
        }
        // talking: sliding left onto × arms cancel, right onto ✓ arms send; a tap on the wrist as either arms
        if g.mode == .talk {
            let slide = clamp((pt.x - g.start.x) / 46, -1, 1), was = rig.talkSlide
            if (abs(slide) >= Rig.armed) != (abs(was) >= Rig.armed) || (slide >= Rig.armed && was <= -Rig.armed) || (slide <= -Rig.armed && was >= Rig.armed) { Haptics.play(.click) }
            rig.talkSlide = slide
        }
        if g.mode == .drag { rig.W.drag = pt }
        if g.mode == .pet { rig.pet(abs(pt.x - g.last.x)) }
        g.last = pt
    }

    /// This agent's conversation, oldest first: the hub's recent lines (after a relaunch) and every line since launch.
    var conversation: [ChatLine] {
        var seen = Set<String>(), all: [Spoken] = []
        for l in (hub.state?.spoken ?? []) + controller.lines where l.owner == controller.agent && seen.insert(l.id).inserted { all.append(l) }
        return all.enumerated().sorted { ($0.element.at ?? Double($0.offset)) < ($1.element.at ?? Double($1.offset)) }.map { ChatLine($0.element) }
    }
    /// The touch started on the handle at the bottom (pulling up there opens the conversation).
    @ObservationIgnored private(set) var onHandle = false
    var talking: Bool { g.mode == .talk }
    /// The finger now belongs to the conversation card: drop whatever the touch had started.
    func cancelTouch() { g.timer?.cancel(); rig.touchUp(); g.down = false; g.mode = .none }

    enum TapAction { case none, settings, chat }
    /// What a tap opens: the agents' list (the faces at the top left), or nothing.
    func dragEnd(_ loc: CGPoint, in size: CGSize) -> TapAction {
        let pt = design(loc, size)
        g.timer?.cancel()
        rig.touchUp()
        rig.staged?.released(rig)
        defer { g.down = false; g.mode = .none }
        let short = Date().timeIntervalSince(g.t0) < 0.3 && !g.moved
        // the faces at the top left: a tap there, quick or slow, as long as it stayed put
        if g.settings { if Date().timeIntervalSince(g.t0) < 1.2 && hypot(pt.x - g.start.x, pt.y - g.start.y) < 14 { return .settings }; return .none }
        switch g.mode {
        case .talk:
            let cancel = rig.talkSlide <= -Rig.armed
            rig.talkSlide = 0
            if cancel { cancelTalk() } else { endTalk() }
        case .drag:
            rig.W.drag = nil; rig.W.body.vx = clamp(g.vx, -1400, 1400); rig.W.body.vy = clamp(g.vy, -1400, 1400)
            if rig.W.loose != nil { rig.W.loose?.phase = .fly; rig.W.loose?.sinceKick = 0 }      // thrown again
        case .pet: rig.petEnded()
        default:
            if short && g.level && !g.jumped && rig.levelPress() {}
            else if short && g.target == .character && !g.jumped { rig.poke() }
        }
        return .none
    }

    // MARK: talk and approvals

    @ObservationIgnored private var talkApproval: String?          // the approval card on screen while you spoke
    @ObservationIgnored private var talkAgent = Agents.fallback     // who you were talking to when you started: it goes to them
    @ObservationIgnored private var talkLimit: Task<Void, Never>?

    private func beginTalk() {
        guard micAllowed else { tell(Self.micRefused); return }
        speaker.stop()
        do {
            try recorder.start()
            talkApproval = g.approval; talkAgent = controller.agent
            controller.talk = .listening
            Haptics.play(.start)
            // a hold that never ends (a sleeve on the screen) stops after 30 s; on the iPhone, where a tap keeps it
            // listening, after 2 minutes
#if os(watchOS)
            let limit = 30.0
#else
            let limit = 120.0
#endif
            talkLimit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                guard let self, !Task.isCancelled, self.g.mode == .talk else { return }
                self.g.mode = .none; self.endTalk()
            }
        } catch { tell("The microphone isn't available right now."); hub.event("mic failed: \(error.localizedDescription)") }
    }

    // MARK: talking on a soul screen: what you say becomes a proposed change to that agent's soul

    /// Your voice's loudness now, 0…1. It's read from the recorder, not stored, so it's never tracked: a view that
    /// follows it reads it inside a TimelineView, every frame.
    var talkLevel: Double { Self.fakeVoice ? Self.voiceLike(rig.t) : recorder.level ?? 0 }
    func startSoulTalk() -> Bool {
        guard micAllowed else { return false }
        speaker.stop()
        do { try recorder.start(); Haptics.play(.start); return true } catch { return false }
    }
    /// Let go: nil when it was canceled (or too short); otherwise the hub's proposal, question or reason it failed.
    func endSoulTalk(cancel: Bool, agent: String) async -> SoulProposal? {
        guard let clip = recorder.stop() else { return nil }
        defer { try? FileManager.default.removeItem(at: clip.url) }
        if cancel || clip.seconds < 0.35 { if cancel { Haptics.play(.click) }; return nil }
        Haptics.play(.click)
        return await hub.sendSoul(audio: clip.url, agent: agent)
    }

    /// Let go on ×: what you said is thrown away, nothing is sent.
    private func cancelTalk() {
        talkLimit?.cancel()
        if let clip = recorder.stop() { try? FileManager.default.removeItem(at: clip.url) }
        if controller.talk == .listening { controller.talk = .none }
        Haptics.play(.click)
        controller.note("Canceled")
        hub.event("talk canceled")
        controller.flushHeld()
    }

    /// Letting go always stops the microphone, whatever the character is doing; a reply that arrived meanwhile waits.
    private func endTalk() {
        talkLimit?.cancel()
        guard let clip = recorder.stop() else { if controller.talk == .listening { controller.talk = .none }; return }
        guard clip.seconds > 0.35 else {
            try? FileManager.default.removeItem(at: clip.url)
            if controller.talk == .listening { controller.talk = .none }
            controller.flushHeld()
            return
        }
        controller.talk = .sending
        controller.orderSent()
        Haptics.play(.click)
        let approval = talkApproval, to = talkAgent
        Task {
            let result = await hub.send(audio: clip.url, approval: approval, agent: to)
            try? FileManager.default.removeItem(at: clip.url)
            if controller.talk == .sending { controller.talk = .none }
            if result == nil { Haptics.play(.failure); tell(hub.connected ? "Couldn't send that. Try again." : "Can't reach your Mac.") }
            else if result?.kind == "empty" { Haptics.play(.failure) }
            controller.flushHeld()
        }
    }

    /// Allow or deny the approval that was under the finger. Nothing happens if it changed meanwhile; the tap of
    /// success comes only once the hub has the verdict.
    private func answer(_ allow: Bool, _ id: String?) {
        guard let id, hub.state?.approvals.contains(where: { $0.requestId == id }) == true else {
            Haptics.play(.failure); tell("That request changed. Look again."); return
        }
        controller.verdictAllowed = allow
        Task {
            if await hub.verdict(id, allow: allow) { Haptics.play(allow ? .success : .failure) }
            else { controller.verdictAllowed = nil; Haptics.play(.failure); tell("Can't reach your Mac. Try again.") }
        }
    }

    // MARK: the iPhone's controls (its microphone button, composer and approval card), the same paths as the watch's touch

    /// The microphone button went down: talk to the agent on screen (an approval of its on screen is what a yes or no answers).
    func micDown() {
        guard g.mode != .talk else { return }
#if !os(watchOS)
        // the first hold asks for the microphone; that hold doesn't record (hold again once it's allowed)
        if !Recorder.fake && AVAudioApplication.shared.recordPermission == .undetermined {
            Task { micAllowed = await Recorder.requestPermission(); if !micAllowed { tell(Self.micRefused) } }
            return
        }
        micAllowed = AVAudioApplication.shared.recordPermission == .granted || Recorder.fake
#endif
        g = Gesture(); g.down = true; g.mode = .talk
        g.approval = hub.state?.approvals.first(where: { $0.session == controller.agent })?.requestId
        beginTalk()
    }
    /// It came up: send what was said, or throw it away (slid onto ×).
    func micUp(cancel: Bool) {
        g.down = false
        guard g.mode == .talk else { return }
        g.mode = .none; rig.talkSlide = 0
        if cancel { cancelTalk() } else { endTalk() }
    }
    var listening: Bool { controller.talk == .listening }
    /// Typed words, sent as if said; nil when they couldn't go.
    func send(text: String, files: [String] = []) async -> RouteResult? {
        controller.orderSent()
        speaker.stop()
        let r = await hub.say(text, agent: controller.agent, files: files)
        if r == nil { Haptics.play(.failure); tell(hub.connected ? "Couldn't send that. Try again." : "Can't reach your Mac.") }
        return r
    }
    /// Allow or deny an approval (the iPhone's card).
    func decide(_ requestId: String, allow: Bool) { answer(allow, requestId) }
    /// Stop reading aloud (the iPhone mutes when you start typing).
    func hush() { speaker.stop() }

    // MARK: self-test: synthetic touches through the real gesture path (launch with -selftest YES)

    func selfTest(size: CGSize, settings: (Bool) -> Void) async {
        func screen(_ x: Double, _ y: Double) -> CGPoint { let f = Renderer.fit(size); return CGPoint(x: f.ox + x * f.s, y: f.oy + y * f.s) }
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        func log(_ s: String) { FileHandle.standardError.write(("SELFTEST " + s + "\n").data(using: .utf8)!) }
        try? await Task.sleep(for: .seconds(2))
        let p = rig.pose()
        log("screen \(size) state \(rig.state) character \(rig.character) mode \(rig.mode) at \(Int(p.cx)),\(Int(p.cy))")
        // 0. hold to talk, slide onto ×, then onto ✓, then back onto × and let go: canceled, nothing sent
        drag(screen(110, 120), in: size); await wait(0.7)
        for i in 1...8 { drag(screen(110 - Double(i) * 7, 120), in: size); await wait(0.03) }
        log("slide left: \(rig.talkSlide <= -Rig.armed ? "× armed" : "FAILED (\(rig.talkSlide))"), caption \(rig.caption)")
        await wait(2.2)
        for i in 1...16 { drag(screen(54 + Double(i) * 7, 120), in: size); await wait(0.03) }
        log("slide right: \(rig.talkSlide >= Rig.armed ? "✓ armed" : "FAILED (\(rig.talkSlide))"), caption \(rig.caption)")
        await wait(2.2)
        for i in 1...16 { drag(screen(166 - Double(i) * 7, 120), in: size); await wait(0.03) }
        _ = dragEnd(screen(54, 120), in: size); await wait(0.2)
        log("let go on ×: talk \(controller.talk), caption \(rig.caption)")
        await wait(1.5)
        // 1. tap the character: a poke (in a pixel level, a jump)
        let before = rig.W.pokes.count
        drag(screen(p.cx, p.cy), in: size); await wait(0.1)
        _ = dragEnd(screen(p.cx, p.cy), in: size)
        log("poke: \(rig.W.pokes.count > before ? "ok" : "FAILED")")
        await wait(1)
        // 2. stroke across it: pet (happy target set while stroking)
        drag(screen(p.cx - 20, p.cy), in: size)
        for i in 1...8 { drag(screen(p.cx - 20 + Double(i) * 6, p.cy), in: size); await wait(0.02) }
        let happy = rig.S.happy.t
        _ = dragEnd(screen(p.cx + 28, p.cy), in: size)
        log("pet: \(happy == 1 ? "ok" : "FAILED")")
        await wait(0.8)
        // 3. hold the lower screen: listening after 450 ms, thinking after release
        drag(screen(99, 210), in: size); await wait(0.7)
        log("hold to talk: \(controller.talk == .listening ? "listening" : "not listening (\(rig.caption))")")
        _ = dragEnd(screen(99, 210), in: size); await wait(0.1)
        log("release: talk \(controller.talk)")
        await wait(1.5)
        // 3b. held high up too (in the level, where a tap jumps): it talks
        drag(screen(150, 70), in: size); await wait(0.7)
        log("hold high up to talk: \(controller.talk == .listening ? "listening" : "not listening")")
        _ = dragEnd(screen(150, 70), in: size); await wait(1.5)
        // 4. the faces at the top left open the agents' list: a quick tap, a slow one, one a little off them
        for (x, y, hold) in [(20.0, 24.0, 0.05), (26.0, 30.0, 0.7), (44.0, 40.0, 0.2)] {
            drag(screen(x, y), in: size); await wait(hold)
            let open = dragEnd(screen(x, y), in: size) == .settings
            log("tap at \(Int(x)),\(Int(y)) held \(hold) s opens settings: \(open ? "ok" : "FAILED")")
        }
        settings(true); await wait(1.5); settings(false)
        // 5. crown: in a pixel level it walks; elsewhere in a world it scrubs back
            rig.crown(3); await wait(0.3)
            log("crown: scrub \(Int(rig.W.scrub)) pt (mode \(rig.mode))")
        log("stay-on call reaches watchOS: \(StayOn.set(idle: 15, sleepGesture: true) ? "ok" : "FAILED")")
        log("done")
    }

    /// A light shake, then a hard one in every direction, every 12 s, as the motion sensors would report them, 50
    /// samples a second (launch with -shakeDemo YES).
    func shakeDemo() async {
        func shake(_ seconds: Double, _ g: Double) async {
            let n = Int(seconds * 50)
            for i in 0..<n {
                let t = Double(i) / 50
                rig.motion(g * sin(t * TAU * 4.5), g * 0.8 * sin(t * TAU * 3.7 + 1), g * 0.7 * sin(t * TAU * 5.3 + 2))
                try? await Task.sleep(for: .milliseconds(20))
            }
            rig.motion(0, 0, 0)
        }
        try? await Task.sleep(for: .seconds(2))
        while true {
            await shake(0.5, 1.5)
            try? await Task.sleep(for: .seconds(4))
            await shake(1.6, 3.6)
            try? await Task.sleep(for: .seconds(6))
        }
    }

    /// Simulator captures (-crownDemo YES): the crown turned up a dozen detents, held, let go; then down, let go.
    func crownDemo() async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        await wait(2.5)
        for _ in 0..<12 { crown(1); await wait(0.07) }
        await wait(1.2); await wait(2.6)                   // held, then let go: it springs back
        for _ in 0..<7 { crown(-1); await wait(0.08) }
        await wait(2.8)
        for _ in 0..<24 { crown(1); await wait(0.035) }      // fast, all the way
        await wait(3.5)
    }

    /// Simulator captures (-playDemo YES): a tap, a finger dragged across, the crown spun, a shake, as a person would.
    func playDemo(size: CGSize) async {
        func screen(_ x: Double, _ y: Double) -> CGPoint { let f = Renderer.fit(size); return CGPoint(x: f.ox + x * f.s, y: f.oy + y * f.s) }
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        func tap(_ x: Double, _ y: Double) async { drag(screen(x, y), in: size); await wait(0.08); _ = dragEnd(screen(x, y), in: size) }
        await wait(2.5)
        await tap(150, 190); await wait(2)                                                                 // a tap
        await tap(120, 40); await wait(2)                                                                  // another, up high
        let eye = rig.staged?.hit(CGPoint(x: 60, y: 112)) == true ? 60.0 : 55.0
        await tap(eye, 112); await wait(1.6)                                                               // poke an eye
        drag(screen(30, 200), in: size)                                                                    // drag across
        for i in 0..<70 { let u = Double(i) / 70; drag(screen(30 + 140 * u, 200 - 110 * sin(u * .pi)), in: size); await wait(0.03) }
        _ = dragEnd(screen(170, 200), in: size)
        await wait(1.5)
        for i in 0..<120 { rig.W.padX = 0.55 * sin(Double(i) / 120 * TAU); await wait(0.03) }              // tilt
        rig.W.padX = 0; await wait(1.5)
        for _ in 0..<16 { rig.crown(0.9); await wait(0.06) }                                               // crown up: bubbles
        await wait(3.5)
        for _ in 0..<30 { rig.crown(-0.9); await wait(0.05) }                                              // crown down: wind
        await wait(3)
        for i in 0..<70 { let t = Double(i) / 50; rig.motion(3.2 * sin(t * TAU * 4.5), 2.4 * sin(t * TAU * 3.7 + 1), 2 * sin(t * TAU * 5.3 + 2)); await wait(0.02) }
        rig.motion(0, 0, 0)                                                                                 // shake
    }

    // MARK: motion: gravity for physics and the eyes; the watch's moves throw the character around

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            // the sensors' axes (y up the screen, z out of it) turned into the screen's (y down, z toward you)
            self.rig.W.padX = m.gravity.x; self.rig.W.padY = -m.gravity.y
            let a = m.userAcceleration
            self.rig.motion(a.x, -a.y, a.z)
            let w = m.rotationRate
            StayOn.shared.motion(rotation: sqrt(w.x * w.x + w.y * w.y + w.z * w.z), accel: sqrt(a.x * a.x + a.y * a.y + a.z * a.z), gravityZ: m.gravity.z)
        }
    }
}

#if os(iOS)
/// The iPhone's engine clock: a display link that calls ScreenModel.frame 30 times a second, or at the screen's own rate
/// while a stage draws a live character big. Paused while the app is in the background, where it costs nothing.
@MainActor
final class EngineClock: NSObject {
    private weak var model: ScreenModel?
    private var link: CADisplayLink?
    var fast: Bool { didSet { if fast != oldValue { pace() } } }

    init(_ model: ScreenModel, fast: Bool) {
        self.model = model; self.fast = fast
        super.init()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link = l
        pace()
        l.isPaused = UIApplication.shared.applicationState == .background
        l.add(to: .main, forMode: .common)                       // .common: it keeps going while you scroll
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    private func pace() {
        link?.preferredFrameRateRange = fast ? .default : CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
    }
    @objc private func tick(_ l: CADisplayLink) {
        guard let model else { l.invalidate(); return }
        // the moment this frame will be on screen: the rig is where the stage draws it then
        model.frame(Date(timeIntervalSinceNow: l.targetTimestamp - CACurrentMediaTime()))
    }
    @objc private func background() { link?.isPaused = true }
    @objc private func foreground() { link?.isPaused = false }
}
#endif

/// Frame timing and CPU for the event log, every 30 s while the screen is on: how often frames come, how long one
/// takes to draw on the main thread, how many came late enough to see (over 50 ms), and how busy the app is.
final class Perf {
    private var n = 0, sum = 0.0, maxMs = 0.0, late = 0, active = 0.0, last: Date?, since = Date()
    private var cpu0 = Perf.cpu()
    func drew(_ ms: Double, at date: Date) {
        n += 1; sum += ms; maxMs = max(maxMs, ms)
        if let l = last {
            let gap = date.timeIntervalSince(l)
            if gap < 0.5 { active += gap; if gap > 0.05 { late += 1 } }      // longer gaps: dimmed, or the card was up
        }
        last = date
    }
    func take() -> String? {
        let now = Date(), wall = now.timeIntervalSince(since), c = Perf.cpu()
        defer { n = 0; sum = 0; maxMs = 0; late = 0; active = 0; since = now; cpu0 = c }
        guard n > 30, active > 1 else { return nil }
        return String(format: "perf: %.0f fps over %.0f s on screen, frame %.1f ms avg, %.0f max, %d late; cpu %.0f%%",
                      Double(n) / active, active, sum / Double(n), maxMs, late, (c - cpu0) / wall * 100)
    }
    static func cpu() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }
}
