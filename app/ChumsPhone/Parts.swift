import SwiftUI

// The iPhone screen's parts. All black; the type is SF; color only where it means something (amber needs you, white
// working, red stuck), as on the watch.

/// What an agent is doing, in a word or two (its words are in the conversation), and its color: amber needs you, red
/// stuck, gray otherwise.
enum AgentWords {
    static func state(_ a: AgentInfo, connected: Bool = true) -> String {
        if !connected { return "Can't reach your Mac" }
        if a.needs { return "Needs you" }
        switch a.status {
        case "offline": return "Not running on your Mac"
        case "working": return "Working"
        case "compacting": return "Tidying its memory"
        case "limited": return "Rate limited"
        case "blocked": return "Stuck"
        default: return "Idle"
        }
    }
    static func color(_ a: AgentInfo, connected: Bool = true) -> Color {
        !connected || a.needs ? Pal.amber : a.status == "blocked" ? Pal.red : Ink.quiet
    }
}

/// The agent's conversation, newest at the bottom: you on the right, it on the left, what it showed you as a picture,
/// notes in the middle, and last of all `now` (the agent itself and what it's doing), which scrolls with the rest. It
/// runs the height of the screen, under the bar at the top (`top` points) and the box at the bottom (`bottom` points):
/// at rest the first and last rows sit clear of them; scrolled, they thin out on a curve as they pass under
/// (EdgeFade). `notice` is something that just went wrong, as the last note.
struct Conversation<Now: View>: View {
    let lines: [ChatLine]
    let name: String
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var notice: String? = nil
    var hush: () -> Void = {}
    var askFirst: (() -> Void)? = nil                // under a refusal: switch the agent to Asks first (nil: it does)
    let open: (Artifact) -> Void
    @ViewBuilder var now: () -> Now
    @State private var phase: ScrollPhase = .idle
    @State private var pinned = true                 // at the newest line: it stays there as lines come and the room changes

