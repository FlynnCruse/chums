import SwiftUI
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// Turns what the hub says (sessions, approvals, spoken lines, tool calls) and what you're doing
/// (holding to talk, waiting for a reply, hearing one) into the character's state, labels and captions.
/// Observable: a screen that shows `talk`, `agent` or `lines` redraws when they change. Everything `update()` keeps
/// for itself is ignored, so a frame never makes a view redraw.
@MainActor @Observable
final class Controller {
    let rig: Rig
    let hub: HubClient
    enum Talk { case none, listening, sending, speaking }
    var talk: Talk = .none
    @ObservationIgnored var demo: DemoDriver?
    /// The agent on screen: everything here (state, approvals, tool calls, replies) is that agent's. The others' lines
    /// go to `onBackground` (a tap on the wrist and a pill to go to them).
    var agent = Agents.fallback
    @ObservationIgnored var onBackground: ((AgentInfo, Spoken) -> Void)?
    @ObservationIgnored private var lastLineTap = -10.0           // rig time of the last line's tap on the wrist
    func info(_ id: String) -> AgentInfo {
        hub.state?.agents?.first { $0.id == id } ?? Agents.known.first { $0.id == id } ?? AgentInfo(id: id, name: id.capitalized, character: CharacterKind.fallback.rawValue, status: "offline", line: nil, needs: false)
    }


    @ObservationIgnored private var seenTools = Set<String>()
    @ObservationIgnored private var primed = false
    @ObservationIgnored private var asking = false                   // an approval of this agent's was up on the last pass
    @ObservationIgnored private var lastDoneAt = -99.0
    @ObservationIgnored private var echo = ""
    @ObservationIgnored private var echoUntil = 0.0
    /// A reply stays on screen at least this long, even if speech ends sooner (or is muted).
    @ObservationIgnored private var speakUntil = 0.0
    @ObservationIgnored private var speechDone = false
    @ObservationIgnored private var speechKind: String?
    @ObservationIgnored private var speechLabel = ""
    /// A problem worth showing while nothing else is (keyring mode failed, say).
    @ObservationIgnored var notice: String?
    /// Every line since launch, newest last: what you said, replies, answered approvals (the chat card).
    private(set) var lines: [Spoken] = []
#if DEBUG
    /// Screenshots for the README: a made-up conversation with `agent`, its last reply showing `chart`.
    func readmeDemo(_ agent: String, chart: Artifact?) {
        let said: [(Bool, String, Artifact?)] = [
            (true, "Rename the checkout button to Pay now.", nil),
            (false, "Renamed in all 3 places and pushed. The tests pass.", nil),
            (true, "Why did checkout drop last week?", nil),
            (false, "Discount codes with lowercase letters were rejected from October 3. I fixed it on the 8th. Here is checkout since then.", chart),
            (true, "Run the whole suite again before we ship.", nil),
        ]
        let start = Date().timeIntervalSince1970 * 1000 - 600_000
        for (i, l) in said.enumerated() {
            lines.append(Spoken(id: "readme-\(i)", session: agent, text: l.1, kind: l.0 ? "echo" : (l.2 == nil ? "done" : "artifact"),
                                audio: nil, at: start + Double(i) * 30_000, artifact: l.2, agent: agent))
        }
    }
    /// UI tests: a conversation of `n` made-up lines for each agent, an hour old, kept here only (nothing reaches the hub).
    func demoConversation(_ n: Int, agents: [String]) {
        let start = Date().timeIntervalSince1970 * 1000 - 3_600_000
        for a in agents {
            for i in 0..<n {
                let you = i % 2 == 0
                lines.append(Spoken(id: "demo-\(a)-\(i)", session: a,
                                    text: you ? "Line \(i): what is the state of the project today?" : "Line \(i): the tests pass and the build is green on every target.",
                                    kind: you ? "echo" : "done", audio: nil, at: start + Double(i) * 1000, artifact: nil, agent: a))
            }
        }
    }
#endif
    /// Tool calls since you last spoke: a reply or a finished turn is celebrated (done) only after real work, not
    /// after "Yes, I hear you."
    @ObservationIgnored private var toolsSinceOrder = 0
    func orderSent() { toolsSinceOrder = 0 }
    /// Set when you answer an approval on the watch; nil when it was answered some other way.
    @ObservationIgnored var verdictAllowed: Bool?
    /// The blocked line you've read (you opened the conversation): it stops holding the character in its blocked pose.
    @ObservationIgnored private var seenBlock: String?
    func seen() { if let b = hub.state?.sessions.first(where: { $0.name == agent && $0.status == "blocked" }) { seenBlock = b.lastLine } }
    /// A word on screen for a moment (talking canceled), where replies go.
    func note(_ text: String, seconds: Double = 2) { echo = text; echoUntil = rig.t + seconds }

