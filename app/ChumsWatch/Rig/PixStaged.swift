import SwiftUI

/// Pix (apple or banana) as a staged character: the rig's state, time, voice and caption go into PixStage, which
/// renders design/pix/pix.js's frames at the screen's own pixels. Pix types replies out in its own dialog box, so it
/// keeps the caption while speaking; the shared approval card is drawn over it (Pix shrinks above it).
final class PixStaged: Staged {
    static let apple = PixStaged(.apple), banana = PixStaged(.banana)
    private let stage: PixStage
    private var tools: [String] = []                      // the latest tool names (READ, EDIT, BASH …), oldest first
    private var ripe: Int?, ripeAcc = 0.0, crownIdle = 9.0, unripenT = 0.0   // the crown's ripeness, and its way back
    private var finger: CGPoint?, petT = 0.0
    private init(_ species: Pix.Species) { stage = PixStage(species: species) }

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 3.3]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { r.state == .speaking }
    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {}

    func step(_ r: Rig, _ dt: Double) {
        stage.step(dt)
        // a few seconds after the crown stops, it goes back to yellow a step at a time, then to its state's colours
        crownIdle += dt; petT = max(0, petT - dt)
        if let k = ripe, crownIdle > 3 {
            unripenT -= dt
            if unripenT <= 0 { unripenT = 0.32; ripe = k == 2 ? nil : k + (k < 2 ? 1 : -1) }
        }
        // tool calls float up as "+1 READ": take them as they arrive (the level world isn't running to take them)
        while !r.worlds.queue.isEmpty {
            let c = r.worlds.queue.removeFirst()
            tools.append(String(c.text.split(separator: " ").first ?? "TOOL").uppercased())
            if tools.count > 6 { tools.removeFirst() }
        }
    }

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        var s = PixStage.Scene(state: Pix.State(rawValue: r.state.rawValue) ?? .idle, stateT: r.stateT, t: r.t)
        s.approval = r.state == .approval
        s.voice = r.voice
        s.caption = r.state == .speaking ? r.caption : ""
        s.tools = tools.isEmpty ? ["READ", "EDIT", "BASH"] : tools
        s.ao = r.ao
        s.ripe = ripe
        s.petted = petT > 0
        if let f = finger { s.look = Double(f.x) < 99 ? -1 : 1 }
        stage.draw(ctx, size: CGSize(width: 198, height: 242), scale: r.pixelScale, s)
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}
    func hit(_ pt: CGPoint) -> Bool { stage.hit(pt) }
    func poke(_ r: Rig) { stage.poke() }
    func touched(_ r: Rig, at pt: CGPoint) { finger = pt }
    func dragged(_ r: Rig, at pt: CGPoint) { finger = pt }
    func released(_ r: Rig) { finger = nil }
    /// The crown ripens it (and back): a step every detent or so, a click at each.
    func crown(_ r: Rig, _ delta: Double) {
        if ripe == nil { ripe = 2 }
        ripeAcc += delta; crownIdle = 0; unripenT = 0.6
        while abs(ripeAcc) >= 1.1 {
            let up = ripeAcc > 0; ripeAcc += up ? -1.1 : 1.1
            let next = clamp(Double(ripe! + (up ? 1 : -1)), 0, Double(Pix.RIPENESS.count - 1))
            if Int(next) != ripe { ripe = Int(next); r.onHaptic?(.click) } else { ripeAcc = 0 }
        }
    }
    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {}
    func pet(_ r: Rig) { petT = 0.8 }
    func deny(_ r: Rig) {}
}