    private struct Spot: Equatable { var top: Double; var fromBottom: Double; var room: Double }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // laid out whole (at most ~120 lines): scrolling to the end lands on it exactly, no estimated heights
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                        // 4 pt between lines from the same side, 12 when the side changes
                        Bubble(line: l, name: name, open: open, hush: hush, askFirst: askFirst)
                            .padding(.top, i == 0 ? 0 : lines[i - 1].who == l.who ? 4 : 12)
                            .id(l.id)
                            .accessibilityIdentifier(i == lines.count - 1 ? "last-line" : "line")
                    }
                    if let notice {
                        NoticeLine(text: notice).frame(maxWidth: .infinity).padding(.top, 12).transition(.opacity)
                    }
                    now()
                    Color.clear.frame(height: 2).id("end")
                }
                .padding(.horizontal, M.margin - 2)
            }
            // room above and below as safe area (not content margins): short content then sits on the box, its end
            // above it, instead of a margin too low
            .safeAreaPadding(.top, top + 40)
            .safeAreaPadding(.bottom, bottom + 16)
            .mask { EdgeFade(top: top, bottom: bottom, topReach: 40, topDepth: 0) }   // gone before it reaches the name
            .defaultScrollAnchor(.bottom)                                            // opens on the newest line; short, sits on the box
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)                     // all of it on screen: it doesn't move
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, p in phase = p }
            .onScrollGeometryChange(for: Spot.self) { g in
                Spot(top: g.contentOffset.y + g.contentInsets.top,
                     fromBottom: g.contentSize.height + g.contentInsets.bottom - g.contentOffset.y - g.containerSize.height,
                     room: g.containerSize.height)
            } action: { old, s in
                // pinned and at rest, it never drifts off the newest line (the box measured, lines arriving, the
                // keyboard coming or going): put it back at once
                if pinned && phase == .idle && s.fromBottom > 1 { proxy.scrollTo("end", anchor: .bottom); return }
                if s.room != old.room {                                              // an approval, the keyboard
                    if pinned { proxy.scrollTo("end", anchor: .bottom) }
                    return
                }
                // only your finger scrolling unpins it: not a scroll the app makes, and not a tap (a tap that puts the
                // keyboard away lands while the room is still changing)
                guard phase == .interacting || phase == .decelerating else { return }
                pinned = s.fromBottom < 60
            }
            .onChange(of: lines.count) { old, _ in
                // the conversation arriving opens on its newest line, at once; after that a new line shows unless
                // you're reading further back (your own always shows)
                if old == 0 { proxy.scrollTo("end", anchor: .bottom); return }
                guard pinned || lines.last?.who == .you else { return }
                pinned = true
                withAnimation(Move.settle) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: notice) { if pinned { withAnimation(Move.settle) { proxy.scrollTo("end", anchor: .bottom) } } }
            // the box below (or the bar above) changed height: the newest line stays on it
            .onChange(of: bottom) { if pinned { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: top) { if pinned { proxy.scrollTo("end", anchor: .bottom) } }
            // once the keyboard has finished coming or going, back on the newest line
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                if pinned { withAnimation(Move.settle) { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if pinned { withAnimation(Move.settle) { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
    }
}

/// Something that just went wrong, in amber, as the conversation's last note. A refused microphone has the way to
/// Settings under it.
struct NoticeLine: View {
    let text: String
    var body: some View {
        VStack(spacing: 2) {
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(Pal.amber).multilineTextAlignment(.center)
            if text == ScreenModel.micRefused {
                Button("Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(minHeight: M.target).contentShape(Rectangle())
                .buttonStyle(Pressable())
            }
        }
    }
}

struct Bubble: View {
    let line: ChatLine
    var name = ""                                    // the agent's, for VoiceOver ("Ray: …")
    let open: (Artifact) -> Void
    var hush: () -> Void = {}
    var askFirst: (() -> Void)? = nil
    @AppStorage("voice") private var speak = true

    var body: some View {
        switch line.who {
        case .you:
            VStack(alignment: .trailing, spacing: 6) {
                if line.artifact.map({ $0.title != line.text }) ?? true {
                    HStack {
                        Spacer(minLength: 56)
                        text(line.text, on: Ink.you)
                    }
                }
                if let a = line.artifact { PhotoBubble(artifact: a) { open(a) } }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(line.text)")
        case .chums:
            VStack(alignment: .leading, spacing: 6) {
                if line.artifact.map({ $0.title != line.text }) ?? true {
                    HStack {
                        text(line.text, on: Ink.agent)
                            .accessibilityLabel(name.isEmpty ? line.text : "\(name): \(line.text)")
                        Spacer(minLength: 56)
                    }
                }
                if let a = line.artifact { ArtifactCard(artifact: a) { open(a) } }
            }
            .accessibilityElement(children: .combine)
        case .note:
            VStack(spacing: 2) {
                Text(line.text).font(.caption.weight(.medium)).foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                // auto mode refused it without asking: from now on, it can ask you instead
                if line.refused, let askFirst {
                    Button("Ask first instead", action: askFirst)
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(minHeight: M.target).contentShape(Rectangle())
                        .buttonStyle(Pressable())
                        .accessibilityIdentifier("ask-first")
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 2)
        }
    }

    /// Press and hold a message: copy it; on the agent's, mute (or bring back) reading its replies aloud.
    private func text(_ s: String, on fill: Color) -> some View {
        Text(s).font(.body).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(fill, in: RoundedRectangle(cornerRadius: M.bubble, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: M.bubble, style: .continuous))
            .contextMenu {
                Button { UIPasteboard.general.string = s } label: { Label("Copy", systemImage: "doc.on.doc") }
                if line.who == .chums {
                    Button {
                        speak.toggle()
                        if !speak { hush() }
                    } label: {
                        Label(speak ? "Mute replies" : "Read replies aloud", systemImage: speak ? "speaker.slash" : "speaker.wave.2")
                    }
                }
            }
    }
}

/// A picture you sent, as itself, on your side of the conversation, whole (not cropped). A tap opens it full screen.
struct PhotoBubble: View {
    let artifact: Artifact
    let open: () -> Void
    @State private var image: CGImage?

    var body: some View {
        let aspect = artifact.w / max(artifact.h, 1)
        let w = min(240, 300 * aspect), h = w / max(aspect, 0.01)
        Button(action: open) {
            Group {
                if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) } else { Ink.agent }
            }
            .frame(width: w, height: min(300, h))
            .clipShape(RoundedRectangle(cornerRadius: M.bubble, style: .continuous))
            .contentTransition(.opacity)
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("Your picture, \(artifact.title)")
        .task {
            image = ArtifactImages.shared.cachedThumb(artifact)
            if let whole = await ArtifactImages.shared.whole(artifact) { withAnimation(Move.fade) { image = whole } }
        }
    }
}

/// Something an agent showed you, in the conversation: its picture, its title and what it is. A tap opens it full screen.
struct ArtifactCard: View {
    let artifact: Artifact
    let open: () -> Void
    @State private var image: CGImage?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Group {
                    if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                    else { Color(white: 0.15) }
                }
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    Text(artifact.label).font(.caption).foregroundStyle(Ink.quiet)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Ink.agent, in: RoundedRectangle(cornerRadius: M.bubble, style: .continuous))
            .frame(maxWidth: 300, alignment: .leading)
        }
        .buttonStyle(Pressable())
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { image = ArtifactImages.shared.cachedThumb(artifact); if image == nil { image = await ArtifactImages.shared.thumb(artifact) } }
    }
}

/// An agent asks to run something: what, and Allow or Deny (a spoken yes or no answers it too). On amber-tinted glass,
/// over the conversation.
struct ApprovalCard: View {
    let approval: Approval
    let name: String
    let decide: (Bool) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Pal.amber)
                Text("\(name) asks to use \(approval.tool)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            Text(approval.summary ?? approval.description).font(.subheadline).foregroundStyle(Color(white: 0.88))
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { withAnimation(Move.settle) { expanded.toggle() } }
            if let detail {
                Text(detail).font(.footnote.monospaced()).foregroundStyle(Color(white: 0.72))
                    .lineLimit(expanded ? nil : 4).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 10) {
                Button { Haptics.play(.click); decide(false) } label: {
                    Text("Deny").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color(white: 0.18), in: Capsule()).foregroundStyle(.white)
                }
                Button { Haptics.play(.click); decide(true) } label: {
                    Text("Allow").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.white, in: Capsule()).foregroundStyle(.black)
                }
            }
            .buttonStyle(Pressable())
        }
        .padding(14)
        .glassEffect(.regular.tint(Pal.amber.opacity(0.12)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The tool's input, readable (its command, file or address), unless the line above already says it.
    private var detail: String? {
        var d = approval.preview
        if let o = (try? JSONSerialization.jsonObject(with: Data(d.utf8))) as? [String: Any] {
            d = ["command", "file_path", "path", "url", "pattern"].lazy.compactMap { o[$0] as? String }.first
                ?? o.values.compactMap { $0 as? String }.joined(separator: "\n")
        }
        d = d.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = approval.summary ?? approval.description
        return d.isEmpty || said.contains(d) ? nil : d
    }
}

/// Beside the character at the bottom: what it's doing, in two lines of plain words. The first says the action ("Looking
/// at your photo", "Running tests", "Needs you"), shimmering while it's under way; the second says exactly what on (the
/// file, the command, the question) and, at work, for how long. Amber when it needs you, red when it's stuck. Idle,
/// nothing: the character alone.
struct StateLane: View {
    /// What the lane says, worked out by the screen.
    struct Words: Equatable {
        enum Tone: Equatable { case live, plain, amber, red, quiet }
        var main: String                                 // the action: "Running tests", "Needs you"
        var tone: Tone = .plain
        var detail: String? = nil                        // exactly what: "npm test", "Asks to read photo-1.jpg"
        var code = false                                 // the detail is a command or a path (the code face)
        var since: Date? = nil                           // at work: since when (after the detail)
    }
    let words: Words?
    var tap: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let w = words {
                main(w).id("main-" + w.main).transition(roll)
                if w.detail != nil || w.since != nil {
                    detail(w).id("detail-" + (w.detail ?? "")).transition(roll)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)                  // two lines in the character's height
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .animation(Move.or(Move.settle, reduced: reduceMotion), value: words)
        .accessibilityElement(children: .combine)
        .accessibilityAction { tap() }
        .accessibilityIdentifier("state-lane")
    }

    /// The new words come in from below and the old go up, like a line of a log.
    private var roll: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                              removal: .move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private func main(_ w: Words) -> some View {
        let font = Font.subheadline.weight(.semibold)
        switch w.tone {
        case .live: Shimmer(text: w.main, font: font, still: reduceMotion)
        case .amber: Text(w.main).font(font).foregroundStyle(Pal.amber).lineLimit(1)
        case .red: Text(w.main).font(font).foregroundStyle(Pal.red).lineLimit(1)
        case .quiet: Text(w.main).font(font).foregroundStyle(Ink.quiet).lineLimit(1)
        case .plain: Text(w.main).font(font).foregroundStyle(.white).lineLimit(1)
        }
    }

    private func detail(_ w: Words) -> some View {
        HStack(spacing: 0) {
            if let d = w.detail {
                Text(d).font(w.code ? .footnote.monospaced() : .footnote).lineLimit(1).truncationMode(.middle)
                    .layoutPriority(-1)
            }
            if let since = w.since {
                Text((w.detail == nil ? "" : " · ") as String) + Text(timerInterval: since...since.addingTimeInterval(86_400), countsDown: false)
            }
        }
        .font(.footnote).monospacedDigit().foregroundStyle(Ink.quiet)
    }

    // MARK: steps in words

    /// A file the iPhone sent, by the name it had there (the hub adds a time and a tag in front: 1791…-f7c9ca-photo-1.jpg).
    static func sentName(_ file: String) -> String? {
        guard let r = file.range(of: #"^\d{10,}-[0-9a-f]{6}-"#, options: .regularExpression) else { return nil }
        return String(file[r.upperBound...])
    }
    private static let pictures: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff"]

    /// A step as the hub names it ("Read hub.mjs", "Bash npm test", "Grep TODO") in words: the action, and what on.
    static func step(_ text: String, test: Bool = false) -> (main: String, detail: String?, code: Bool) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        let verb = parts.first ?? text, rest = parts.count > 1 ? parts[1] : nil
        guard let rest else { return (verb == "Thinking" ? verb : "Using \(verb)", nil, false) }
        switch verb {
        case "Read":
            if let name = sentName(rest) {
                let ext = (name as NSString).pathExtension.lowercased()
                return (pictures.contains(ext) ? "Looking at your photo" : "Reading your file", name, false)
            }
            return ("Reading a file", rest, true)
        case "Edit": return ("Editing a file", rest, true)
        case "Write": return ("Writing a file", rest, true)
        case "Grep": return ("Searching the code", "“\(rest)”", false)
        case "Glob": return ("Finding files", rest, true)
        case "WebFetch": return ("Opening a page", rest, false)
        case "WebSearch": return ("Searching the web", rest, false)
        case "Subagent": return ("Running a helper agent", rest, false)
        case "Bash":
            var c = rest                                    // the command alone, up to its first ; && | or redirect
            for sep in [" && ", " || ", ";", " | ", " 2>", " >", " <"] { if let r = c.range(of: sep) { c = String(c[..<r.lowerBound]) } }
            c = c.trimmingCharacters(in: .whitespaces)
            return (test ? "Running tests" : "Running a command", c.isEmpty ? rest : c, true)
        default: return ("Using \(verb)", rest, false)     // a tool from an MCP server: its server, then its name
        }
    }
}

/// Words with light passing across them, left to right, again and again: it's happening now.
struct Shimmer: View {
    let text: String
    let font: Font
    var still = false
    var body: some View {
        let base = Text(text).font(font).lineLimit(1)
        if still { base.foregroundStyle(.white) } else {
            base.foregroundStyle(Color.white.opacity(0.5))
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                        let p = (t.date.timeIntervalSinceReferenceDate / 1.7).truncatingRemainder(dividingBy: 1) * 1.8 - 0.4
                        base.foregroundStyle(.white)
                            .mask(LinearGradient(colors: [.clear, .black, .clear],
                                                 startPoint: UnitPoint(x: p - 0.35, y: 0.5), endPoint: UnitPoint(x: p + 0.35, y: 0.5)))
                    }
                }
        }
    }
}