    init(rig: Rig, hub: HubClient) { self.rig = rig; self.hub = hub }

    /// Called every frame before drawing.
    func update() {
        if let demo { demo.update(rig); return }
        let s = hub.state
        feedTools(s)
        let (rest, variant, label, caption, sub) = restFor(s)
        rig.restState = rest; rig.restVariant = variant

        // interactions and interruptions come first (this agent's; another's approval is its pill and the badge)
        if let a = s?.approvals.first(where: { $0.session == agent }) {
            rig.approvalTitle = a.summary ?? a.description
            rig.approvalDetail = a.tool == "Bash" ? a.description : a.tool
            rig.label = a.tool.uppercased()
            // the iPhone draws its own card under the character: there it stays full size and asks (needs)
            let asks: ChumsState = rig.chrome ? .approval : .needs
            if rig.state != asks { rig.setState(asks) }                     // the tap comes from HubClient.onApproval
            asking = true
            return
        }
        switch talk {
        case .listening:
            if rig.state != .listening { rig.setState(.listening) }
            // the talk bar at the top (× · your voice · ✓) says the rest: no caption
            rig.label = "TO \(info(agent).name.uppercased())"; rig.caption = ""; return
        case .sending:
            if rig.state != .thinking { rig.setState(.thinking) }
            rig.label = "THINKING"; rig.caption = ""; return
        case .speaking:
            if rig.state != .speaking { rig.setState(.speaking) }
            rig.label = speechLabel                                   // an approval may have borrowed the label
            if speechDone && rig.t >= speakUntil { finishSpeaking() }
            return
        case .none: break
        }
        if asking || rig.state == .approval {
            asking = false
            let allowed = verdictAllowed ?? echo.hasPrefix("Allowed")
            verdictAllowed = nil
            if allowed { rig.setState(.done, variant: true); rig.caption = echo.hasPrefix("Allowed") ? echo : "Allowed."; return }
            rig.settle()
        }
        if rig.inOneShot { return }
        if rig.state != rest || rig.variant != variant { rig.setState(rest, variant: variant) }
        rig.label = label
        rig.caption = rig.t < echoUntil ? echo : caption
        rig.subCaption = sub
        if let notice, rest == .idle || rest == .sleep { rig.caption = notice }
    }

