import SwiftUI
import WatchKit
import CoreMotion

@main
struct ChumsWatchApp: App {
    @WKApplicationDelegateAdaptor(ChumsAppDelegate.self) private var delegate
    @State private var hub = HubClient()
    @State private var keepOn = KeepOn.shared
    @Environment(\.scenePhase) private var phase

    init() { CharacterKind.migrate() }

    var body: some Scene {
        WindowGroup {
            ChumsScreen(hub: hub, keepOn: keepOn)
                .onChange(of: phase, initial: true) { old, p in
                    if keepOn.onEvent == nil { keepOn.onEvent = { [hub] in hub.event($0) } }
                    // in keyring mode the app keeps running with the screen dimmed, so it keeps listening to the hub
                    if p == .active || keepOn.running { hub.start() } else { hub.stop() }
                    if p == .active { Task { await keepOn.start() } }
                    hub.event(old == p ? "launch, build \(HubConfig.build), keyring \(keepOn.enabled ? "on" : "off")" : "app \(p == .active ? "active" : p == .inactive ? "inactive" : "background")")
                }
                .onChange(of: keepOn.running, initial: true) { _, r in hub.keyring = r; if r { hub.start() } }
                // with the Mac away, keyring mode only holds the watch hostage: let go until Chums is opened again
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        if keepOn.running, let f = hub.failingFor, f > 600 {
                            keepOn.release("Your Mac was out of reach for 10 minutes, so keyring mode stopped. It starts again when you open Chums.")
                        }
                    }
                }
        }
    }
}

/// The whole app is one screen: the character, drawn every frame, and the gestures on it.
///   hold anywhere to talk · tap the character to poke it · stroke it to pet it
///   drag and throw it (Physics) · hold the card to allow · tap × to deny · the faces at the top left: the agents
///   shake the watch: the character is shaken, thrown or dizzied, each in its own way
///   a pixel level is a game: turn the crown to walk, tap to jump
///   just after the dimmed screen wakes, a touch held anywhere talks
struct ChumsScreen: View {
    let hub: HubClient
    let keepOn: KeepOn
    @State private var model: ScreenModel
    @AppStorage("character") private var character = CharacterKind.fallback.rawValue
    @AppStorage("agent") private var agent = Agents.fallback          // who you talk to (its character is `character`)
    @State private var notice: (agent: AgentInfo, line: Spoken)?      // another agent has news: its pill above the handle
    @State private var noticeHide: Task<Void, Never>?
    @AppStorage("mode") private var mode = "world"
    @AppStorage("demo") private var demo = false
    @AppStorage("voice") private var voice = true
    @AppStorage("stayOn") private var stayOn = true
    @State private var crown = 0.0
    @State private var showSettings = false
    @State private var chatOpen = false                       // the conversation card is up
    private static let chatTop = 30.0
    @State private var chatPull = 0.0
    @State private var chatDrop = 0.0
    @State private var pulling = false
    @State private var viewing: Artifact?                     // open full screen
    @State private var toast: (artifact: Artifact, line: String)?      // just arrived: a pill above the handle
    @State private var toastHide: Task<Void, Never>?
    @Environment(\.isLuminanceReduced) private var reduced
    @State private var calm = false
    private var touches: TouchShow { Capture.shared.touch }   // Simulator captures: the fingertip drawn over the screen
    @State private var chatScroll: (id: String, seconds: Double)?                           // a staged character holding still: 30 frames a second will do

    init(hub: HubClient, keepOn: KeepOn) {
        self.hub = hub
        self.keepOn = keepOn
        _model = State(initialValue: ScreenModel(hub: hub))
    }