/// The watch's crown, on the side of the character's window: roll it up or down with a finger and it turns like the
/// watch's (a flick keeps it spinning a moment). Each detent ticks; its ridges roll with it.
struct Crown: View {
    let turn: (Double) -> Void
    @State private var lastY = 0.0
    @State private var detent = 0.0
    @State private var roll = 0.0                    // where its ridges are, in detents
    @State private var held = false
    @State private var coast: Task<Void, Never>?
    private static let perDetent = 7.0               // points of finger travel for one detent

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3.5),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.18), Color(white: held ? 0.6 : 0.42), Color(white: 0.22)]),
                                           startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            // the ridges, rolling as it turns
            let gap = 3.0, off = (roll * gap).truncatingRemainder(dividingBy: gap)
            var y = -gap + (off < 0 ? off + gap : off)
            while y < size.height + gap {
                var line = Path(); line.move(to: CGPoint(x: 1.5, y: y)); line.addLine(to: CGPoint(x: size.width - 1.5, y: y))
                ctx.stroke(line, with: .color(.black.opacity(0.45)), lineWidth: 0.8)
                y += gap
            }
        }
        .frame(width: 9, height: 32)
        .scaleEffect(held ? 1.08 : 1)
        .animation(.snappy(duration: 0.15), value: held)
        .padding(.horizontal, 14).padding(.vertical, 18)          // a finger-sized place to grab it
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !held { held = true; coast?.cancel(); lastY = 0 }
                    let dy = v.translation.height - lastY
                    lastY = v.translation.height
                    step(-dy / Self.perDetent)
                }
                .onEnded { v in
                    held = false
                    flick(-v.velocity.height / Self.perDetent)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Crown")
        .accessibilityHint("Turns like the watch's Digital Crown")
        .accessibilityAdjustableAction { d in step(d == .increment ? 1 : -1) }
    }

    private func step(_ d: Double) {
        guard d != 0 else { return }
        roll += d; detent += d
        turn(d)
        if abs(detent) >= 1 { detent -= detent.rounded(.towardZero); Haptics.play(.click) }
    }
    /// Let go while moving: it keeps turning, slowing down.
    private func flick(_ v0: Double) {
        guard abs(v0) > 4 else { return }
        coast = Task { @MainActor in
            var v = min(60, max(-60, v0))
            while abs(v) > 1.5 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                step(v / 60)
                v *= 0.92
            }
        }
    }
}

