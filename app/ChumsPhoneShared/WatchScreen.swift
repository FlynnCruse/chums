import SwiftUI
import UIKit

/// The watch's screen for one agent, as a picture: the same character, faces, status, caption and approval card the
/// watch draws (Renderer, with its chrome), for the widgets, which can't animate. The rig runs a moment first, so the
/// character has settled into its state.
@MainActor enum WatchScreen {
    static func image(_ agent: WAgent, in state: WState?, size: CGSize, scale: CGFloat = 3) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let r = Rig()
        r.cardControls = false                       // the widget's own Deny and Allow answer it
        if let k = CharacterKind(id: agent.character) { r.character = k }
        let look = Self.look(agent, state)
        if let a = state?.approval(for: agent.id) {
            r.approvalTitle = a.summary ?? a.description
            r.approvalDetail = a.tool == "Bash" ? a.description : a.tool
        }
        r.restState = look.state
        r.setState(look.state)
        r.label = look.label
        r.caption = look.caption
        r.faces = faces(agent, state)
        for _ in 0..<45 { r.tick(1.0 / 30) }
        let view = Canvas { ctx, sz in Renderer.draw(r, ctx, size: sz) }
            .frame(width: size.width, height: size.height)
            .environment(\.displayScale, scale)
        func draw() -> UIImage? { let ir = ImageRenderer(content: view); ir.scale = scale; return ir.uiImage }
        // Stretch's frames are decoded off the main thread: the first drawing asks for them, a second one has them
        if r.character == .stretch { _ = draw(); try? await Task.sleep(for: .milliseconds(300)) }
        return draw()
    }

    /// The watch's state, status and caption for an agent (Controller.restFor, from what the widgets get).
    static func look(_ a: WAgent, _ s: WState?) -> (state: ChumsState, label: String, caption: String) {
        guard let s else { return (.sleep, "HUB OFFLINE", "Can't reach your Mac") }
        if let ap = s.approval(for: a.id) { return (.approval, ap.tool.uppercased(), "") }
        switch a.status {
        case "offline": return (.sleep, "NOT RUNNING", "\(a.name) isn't running on your Mac.")
        case "blocked": return (.blocked, "BLOCKED", a.line ?? "It's stuck.")
        case "limited": return (.blocked, "RATE LIMITED", "Rate limited. It resumes by itself.")
        case "compacting": return (.thinking, "COMPACTING", "")
        case "working": return (.working, "WORKING", "")
        default: return a.needs || a.status == "waiting" ? (.needs, "ASKS", a.line ?? "It has a question.") : (.idle, "", "")
        }
    }

    /// The faces at the top left, as on the watch: this agent, then at most two others, the ones that need you first.
    static func faces(_ a: WAgent, _ s: WState?) -> [(character: String, needs: Bool)] {
        let others = (s?.byUrgency ?? []).filter { $0.id != a.id }
        return [(a.character, false)] + others.prefix(2).map { ($0.character, $0.needs) }
    }
}