    var body: some View {
        GeometryReader { geo in
            // the character keeps going behind the conversation card, at 30 frames a second (the glass over it blurs every
            // frame); it holds still only under the settings and a picture, which cover it. Noodle's frames and Pix's
            // pixels change at most 24 times a second, so they draw at 30; so do the Eyes when nothing moves fast
            TimelineView(.animation(minimumInterval: reduced ? 1 : CharacterKind(id: character)?.framed == true || calm || chatOpen || pulling ? 1.0 / 30 : nil,
                                    paused: showSettings || viewing != nil)) { tl in
                Canvas { ctx, size in
                    let t0 = CFAbsoluteTimeGetCurrent()
                    model.frame(tl.date)
                    Renderer.draw(model.rig, ctx, size: size)
                    model.perf.drew((CFAbsoluteTimeGetCurrent() - t0) * 1000, at: tl.date)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(model.rig.label.isEmpty ? (CharacterKind(id: character)?.name ?? "Character") : model.rig.label)
            .accessibilityHint("Hold the screen to talk")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if calm { calm = false }
                        if pulling { chatPull = max(0, -v.translation.height); return }
                        model.drag(v.location, in: geo.size)
                        // up from the handle at the bottom, before a hold turned into talking: the conversation follows the finger
                        if model.onHandle && v.translation.height < -10 && !model.talking {
                            model.cancelTouch(); pulling = true; chatPull = -v.translation.height
                        }
                    }
                    .onEnded { v in
                        if pulling {
                            pulling = false
                            withAnimation(.snappy(duration: 0.28)) { chatOpen = chatPull > 50 || v.predictedEndTranslation.height < -120; chatPull = 0 }
                            return
                        }
                        switch model.dragEnd(v.location, in: geo.size) {
                        case .settings: showSettings = true
                        case .chat: withAnimation(.snappy(duration: 0.28)) { chatOpen = true }
                        case .none: break
                        }
                    }
            )
        }
        .overlay(alignment: .bottom) {
            // the handle: always there; pull it up for the conversation
            Grabber(quiet: true).padding(.bottom, 5)
                .opacity(reduced || chatOpen ? 0 : 1).allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            // another agent's news: a tap goes to that agent, and opens what it showed you
            if let n = notice, toast == nil, !chatOpen, !reduced {
                AgentNotice(agent: n.agent, line: n.line.artifact.map { "Showed you: \($0.title)" } ?? n.line.text) {
                    let a = n.line.artifact
                    withAnimation(.snappy(duration: 0.3)) { notice = nil; agent = n.agent.id }
                    if let a { open(a) }
                }
                .padding(.horizontal, 8).padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            // something it showed you, just arrived: a tap opens it
            if let t = toast, !chatOpen, !reduced {
                ArtifactToast(a: t.artifact, line: t.line) { open(t.artifact) }
                    .padding(.horizontal, 8).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if chatOpen || chatPull > 0 {
                GeometryReader { g in
                    // the card stops under the clock (watchOS draws the time over everything)
                    ChatPanel(lines: model.conversation, open: open, scroll: chatScroll)
                        .frame(height: g.size.height - Self.chatTop)
                        .offset(y: chatOpen ? Self.chatTop + chatDrop : max(Self.chatTop, g.size.height - chatPull))
                        .overlay(alignment: .top) {
                            // the card's top edge: drag it down to put the card away. The zone is wider than the grabber: the
                            // whole band above the card (under the clock, where a finger reaching for it often lands) and a
                            // little into it
                            Color.clear.frame(height: Self.chatTop + 36).contentShape(Rectangle())
                                .offset(y: (chatOpen ? Self.chatTop + chatDrop : max(Self.chatTop, g.size.height - chatPull)) - Self.chatTop)
                                .gesture(DragGesture()
                                    .onChanged { chatDrop = max(0, $0.translation.height) }
                                    .onEnded { v in
                                        withAnimation(.snappy(duration: 0.25)) {
                                            if chatDrop > 50 || v.predictedEndTranslation.height > 120 { chatOpen = false }
                                            chatDrop = 0
                                        }
                                    })
                        }
                }
                .transition(.move(edge: .bottom))
            }
        }
        .overlay {
            if let a = viewing {
                ArtifactViewer(a: a) { withAnimation(.snappy(duration: 0.25)) { viewing = nil } }
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .overlay { if ScreenModel.fakeVoice { TouchSpot(show: touches) } }
        .ignoresSafeArea()
        .focusable(!chatOpen && viewing == nil)
        // a small range that wraps around: a range of ±1,000,000 detents ran the watch out of memory on the first turn
        .digitalCrownRotation($crown, from: 0, through: 60, by: 1, sensitivity: .medium,
                              isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in
            var d = new - old
            if d > 30 { d -= 60 } else if d < -30 { d += 60 }                // across the wrap
            if calm { calm = false }
            model.crown(d)
        }
        // switching agents: its character, its thread, its state (a recording already going keeps its agent)
        .onChange(of: agent, initial: true) { _, id in
            model.setAgent(id)
            let c = model.controller.info(id).character
            if c != character { character = c }
            if notice?.agent.id == id { notice = nil }
        }
        .onChange(of: hub.state?.agents?.first(where: { $0.id == agent })?.character) { _, c in if let c, c != character { character = c } }
        // the agent you talk to is gone from the Mac (an id from before every character was its own agent): talk to
        // the one for the character on screen
        .onChange(of: hub.state?.agents?.map(\.id)) { _, ids in
            if let ids, !ids.isEmpty, !ids.contains(agent) { agent = ids.contains(character) ? character : (ids.contains(Agents.fallback) ? Agents.fallback : ids[0]) }
        }
        .onChange(of: character, initial: true) { _, v in
            // a test launch (-testCharacter noodle) shows that character whoever you talk to, for this launch only
            let k = CharacterKind(id: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["testCharacter"] as? String ?? v) ?? .fallback
            model.rig.character = k
        }
        .onChange(of: mode, initial: true) { _, v in model.rig.mode = StageMode(rawValue: v) ?? .world }
        .onChange(of: demo, initial: true) { _, v in model.setDemo(v) }
        .onChange(of: reduced, initial: true) { _, v in model.setDimmed(v) }
        .onChange(of: chatOpen) { _, open in if open { model.controller.seen() } }
        // the screen stays on while you hold the watch and look at it, and sleeps when it's put down (StayOn)
        .onChange(of: stayOn, initial: true) { _, v in StayOn.shared.enabled = v }
        .onChange(of: keepOn.problem, initial: true) { _, v in model.controller.notice = v }
        .sheet(isPresented: $showSettings) {
            AgentsView(agents: hub.state?.agents ?? Agents.known, active: $agent,
                       settings: AnyView(SettingsView(character: $character, mode: $mode, demo: $demo, voice: $voice, stayOn: $stayOn, keepOn: keepOn, report: { hub.event($0) })),
                       soul: { a in AnyView(SoulView(agent: a, model: model, hub: hub)) })
        }
#if targetEnvironment(simulator)
        .task {                                                          // offline frames for recordings (OfflineRender)
            if let spec = UserDefaults.standard.string(forKey: "render") { await OfflineRender.run(spec); exit(0) }
        }
#endif
        .task {
            // the frame rate follows the staged character: full while something moves fast, 30 when it's still
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let c = model.rig.staged?.calm ?? false
                if c != calm { calm = c }
            }
        }
        .task {
            await model.prepare()
            if UserDefaults.standard.bool(forKey: "openChat") { try? await Task.sleep(for: .seconds(8)); chatOpen = true }   // for Simulator captures
            if UserDefaults.standard.bool(forKey: "openSettings") { try? await Task.sleep(for: .seconds(3)); showSettings = true }
            // another agent finished, asked, needs an approval or showed you something: its pill, and a tap on the wrist
            model.controller.onBackground = { a, line in
                Haptics.play(["question", "blocked"].contains(line.kind) ? .notification : .success)
                withAnimation(.spring(duration: 0.4, bounce: 0.25)) { notice = (a, line) }
                noticeHide?.cancel()
                noticeHide = Task { try? await Task.sleep(for: .seconds(14)); if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { notice = nil } } }
            }
            model.onArtifact = { a, line in
                toastHide?.cancel()
                toastHide = Task {
                    // the pill sits where the words of a reply do: it waits until the reply has been said (and a moment more)
                    var quiet = 0.0, waited = 0.0
                    while quiet < 0.6 && waited < 20 {
                        try? await Task.sleep(for: .milliseconds(100)); waited += 0.1
                        quiet = model.rig.state == .speaking ? 0 : quiet + 0.1
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) { toast = (a, line) }
                    try? await Task.sleep(for: .seconds(14)); if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { toast = nil } }
                }
            }
            // Simulator captures: open the newest artifact in the conversation (-openArtifact YES)
            if UserDefaults.standard.bool(forKey: "openArtifact") {
                try? await Task.sleep(for: .seconds(6))
                if let a = model.conversation.last(where: { $0.artifact != nil })?.artifact { open(a) }
            }
            if UserDefaults.standard.bool(forKey: "selftest") { await model.selfTest(size: WKInterfaceDevice.current().screenBounds.size) { showSettings = $0 } }
            if UserDefaults.standard.bool(forKey: "shakeDemo") { await model.shakeDemo() }      // Simulator captures: no sensors there
            if UserDefaults.standard.bool(forKey: "playDemo") { await model.playDemo(size: WKInterfaceDevice.current().screenBounds.size) }
            if let scene = UserDefaults.standard.string(forKey: "scene") { await playScene(scene) }
            if UserDefaults.standard.bool(forKey: "crownDemo") { await model.crownDemo() }   // Simulator captures
        }
    }

    /// Simulator captures (-scene <agent id> | switch | chat | soul, against a stand-in hub given with -hub): one agent's session
    /// played through the real screen, as a person would: hold to talk, watch it work, hold to allow, open what it showed
    /// you, look over the conversation. The hub side (what it says and does) is the stand-in's script.
    private func playScene(_ name: String) async {
        Recorder.fake = ScreenModel.fakeVoice
        let size = WKInterfaceDevice.current().screenBounds.size
        func pt(_ x: Double, _ y: Double) -> CGPoint { let f = Renderer.fit(size); return CGPoint(x: f.ox + x * f.s, y: f.oy + y * f.s) }
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        func until(_ limit: Double = 40, _ ok: () -> Bool) async {
            let end = Date().addingTimeInterval(limit)
            while !ok() && Date() < end { await wait(0.1) }
        }
        // the fingertip: it comes down, slides (eased) and lifts off; `each` runs at every step of a slide
        func down(_ p: CGPoint) async { touches.at = p; touches.visible = true; await wait(0.06); touches.down = true }
        func slide(to p: CGPoint, over t: Double, _ each: (CGPoint, Double) -> Void = { _, _ in }) async {
            let from = touches.at, n = max(1, Int(t * 60))
            for i in 1...n {
                let u = Double(i) / Double(n), e = u * u * (3 - 2 * u)
                touches.at = CGPoint(x: from.x + (p.x - from.x) * e, y: from.y + (p.y - from.y) * e)
                each(touches.at, e); await wait(t / Double(n))
            }
        }
        func up() async { touches.down = false; await wait(0.05); touches.visible = false }
        func tap(_ p: CGPoint, _ action: () -> Void) async { await down(p); await wait(0.14); action(); await up() }

        // a flick: the finger comes down, moves (the screen scrolls along with it), lifts
        func swipe(from a: CGPoint, to b: CGPoint, over t: Double, _ start: () -> Void) async {
            await down(a); start(); await slide(to: b, over: t); await up()
        }
        // the agents' faces at the top left: the list
        func openList() async {
            let p = pt(26, 24)
            await down(p); model.drag(p, in: size); await wait(0.12)
            if model.dragEnd(p, in: size) == .settings { showSettings = true }
            await up()
        }
        // hold to talk: the finger rests, the talk bar comes, it's held while "you" speak, and lifts to send
        func talk(_ seconds: Double) async {
            let p = pt(104, 176)
            await down(p); model.drag(p, in: size)
            await until(8) { model.controller.talk == .listening }; await wait(seconds)
            _ = model.dragEnd(p, in: size); await up()
        }
        // an approval: read the card, then hold it until it's allowed
        func allow() async {
            await until { model.rig.state == .approval }; await wait(2.2)
            let p = pt(99, 152)
            await down(p); model.drag(p, in: size); await wait(1.45); _ = model.dragEnd(p, in: size); await up()
        }
        func quiet() async { await until(30) { model.rig.state != .speaking && model.rig.state != .done } }
        // what it showed you: tap its pill, look, close it with the × at the top left
        func show() async {
            await until(30) { toast != nil }; await wait(1.4)
            guard let a = toast?.artifact else { return }
            await tap(pt(99, 196)) { open(a) }
            await wait(4.2)
            await tap(pt(16, 18)) { withAnimation(.snappy(duration: 0.25)) { viewing = nil } }
        }
        // the conversation: pull the handle up, scroll back to the start with a finger, back down, and drag it away
        func conversation() async {
            await wait(1.2)
            let h = pt(99, 232)
            await down(h); model.drag(h, in: size)
            model.cancelTouch(); pulling = true
            await slide(to: pt(99, 120), over: 0.45) { p, _ in chatPull = max(0, h.y - p.y) }
            pulling = false
            withAnimation(.snappy(duration: 0.28)) { chatOpen = chatPull > 50; chatPull = 0 }
            await up(); await wait(2.0)
            if !model.conversation.isEmpty {
                await down(pt(99, 80)); chatScroll = ("top", 1.3)
                await slide(to: pt(99, 205), over: 1.3); await up(); await wait(3.2)
                await down(pt(99, 205)); chatScroll = ("end", 1.3)
                await slide(to: pt(99, 80), over: 1.3); await up(); await wait(2.4)
                chatScroll = nil
            }
            let top = pt(99, Self.chatTop / Renderer.fit(size).s + 8)
            await down(top)
            await slide(to: pt(99, 170), over: 0.4) { p, _ in chatDrop = max(0, p.y - top.y) }
            withAnimation(.snappy(duration: 0.25)) { chatOpen = false; chatDrop = 0 }
            await up(); await wait(1.5)
        }

        await wait(1.0)
        model.hub.event("scene: start")
        await wait(1.5)
        switch name {
        case "code":
            await talk(3.6)                                  // the checkout tests are failing: find out why and fix it
            await allow()                                    // git push
            await show()                                     // the fix
            await quiet(); await conversation()
        case "noodle":
            await talk(3.2)                                  // send last month's Figma invoice to accounting
            await until(45) { model.rig.state == .needs }; await quiet(); await wait(1.4)   // which invoice?
            await talk(1.5)                                  // the team plan
            await allow()                                    // send the email
            await show()                                     // the email it sent
            await quiet(); await conversation()
        case "switch":                                       // the agents list: scroll it, switch to Noodle, then to Eyes
            await wait(1.5)
            await openList(); await wait(1.3)
            await swipe(from: pt(99, 205), to: pt(99, 95), over: 0.5) { Capture.shared.listScroll = "settings" }
            await wait(1.6)
            await swipe(from: pt(99, 80), to: pt(99, 200), over: 0.5) { Capture.shared.listScroll = Agents.fallback }
            await wait(1.4)
            await tap(pt(99, 160)) { Capture.shared.pick = "noodle" }
            await wait(3.6)
            await openList(); await wait(1.4)
            await tap(pt(99, 216)) { Capture.shared.pick = "pix" }
            await wait(3.6)
        case "chat":                                         // at work, then the conversation behind it
            await wait(7.5)
            await conversation()
        case "soul":                                         // Eyes' soul: open it, read it, say what changes, save
            await wait(1.5)
            await openList(); await wait(1.3)
            // swiped left on Eyes' row: its Edit (a capture can't reveal a list's swipe action, so it opens the soul)
            await down(pt(150, 216)); await slide(to: pt(60, 216), over: 0.35); await up()
            Capture.shared.openSoul = "pix"
            await wait(2.6)
            await swipe(from: pt(99, 200), to: pt(99, 90), over: 0.55) { Capture.shared.soulScroll = "end" }
            await wait(1.6)
            let hold = pt(99, 186)
            await down(hold); Capture.shared.soulPress = true
            await wait(3.4)
            Capture.shared.soulPress = false; await up()
            await wait(4.2)                                  // writing the change, then the proposal
            await swipe(from: pt(99, 80), to: pt(99, 200), over: 0.55) { Capture.shared.soulScroll = "top" }
            await wait(3.4)
            await swipe(from: pt(99, 200), to: pt(99, 90), over: 0.55) { Capture.shared.soulScroll = "end" }
            await wait(1.3)
            await tap(pt(148, 186)) { Capture.shared.soulSave = true }
            await wait(1.6)
            await swipe(from: pt(99, 80), to: pt(99, 200), over: 0.55) { Capture.shared.soulScroll = "top" }
            await wait(3.2)
        case "eyes":
            await talk(3.4)                                  // three cover options for the case study
            await show()                                     // the covers, and a question
            await until(20) { model.rig.state == .needs || model.rig.state == .idle }; await wait(1.2)
            await talk(1.5)                                  // just the eyes
            await until(20) { model.rig.state == .done }; await quiet(); await conversation()
        default: break
        }
        model.hub.event("scene: end")
    }

    private func open(_ a: Artifact) {
        hub.event("artifact opened: \(a.kind) \(Int(a.w))x\(Int(a.h))")
        withAnimation(.snappy(duration: 0.3)) { viewing = a; toast = nil }
    }
}

struct SettingsView: View {
    @Binding var character: String
    @Binding var mode: String
    @Binding var demo: Bool
    @Binding var voice: Bool
    @Binding var stayOn: Bool
    let keepOn: KeepOn
    var report: (String) -> Void = { _ in }
    @AppStorage("watchVoice") private var watchVoice: String?

