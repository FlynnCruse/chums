import SwiftUI
import WidgetKit

/// The one screen, for the agent you talk to. Before you've said anything to it, it stands in the middle in a window
/// the shape of the watch's screen (the same character, touches and crown as on the watch). Once there's a
/// conversation, it is the conversation's last row, unframed, at the left: its newest line arrives right above it, what
/// it's doing plays out beside it (StateLane), and it scrolls with the rest. A tap on it brings it in front. At the top, only its name
/// (a tap opens its card), the agents' button (a panel from the left, or a swipe from the edge) and the app's settings.
/// At the bottom: type, tap or hold the microphone and talk, or add photos and files.
struct HomeView: View {
    let hub: HubClient
    @State private var model: ScreenModel
    @AppStorage("agent") private var agent = Agents.fallback
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var sheet: AgentInfo?
    @State private var appSettings = false
    @State private var viewing: Artifact?
    @State private var attachments: [Attachment] = []
    @State private var sending = false
    @State private var attaching = false
    @State private var boxHeight = 70.0              // the box at the bottom, which the conversation runs under
    @AppStorage("agentOrder") private var order = "" // the agents' order in the panel, if you changed it
    @State private var front = false                // the character brought in front of the conversation
    @State private var sidecar = false               // the agents' panel
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.38, dampingFraction: 0.86)))
    private var sideDrag: CGFloat = 0                // the open panel, dragged
    @State private var edgeDrag: CGFloat = 0         // the panel coming in from the screen's left edge
    @State private var handsFree = false            // opened from a widget, the Control or Siri: listening, no finger down
    @State private var pendingLink: PhoneLink?
    @State private var prepared = false
    @State private var lastWidgetReload = Date.distantPast
    @Namespace private var names
    @State private var notice: String?               // what just went wrong, as the conversation's last note
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    private var move: Animation { Move.or(Move.place, reduced: reduceMotion) }
    private var side: Animation { Move.or(Move.panel, reduced: reduceMotion) }
    private static let dock = CGSize(width: 100, height: 78)     // the character at the bottom of the conversation

    init(hub: HubClient) {
        self.hub = hub
        let m = ScreenModel(hub: hub)
        m.rig.chrome = false                          // the faces, status and approval card are the iPhone's own, around it
        _model = State(initialValue: m)
    }

    /// Every agent: in your order if you changed it, else the characters' order; any others after.
    private var agents: [AgentInfo] {
        let all = hub.state?.agents ?? Agents.known
        let ids = order.split(separator: ",").map(String.init) + SoulView.looks
        var seen = Set<String>()
        let first = ids.compactMap { id in seen.insert(id).inserted ? all.first { $0.id == id } : nil }
        return first + all.filter { !seen.contains($0.id) }
    }
    private var me: AgentInfo { model.controller.info(agent) }
    private var approval: Approval? { hub.state?.approvals.first { $0.session == agent } ?? demoApproval }
    @State private var demoApproval: Approval?        // debug pictures only (-approval YES)
    /// The others, for the agents button: the ones that need you first, then the ones at work.
    private var others: [AgentInfo] {
        func rank(_ a: AgentInfo) -> Int { a.needs ? 0 : a.status == "blocked" ? 1 : a.status == "working" ? 2 : a.status == "offline" ? 4 : 3 }
        return agents.filter { $0.id != agent }.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
    /// Each agent's last line in its conversation (yours too, as "You: …"), for the agents' panel.
    private var lastLines: [String: String] {
        var d: [String: String] = [:]
        for l in hub.state?.spoken ?? [] where l.kind != "verdict" {
            d[l.owner] = l.kind == "echo" ? "You: " + l.text.replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: "") : l.text
        }
        return d
    }
    private var place: StagePlace {
        if front { return .front }
        if hub.state == nil { return .dock }                       // before the hub has answered: no guess, no jump
        if model.conversation.isEmpty && !typing { return .middle }
        return .dock
    }
    /// It's working on what you asked (or tidying its memory).
    private var working: Bool { me.status == "working" || me.status == "compacting" || demoWorking }
    @State private var demoWorking = false            // debug pictures only (-working YES)
    @State private var sawItStart: Date?              // when this screen saw it start working
    @State private var firstStep: String?             // the last step it had taken before that (not shown again)
    /// Since when it has been on what you asked: your last message to it, if it hasn't answered it yet; else when this
    /// screen saw it start.
    private var workingSince: Date? {
        guard working else { return nil }
        let mine = (hub.state?.spoken ?? []).filter { $0.owner == agent }
        guard let i = mine.lastIndex(where: { $0.kind == "echo" }), let at = mine[i].at,
              !mine[(i + 1)...].contains(where: { ["done", "question", "blocked"].contains($0.kind) }) else {
            // no message of yours it's answering (it's older than the hub's window, or not yours): its first step since
            // it last stopped
            let all = (hub.state?.tools ?? []).filter { $0.session == agent }
            let current = all.lastIndex { $0.type == "stop" }.map { all[($0 + 1)...] } ?? all[...]
            let first = current.compactMap(\.at).min().map { Date(timeIntervalSince1970: $0 / 1000) }
            return [first, sawItStart].compactMap { $0 }.min()
        }
        return Date(timeIntervalSince1970: at / 1000)
    }
    /// Its steps on what you asked so far, newest last (its tool calls: "Read hub.mjs", "Bash npm test").
    private var steps: [ToolInfo] {
        let mine = (hub.state?.tools ?? []).filter { $0.session == agent && $0.type != "stop" }
        guard let f = firstStep, let i = mine.lastIndex(where: { $0.id == f }) else { return mine }
        return Array(mine[(i + 1)...])
    }
    /// What the lane beside it says now: the action, and exactly what on.
    private var lane: StateLane.Words? {
        if hub.state == nil { return patient ? nil : .init(main: "Can't reach your Mac", tone: .amber, detail: "Trying again") }
        if !reachable { return .init(main: "Can't reach your Mac", tone: .amber, detail: "Trying again") }
        if model.listening { return .init(main: "Listening", detail: "↑ sends it to \(me.name), × throws it away") }
        if sending { return .init(main: attachments.contains { $0.preview != nil } ? "Sending your photo" : "Sending your file", tone: .live, detail: "To your Mac") }
        if model.controller.talk == .sending { return .init(main: "Sending what you said", tone: .live, detail: "Your Mac turns it into text") }
        if model.controller.talk == .speaking { return .init(main: "Speaking", detail: "Tap to stop") }
        if let a = approval { return .init(main: "Needs you", tone: .amber, detail: Self.asks(a).text, code: Self.asks(a).code) }
        if me.needs { return .init(main: "Needs you", tone: .amber, detail: "It asked you a question") }
        if working {
            let since = workingSince ?? Date()
            if me.status == "compacting" { return .init(main: "Tidying its memory", tone: .live, detail: "Making its conversation shorter", since: since) }
            let s = demoWorking ? [ToolInfo(id: "d1", session: agent, type: "read", text: "Read hub.mjs", ok: true),
                                   ToolInfo(id: "d2", session: agent, type: "test", text: "Bash npm test", ok: nil)] : steps
            if let t = s.last {
                let w = StateLane.step(t.text, test: t.type == "test")
                return .init(main: w.main, tone: .live, detail: w.detail, code: w.code, since: since)
            }
            if answered { return .init(main: "Finishing up", tone: .live, detail: "Writing the rest on your Mac", since: since) }
            return .init(main: "Thinking", tone: .live, detail: askedWithFiles > 0 ? "About your message and \(askedWithFiles == 1 ? "photo" : "files")" : "About your message", since: since)
        }
        switch me.status {
        case "offline": return .init(main: "Not running on your Mac", tone: .quiet)
        case "blocked": return .init(main: "Stuck", tone: .red, detail: "It said why above")
        case "limited": return .init(main: "Rate limited", tone: .amber, detail: "It goes on by itself")
        default: return nil                                       // idle: the character alone
        }
    }
    /// Its lines since your last message to it.
    private var sinceAsked: ArraySlice<Spoken> {
        let mine = (hub.state?.spoken ?? []).filter { $0.owner == agent }
        guard let i = mine.lastIndex(where: { $0.kind == "echo" }) else { return [] }
        return mine[i...]
    }
    /// It has already answered what you asked (it's still at work: writing on the Mac).
    private var answered: Bool { sinceAsked.dropFirst().contains { ["done", "question", "blocked"].contains($0.kind) } }
    /// What you sent with your last message: 0, or 1 for a photo, 2 for files.
    private var askedWithFiles: Int {
        guard let echo = sinceAsked.first, echo.artifact != nil else { return 0 }
        return echo.artifact?.kind == "image" ? 1 : 2
    }
    /// What an approval asks, in words: "Asks to read photo-1.jpg", "Asks to run a command".
    static func asks(_ a: Approval) -> (text: String, code: Bool) {
        let input = (try? JSONSerialization.jsonObject(with: Data(a.preview.utf8))) as? [String: Any] ?? [:]
        let file = (input["file_path"] as? String ?? input["path"] as? String).map { f -> String in
            let base = (f as NSString).lastPathComponent
            return StateLane.sentName(base) ?? base
        }
        switch a.tool {
        case "Read": return ("Asks to read \(file ?? "a file")", false)
        case "Edit", "MultiEdit": return ("Asks to edit \(file ?? "a file")", false)
        case "Write": return ("Asks to write \(file ?? "a file")", false)
        case "Bash": return ("Asks to run a command", false)                    // the card under it shows which
        case "WebFetch": return ("Asks to open \(URL(string: input["url"] as? String ?? "")?.host() ?? "a page")", false)
        default: return ("Asks to use \(a.tool)", false)
        }
    }
    /// For the first few seconds the hub hasn't answered yet, it isn't "can't reach" — just not yet.
    @State private var patient = true
    @State private var settled = false                            // the first answer from the hub has been laid out
    private var reachable: Bool { hub.connected || patient }

    var body: some View {
        GeometryReader { geo in
            let sideW = min(330, geo.size.width * 0.84)
            let raw = (sidecar ? 1 : 0) + (sideDrag + edgeDrag) / sideW            // how far the agents' panel is out
            let p = min(1, max(0, raw))
            let over = max(0, raw - 1) * sideW * 0.18                               // pulled past open: it gives a little
            ZStack(alignment: .topLeading) {
                screen(geo)
                    .scaleEffect(1 - 0.06 * p, anchor: .trailing)
                    .overlay {
                        Color.black.opacity(0.6 * p).ignoresSafeArea()
                            .allowsHitTesting(p > 0.01)
                            .onTapGesture { withAnimation(side) { sidecar = false } }
                    }
                Sidecar(agents: agents, active: agent, connected: reachable, last: lastLines) { id in
                    pick(id)
                    withAnimation(side) { sidecar = false }
                } settings: { a in sheet = a } reorder: { ids in order = ids.joined(separator: ",") }
                    .frame(width: sideW)
                    .offset(x: -sideW * (1 - p) + over - 24 * max(0, 1 - p * 20))       // its shadow off screen when shut
                    .shadow(color: .black.opacity(0.5 * p), radius: 24, x: 8)
                    .gesture(sideGesture(sideW))
            }
            // a swipe in from the left edge opens the agents (the system's edge pan: taps and scrolls there pass through)
            .gesture(EdgePan(enabled: !sidecar && place != .front) { edgeDrag = max(0, $0) } ended: { _, end in
                withAnimation(side) { edgeDrag = 0; sidecar = end > sideW * 0.5 }
            })
        }
        .background(Color.black.ignoresSafeArea())
        // a soft knock when the character comes in front or goes back (not when the keyboard moves it)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: front)
        .sensoryFeedback(.selection, trigger: sidecar)
        // a soft tap when the agent you're looking at answers
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: model.conversation.count) { _, _ in
            model.conversation.last?.who == .chums
        }
        .task {
            guard !prepared else { return }
            prepared = true
            Task { try? await Task.sleep(for: .seconds(4)); patient = false }
            model.onNotice = { text in
                withAnimation(Move.fade) { notice = text }
                let life = text == ScreenModel.micRefused ? 15.0 : 6.0                  // time to reach Settings
                Task { try? await Task.sleep(for: .seconds(life)); if notice == text { withAnimation(Move.fade) { notice = nil } } }
            }
            await model.prepare()
            model.setAgent(agent)
            if let l = pendingLink { pendingLink = nil; follow(l) }
            #if DEBUG
            await WidgetShots.run()
            let args = UserDefaults.standard
            if let id = args.string(forKey: "sheet") { sheet = agents.first { $0.id == id } }   // -sheet <agent>
            if args.bool(forKey: "agents") { sidecar = true }                                  // -agents YES
            if args.bool(forKey: "front") { front = true }                                    // -front YES
            if args.bool(forKey: "settings") { appSettings = true }                          // -settings YES
            if let id = args.string(forKey: "viewer") {                                       // -viewer <artifact id>
                viewing = Artifact(id: id, kind: "image", title: "Test picture", from: nil, w: 1200, h: 1600)
            }
            if args.bool(forKey: "approval") {                                                // -approval YES
                demoApproval = Approval(requestId: "demo", session: agent, tool: "Bash", description: "Delete the build folder",
                                        preview: "{\"command\":\"rm -rf ~/Developer/chums/app/build\"}", summary: "rm -rf ~/Developer/chums/app/build")
            }
            if args.bool(forKey: "attach") {                                                  // -attach YES
                let r = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800))
                for (i, c) in [UIColor.systemOrange, .systemPink].enumerated() {
                    let img = r.image { ctx in c.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800)) }
                    if let a = Attachment.photo(img, name: "photo-\(i + 1).jpg") { attachments.append(a) }
                }
                attachments.append(Attachment(name: "notes.pdf", type: "application/pdf", data: Data([1]), preview: nil))
            }
            if args.bool(forKey: "listen") { follow(.talk(nil)) }                            // -listen YES (with -quiet YES)
            if args.bool(forKey: "working") { demoWorking = true }                           // -working YES
            // -viewerJSON <artifact JSON, base64> opens it, as a tap on it would; -readmeDemo <artifact JSON, base64>
            // puts it in a made-up conversation (the README's pictures)
            let artifact = { (key: String) in args.string(forKey: key).flatMap { Data(base64Encoded: $0) }
                .flatMap { try? JSONDecoder().decode(Artifact.self, from: $0) } }
            if let a = artifact("viewerJSON") { viewing = a }
            if args.string(forKey: "readmeDemo") != nil { model.controller.readmeDemo(agent, chart: artifact("readmeDemo")) }
            if let n = args.string(forKey: "demoConversation").flatMap(Int.init) {           // -demoConversation 24
                model.controller.demoConversation(n, agents: agents.map(\.id))
            }
            if args.bool(forKey: "crownDemo") { await model.crownDemo() }                    // -crownDemo YES
            // -say "…" sends that as if typed, once the hub has answered
            if let text = args.string(forKey: "say") {
                for _ in 0..<40 where hub.state == nil { try? await Task.sleep(for: .milliseconds(250)) }
                _ = await model.send(text: text)
            }
            #endif
        }
        .onChange(of: agent, initial: true) { _, id in
            model.setAgent(id)
            // the widgets show the agent you're on: the hub hears it first, then they look again
            Task { await hub.focus(id); WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: phase) { _, p in
            if p == .background { WidgetCenter.shared.reloadAllTimelines() }      // back on the Home Screen: up to date
        }
        .onChange(of: me.character, initial: true) { _, c in
            if let k = CharacterKind(id: c) { model.rig.character = k }
        }
        .onChange(of: hub.state != nil) { _, has in
            if has { Task { try? await Task.sleep(for: .milliseconds(400)); settled = true } }
        }
        .onChange(of: hub.state?.rev) { _, _ in
            // the widgets follow what the app sees, at most every 20 s
            if Date().timeIntervalSince(lastWidgetReload) > 20 { lastWidgetReload = Date(); WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: working, initial: true) { was, on in
            sawItStart = on ? Date() : nil
            // it starts on something new here: its steps from before aren't this work's (at launch, or on another
            // agent, they may be: they show)
            firstStep = on && !was ? (hub.state?.tools ?? []).last(where: { $0.session == agent && $0.type != "stop" })?.id : nil
        }
        .onChange(of: agent) { firstStep = nil; sawItStart = working ? Date() : nil }
        .onChange(of: typing) { _, on in
            guard on else { return }
            model.hush(); hub.nudge()                                    // typing while it's out of reach: look again now
            withAnimation(move) { front = false }
        }
        .accessibilityAction(.magicTap) { follow(.talk(nil)) }           // two-finger double tap: talk, hands-free
        .onOpenURL { url in
            guard let l = PhoneLink(url) else { return }
            if prepared { follow(l) } else { pendingLink = l }
        }
        .sheet(item: $sheet) { a in AgentSheet(agent: a, hub: hub) }
        .sheet(isPresented: $appSettings) { AppSettings(hub: hub, character: me.character) }
        .sheet(item: $viewing) { a in ArtifactSheet(artifact: a, character: me.character) }
    }

    // MARK: the screen

    /// The conversation and its controls, with the character over them in its place.
    private func screen(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width, h = geo.size.height
        let r = stageRect(w, h)
        return ZStack(alignment: .top) {
            // the conversation fills the screen and runs under the bar at the top and the box at the bottom, fading out
            // under each over most of its height
            ZStack(alignment: .bottom) {
                // a tap anywhere here puts the keyboard away
                Color.black.contentShape(Rectangle()).onTapGesture { typing = false }
                if place == .dock || front {
                    Conversation(lines: model.conversation, name: me.name, top: Self.barHeight,
                                 bottom: boxHeight, notice: notice, hush: { model.hush() },
                                 askFirst: (me.runtime ?? "claude") == "claude" && me.permission != "default" ? { askFirst() } : nil,
                                 open: { viewing = $0 }) { nowRow }
                        .id(agent)                                   // each agent's conversation opens on its newest line
                        .simultaneousGesture(TapGesture().onEnded { typing = false })
                        .transition(.opacity)
                }
                if attaching {
                    // a tap or a scroll behind the menu closes it, the moment the finger lands
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                            if attaching { withAnimation(Move.snap) { attaching = false } }
                        })
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    if let a = approval {
                        ApprovalCard(approval: a, name: me.name) { model.decide(a.requestId, allow: $0) }
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Composer(name: me.name, draft: $draft, attachments: $attachments, typing: $typing, model: model,
                             handsFree: $handsFree, attaching: $attaching, sending: sending) { text in send(text) }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { boxHeight = $0 }
                .opacity(front ? 0 : 1)
            }
            .blur(radius: front && !reduceMotion ? 16 : 0)
            .overlay {
                if front {
                    Color.black.opacity(reduceMotion ? 0.7 : 0.55).ignoresSafeArea()
                        .onTapGesture { withAnimation(move) { front = false } }
                        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                            if v.translation.height > 60 { withAnimation(move) { front = false } }
                        })
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) { topBar(w) }

            // in the middle (no conversation yet) or in front: over everything. At the bottom it's the conversation's
            // last row (nowRow), and the same character flies between the two.
            if place != .dock {
                stage(small: false)
                    .frame(width: r.width, height: r.height)
                    .matched("stage", in: names, if: !reduceMotion)            // Reduce Motion: it fades instead of flying
                    .position(x: r.midX, y: r.midY)
            }

            if place == .middle || place == .front { caption(below: r, width: w) }
        }
        .animation(settled ? move : nil, value: place)
        .animation(Move.snap, value: approval?.requestId)
        .animation(Move.settle, value: model.listening)
    }

    /// The conversation's last row: the agent, small and unframed, and what it's doing beside it. It scrolls with the
    /// conversation; in front, its place stays empty while it's out.
    private var nowRow: some View {
        HStack(spacing: 4) {
            ZStack {
                if place == .dock {
                    stage(small: true)
                        .matched("stage", in: names, if: !reduceMotion)
                        .modifier(VoiceScale(model: model, on: model.listening, base: 1.06, gain: 0.06))   // grows with your voice
                }
            }
            .frame(width: Self.dock.width, height: Self.dock.height)
            .padding(.leading, -12)                                    // its edges fade out: the character itself lines up
            StateLane(words: place == .dock ? lane : nil) { if model.controller.talk == .speaking { model.hush() } }
                .frame(height: Self.dock.height)
        }
        .padding(.top, 8)
    }

    private func stage(small: Bool) -> some View {
        CharacterStage(model: model, agent: me, small: small,
                       paused: sheet != nil || viewing != nil || appSettings || sidecar) {
            withAnimation(move) { front = true }
        } settings: { sheet = me }
    }

    /// The agents button, the agent's name (a tap opens its card) and the app's settings. Its state is at the bottom,
    /// beside it.
    private func topBar(_ w: CGFloat) -> some View {
        ZStack {
            HStack {
                AgentsButton(others: others) { withAnimation(side) { sidecar = true } }
                Spacer()
                DotsButton(label: "Settings") { appSettings = true }
            }
            .padding(.leading, 14).padding(.trailing, 6)
            if place == .dock {
                Button { sheet = me } label: {
                    HStack(spacing: 4) {
                        Text(me.name).font(.headline).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .matchedGeometryEffect(id: "name", in: names)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Ink.ghost)
                    }
                    .frame(minHeight: M.target).padding(.horizontal, 10).contentShape(Rectangle())
                }
                .frame(maxWidth: max(120, w - 2 * 96))                     // clear of the faces and the dots
                .buttonStyle(Pressable())
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)                  // the bar's height is fixed
                .accessibilityIdentifier("name-button")
                .accessibilityHint("Opens \(me.name)'s card")
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
        .frame(height: Self.barHeight, alignment: .top)
    }
    private static let barHeight = 52.0                        // the bar at the top: the buttons and the name

    /// Under the big character: its name and what it's doing (and, before you've talked to it, how).
    private func caption(below r: CGRect, width w: CGFloat) -> some View {
        let talk = model.listening || model.controller.talk != .none          // the box listens, sends or it speaks
        return
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                if place == .front { Color.clear.frame(width: 44, height: 1) }        // keeps the name centred
                Text(me.name).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .matchedGeometryEffect(id: "name", in: names)
                if place == .front {
                    DotsButton(label: "\(me.name)'s settings") { sheet = me }       // its card, from right here
                        .transition(.opacity)
                }
            }
            Text(hub.state == nil ? " " : talk ? lane?.main ?? " " : AgentWords.state(me, connected: reachable))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(talk ? .white : AgentWords.color(me, connected: reachable))
                .contentTransition(.opacity)
                .matchedGeometryEffect(id: "status", in: names)
            if place == .middle && !talk {
                Text("Hold the screen to talk to \(me.name), or type.")
                    .font(.footnote).foregroundStyle(Color(white: 0.55)).padding(.top, 6)
                if let notice { NoticeLine(text: notice).transition(.opacity) }
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: min(w - 2 * M.margin, 380))
        .position(x: r.midX, y: r.maxY + (place == .middle ? 70 : 54))
        .allowsHitTesting(place == .front || notice == ScreenModel.micRefused)     // its dots; or the way to Settings
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Where the character is drawn, in this screen's points.
    private func stageRect(_ w: CGFloat, _ h: CGFloat) -> CGRect {
        let aspect = DESIGN.width / DESIGN.height
        switch place {
        case .dock:
            // (drawn in the conversation's last row; this is where that row is when the conversation is at its end)
            return CGRect(x: 2, y: h - boxHeight - 2 - Self.dock.height, width: Self.dock.width, height: Self.dock.height)
        case .middle:
            let top = 70.0, bottom = h - boxHeight - 130                  // the box below, the caption under it
            let wh = min(h < 700 ? 280 : 340, max(180, bottom - top)), ww = wh * aspect
            return CGRect(x: (w - ww) / 2, y: top + max(0, (bottom - top - wh) * 0.45), width: ww, height: wh)
        case .front:
            let wh = min(h < 700 ? 320 : 400, h * 0.5), ww = wh * aspect
            return CGRect(x: (w - ww) / 2, y: max(70, h * 0.4 - wh / 2), width: ww, height: wh)
        }
    }

    private func sideGesture(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($sideDrag) { v, s, _ in s = v.translation.width }
            .onEnded { v in
                let p = (sidecar ? 1 : 0) + v.predictedEndTranslation.width / width
                withAnimation(side) { sidecar = p > 0.5 }
            }
    }

    /// Sends what's typed, with the photos and files above the box: they go to the Mac first, then the message names them.
    private func send(_ text: String) {
        let files = attachments
        guard !files.isEmpty else {
            Task { if await model.send(text: text) == nil, draft.isEmpty { draft = text } }    // didn't go: your words come back
            return
        }
        sending = true
        Task {
            var paths: [String] = []
            for f in files { if let u = await hub.upload(f.data, name: f.name, type: f.type) { paths.append(u.path) } }
            sending = false
            guard !paths.isEmpty else {                                                  // nothing reached the Mac: try again
                Haptics.play(.failure); if draft.isEmpty { draft = text }
                withAnimation(Move.fade) { notice = hub.connected ? "Couldn't send the files. Try again." : "Can't reach your Mac." }
                return
            }
            if await model.send(text: text, files: paths) == nil { if draft.isEmpty { draft = text }; return }   // kept for again
            withAnimation(.snappy) { attachments.removeAll { a in files.contains(a) } }
        }
    }

    /// Under a refusal: this agent asks you from now on (Asks first); it restarts, and its conversation carries on.
    private func askFirst() {
        Haptics.play(.click)
        let name = me.name
        Task {
            if let e = await hub.setPermission(agent, mode: "default") { model.onNotice?(e); Haptics.play(.failure) }
            else { model.onNotice?("\(name) asks first now."); Haptics.play(.success) }
        }
    }

    private func pick(_ id: String) {
        guard id != agent else { return }
        Haptics.play(.click)
        withAnimation(move) { front = false }
        withAnimation(Move.fade) { agent = id }                       // its conversation replaces the other's: no morph
    }

    private func follow(_ l: PhoneLink) {
        switch l {
        case .agent(let id): pick(id)
        case .talk(let id):
            if let id { agent = id; model.setAgent(id) }
            typing = false
            model.micDown()
            if model.listening { handsFree = true }
        }
    }
}