    /// The resting state: what this agent's session is doing when nothing else is going on.
    private func restFor(_ all: HubState?) -> (ChumsState, Bool, String, String, String) {
        if !hub.connected && hub.lastError == nil { return (.sleep, false, "CONNECTING", "Looking for your Mac", "") }
        guard hub.connected, let all else { return (.sleep, true, "HUB OFFLINE", hub.lastError ?? "Can't reach your Mac", "") }
        let mine = all.sessions.filter { $0.name == agent }
        if mine.isEmpty { return (.sleep, false, "NOT RUNNING", "\(info(agent).name) isn't running on your Mac.", "") }
        if let b = mine.first(where: { $0.status == "blocked" && !(seenBlock != nil && $0.lastLine == seenBlock) }) {
            return (.blocked, false, "BLOCKED", b.lastLine ?? "It's stuck.", "Details on your Mac")
        }
        if let q = mine.first(where: { $0.status == "waiting" }) {
            return (.needs, true, "ASKS", q.lastLine ?? "It has a question.", "")
        }
        // rate limited: it resumes by itself. The watch rig has no waiting state yet, so it shows as blocked
        if mine.contains(where: { $0.status == "limited" }) {
            return (.blocked, false, "RATE LIMITED", "Rate limited. It resumes by itself.", "")
        }
        // compacting the context: shown as thinking until the watch rig gets the compacting state
        if mine.contains(where: { $0.status == "compacting" }) {
            return (.thinking, false, "COMPACTING", "", "")
        }
        if let w = mine.first(where: { $0.status == "working" && ($0.subagents ?? 0) > 0 }) {
            let n = w.subagents ?? 0
            return (.subagents, false, "\(n) SUBAGENT\(n == 1 ? "" : "S")", "", "")
        }
        if mine.contains(where: { $0.status == "working" }) {
            return (.working, false, "WORKING", "", "")
        }
        return (.idle, false, "", "", "")
    }
    /// What the hub calls itself on the lines it says on its own (an answered approval, which session to ask).
    static let hub = "Chums"

    private func feedTools(_ s: HubState?) {
        guard let tools = s?.tools else { return }
        for t in tools {
            if let ok = t.ok { rig.worlds.results[t.id] = ok }
            guard !seenTools.contains(t.id) else { continue }
            seenTools.insert(t.id)
            guard primed, t.session == agent else { continue }   // no history from before launch; only this agent's work
            if t.type == "stop" {
                if toolsSinceOrder > 0 && rig.t - lastDoneAt > 3 && talk == .none {
                    toolsSinceOrder = 0; lastDoneAt = rig.t; rig.caption = "Done."; rig.setState(.done); haptic(.success)
                }
                continue
            }
            toolsSinceOrder += 1
            rig.push(ToolCall(id: t.id, kind: ToolCall.Kind(rawValue: t.type) ?? .bash, text: t.text))
        }
        primed = true
    }

    // MARK: events from the hub and the talk flow

    /// A line that arrived while you were talking waits until you let go; it never takes over the microphone.
    @ObservationIgnored private var held: [(Spoken, (String) -> Void)] = []
    func flushHeld() {
        let lines = held; held = []
        for (l, s) in lines { spoken(l, speak: s) }
    }

    func spoken(_ line: Spoken, speak: @escaping (String) -> Void) {
        if !lines.contains(where: { $0.id == line.id }) { lines.append(line); if lines.count > 90 { lines.removeFirst() } }
        // said more than a minute ago (the app was closed, or the Mac out of reach): it joins the conversation quietly,
        // so reopening the app after a long talk on the iPhone isn't a tap for every line
        if let at = line.at, Date().timeIntervalSince1970 * 1000 - at > 60_000 { return }
        // another agent's: it doesn't take over this one; a tap on the wrist and its pill (what you told it isn't news)
        if line.owner != agent {
            if !["echo", "verdict", "refused"].contains(line.kind) {
                onBackground?(info(line.owner), line)
                if ["done", "question", "blocked"].contains(line.kind) { Alerts.post(alertTitle(line), line.text) }
            }
            return
        }
        if talk == .listening || talk == .sending, !["echo", "verdict", "refused"].contains(line.kind) {
            held.append((line, speak)); if held.count > 5 { held.removeFirst() }
            if ["done", "question", "blocked"].contains(line.kind) {
                Alerts.post(alertTitle(line), line.text)
            }
            return
        }
        switch line.kind {
        case "echo":
            echo = line.text; echoUntil = rig.t + 15; return       // what you said, in quotes, until the reply comes
        case "verdict", "refused":                                // a note, shown a moment: not a reply, never read aloud
            echo = line.text; echoUntil = rig.t + 3; return
        default: break
        }
        rig.caption = line.artifact == nil ? line.text : ""      // something it showed you: its pill says it instead
        echoUntil = 0
        if line.kind == "done" { lastDoneAt = rig.t }
        if ["done", "question", "blocked"].contains(line.kind) { Alerts.post(alertTitle(line), line.text) }
#if os(watchOS)
        // (the iPhone taps once for a new line itself, HomeView's soft tap); lines that land together tap once
        if rig.t - lastLineTap > 1.5 { lastLineTap = rig.t; haptic(line.kind == "blocked" ? .failure : line.kind == "question" ? .notification : .success) }
#endif
        talk = .speaking; speechDone = false; speechKind = line.kind
        speakUntil = rig.t + max(3, Double(line.text.count) / 24 + 2.5)      // typed at 24 characters a second, then read
        speechLabel = ""
        rig.label = speechLabel
        rig.setState(.speaking)
        speak(line.text)
    }