    var body: some View {
        list.navigationTitle("Settings")                      // pushed from the agents list
    }

    private static func scene(_ k: CharacterKind) -> String {
        switch k {
        case .peeps: return "Peeps fill the screen on their own. Touch the screen and they follow your finger; tap an eye and it winces. Turn the crown up for bubbles (tap one to pop it), down for a wind that pushes them down. Shake the watch and they get dizzy."
        default: return "\(k.name) fills the screen with its own scene, so it has no stage to choose."
        }
    }

    private var list: some View {
        let kind = CharacterKind(id: character) ?? .fallback
        return List {
            // each agent is its own character; only a gridded one has stages to choose from, the others fill the screen their own way
            if kind.staged {
                Section {} footer: { Text(Self.scene(kind)) }
            }
            if !kind.staged {
                Section {
                    ForEach(StageMode.allCases) { m in row(m.name(for: kind), selected: mode == m.rawValue) { mode = m.rawValue } }
                } header: { Text("Stage") } footer: {
                    Text((StageMode(rawValue: mode) ?? .world).about(for: kind))
                }
            }
            Section {
                Toggle("Voice: read replies aloud", isOn: $voice)
                NavigationLink { WatchVoices(report: report) } label: {
                    HStack { Text("Watch voice"); Spacer(); Text(Speaker.voice(watchVoice)?.name ?? "").foregroundStyle(Pal.gray) }
                }
            } footer: {
                Text("With the voice off, replies are text and a tap on the wrist.")
            }
            Section {
                Toggle("Stay on while held", isOn: $stayOn)
            } footer: {
                Text("While you hold the watch facing you, the screen stays on, up to 10 minutes without a touch. Put down, hanging from your keys or in a pocket, it sleeps after 20 seconds.")
            }
            Section {
                Toggle("Keyring: stay on", isOn: Binding(get: { keepOn.enabled }, set: { keepOn.enabled = $0 }))
            } footer: {
                Text(keepOn.problem ?? "Keeps this app running, so a tap on the dark screen lands here and a touch held as it wakes talks. Off the wrist, also turn off Wrist Detection in Settings › Passcode. For the screen to stay lit longer after a tap: Settings › Display & Brightness › Wake Duration › Wake for 70 Seconds.")
            }
            Section {
                Toggle("Demo: play every state", isOn: $demo)
            }
        }
    }