extension View {
    /// matchedGeometryEffect, or nothing (Reduce Motion: things fade where they are instead of flying).
    @ViewBuilder func matched(_ id: String, in ns: Namespace.ID, if on: Bool) -> some View {
        if on { matchedGeometryEffect(id: id, in: ns) } else { self }
    }
}

/// The system's pan from the screen's left edge, for SwiftUI: it only starts on a horizontal drag that begins at the
/// edge, and other pans (the conversation's scroll) wait for it to fail, so a tap or a vertical scroll there goes
/// through. `changed` gets the distance, `ended` the distance and where a flick would have taken it.
struct EdgePan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let g = UIScreenEdgePanGestureRecognizer()
        g.edges = .left
        g.delegate = context.coordinator
        return g
    }
    func updateUIGestureRecognizer(_ g: UIScreenEdgePanGestureRecognizer, context: Context) { g.isEnabled = enabled }
    func handleUIGestureRecognizerAction(_ g: UIScreenEdgePanGestureRecognizer, context: Context) {
        let t = g.translation(in: g.view).x, v = g.velocity(in: g.view).x
        switch g.state {
        case .changed: changed(t)
        case .ended, .cancelled, .failed: ended(t, t + v * 0.15)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && !(other is UIScreenEdgePanGestureRecognizer)
        }
    }
}