    /// A notification's title: which agent, and what happened.
    private func alertTitle(_ line: Spoken) -> String {
        let what = line.kind == "question" ? "asks" : line.kind == "blocked" ? "is stuck" : "is done"
        return "\(info(line.owner).name) \(what)"
    }

    func speechFinished(kind: String?) {
        guard talk == .speaking else { return }
        speechDone = true
        if rig.t >= speakUntil { finishSpeaking() }
    }
    private func finishSpeaking() {
        talk = .none; speechDone = false
        if speechKind == "done" && toolsSinceOrder > 0 { toolsSinceOrder = 0; lastDoneAt = rig.t; rig.setState(.done) } else { rig.settle() }
    }

    func haptic(_ h: Rig.Haptic) { Haptics.play(h) }
}

enum Haptics {
    private static var last = 0.0
    static func play(_ h: Rig.Haptic) {
#if !os(watchOS)
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }   // the iPhone's settings
#endif
        let now = Date().timeIntervalSinceReferenceDate
        if h == .click && now - last < 0.06 { return }            // a burst of impacts is one tap, not a buzz
        last = now
#if os(watchOS)
        let type: WKHapticType
        switch h {
        case .click, .settle: type = .click
        case .strong: type = .directionDown
        case .success: type = .success
        case .failure: type = .failure
        case .notification: type = .notification
        case .start: type = .start
        }
        WKInterfaceDevice.current().play(type)
#else
        switch h {
        case .click: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .strong: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .settle: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .notification: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
#endif
    }
}

/// Plays every state in turn with made-up tool calls, for trying it out without a session.
@MainActor
final class DemoDriver {
    private var i = -1, t = 0.0, last = Date()
    private let script: [(ChumsState, Bool, Double, String, String)] = [
        (.idle, false, 3, "", ""),
        (.listening, false, 2.6, "LISTENING", ""),
        (.thinking, false, 1.8, "THINKING", ""),
        (.working, false, 9, "WORKING", ""),
        (.subagents, false, 6, "3 SUBAGENTS", ""),
        (.approval, false, 3.5, "BASH", ""),
        (.done, true, 3, "ALLOWED", "Allowed."),
        (.working, false, 6, "WORKING", ""),
        (.speaking, false, 6, "", "All ten tests pass now. Nothing waits on you."),
        (.done, false, 4, "DONE", "Done."),
        (.needs, true, 4, "ASKS", "Which branch, main or dev?"),
        (.blocked, false, 4, "BLOCKED", "Signing failed twice."),
        (.sleep, false, 4, "", ""),
    ]
    func update(_ rig: Rig) {
        let now = Date(); t += now.timeIntervalSince(last); last = now
        rig.worlds.demo = true
        if i < 0 || (t > script[i].2 && !rig.W.busy) {
            i = (i + 1) % script.count; t = 0
            let s = script[i]
            rig.restState = s.0 == .done ? .working : s.0; rig.restVariant = false
            rig.label = s.3; rig.caption = s.4; rig.subCaption = s.0 == .blocked ? "Details on your Mac" : ""
            rig.approvalTitle = "rm -rf build"; rig.approvalDetail = "Clean the build folder"
            rig.setState(s.0, variant: s.1)
        }
    }
}