    private func row(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(Pal.clay) } }
        }
    }
}

/// The voices installed on the watch, for the replies it reads itself (when the Mac doesn't render them): a tap plays a
/// sample line in that voice and picks it. The list goes to the hub's log too.
struct WatchVoices: View {
    let report: (String) -> Void
    @AppStorage("watchVoice") private var picked: String?
    @State private var speaker = Speaker()
    private let voices = Speaker.englishVoices
    static let sample = "Two tests failed in the cart. Want me to fix them?"

    var body: some View {
        List {
            Section {
                ForEach(voices, id: \.identifier) { v in
                    Button {
                        picked = v.identifier; Haptics.play(.click)
                        speaker.speak(Self.sample, voice: v.identifier)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name)
                                Text("\(Speaker.qualityName(v)) · \(v.language)").font(.system(size: 12)).foregroundStyle(Pal.gray)
                            }
                            Spacer()
                            if (picked ?? Speaker.voice(nil)?.identifier) == v.identifier { Image(systemName: "checkmark").foregroundStyle(Pal.clay) }
                        }
                    }
                }
            } footer: {
                Text(voices.isEmpty ? "No English voices on this watch." : "Tap one to hear it; it reads the replies the Mac doesn't voice.")
            }
        }
        .navigationTitle("Watch voice")
        .onAppear {
            report("watch voices: " + voices.map { "\($0.name) (\(Speaker.qualityName($0)), \($0.language))" }.joined(separator: ", "))
        }
    }
}

