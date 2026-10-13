import SwiftUI

/// Pix on the watch. The per-character runtime of the Character Lab's `pixChar` (the HTML prototype, not in the public
/// repository): the poke hop, the
/// reactions (a failed tool call glitches it, an interruption freezes the frame), the positions per state, and the
/// offscreen bitmap it is drawn into. Pix stages every state itself: it draws its own full screen (no world), and
/// the status label row goes on top of it.
///
///     let stage = PixStage(species: .apple)
///     // each frame, inside the Canvas:
///     stage.step(dt)
///     stage.draw(ctx, size: size, scale: 2, PixStage.Scene(state: .working, stateT: rig.stateT, t: rig.t, tools: ["Read", "Edit"]))
///     // on a tap / a hook event:
///     stage.poke()                      // a hop, eyes on you, for 0.45 s
///     stage.react(.fail, t: rig.t, stateT: rig.stateT)       // glitch bands for 0.5 s
///     stage.react(.interrupt, t: rig.t, stateT: rig.stateT)  // the frame freezes for 0.7 s
final class PixStage {
    enum Reaction { case fail, interrupt }

    /// What the character is told about the session, each frame.
    struct Scene {
        var state: Pix.State = .idle
        var approval = false              // the approval card is up: small, above it, as `needs` without the !
        var stateT = 0.0, t = 0.0
        var voice = 0.0                   // listening: microphone level 0…1
        var caption = ""                  // speaking: the reply being typed out
        var tools: [String] = []          // working: recent tool names, oldest first (READ, EDIT, BASH …)
        var subagents = 3
        var ao = false                    // always on: half brightness
        var free: CGPoint? = nil          // physics / launch: where the body is; nil = Pix's own positions
        var thumb = false                 // a settings thumbnail: no poke, no reaction, no bookkeeping
        var ripe: Int? = nil              // the crown's ripeness step (Pix.RIPENESS), nil = the state's own colours
        var look: Double? = nil           // a finger on the screen: −1 it's to the left, 1 to the right
        var petted = false                // stroked: a happy squint
        init() {}
        init(state: Pix.State, stateT: Double, t: Double) { self.state = state; self.stateT = stateT; self.t = t }
    }

    var species: Pix.Species
    /// Where the body is, in design points, for hit tests.
    private(set) var at = CGPoint(x: 99, y: 118)
    private var pokeT = 9.0                    // seconds since the last poke
    private var re: (kind: Reaction, t: Double, at: (Double, Double))?
    private var rasters: [Pix.Raster] = []
    private var which = 0
    private static let pokeable: Set<Pix.State> = [.idle, .thinking, .working, .needs, .listening]
    private static let screen = CGRect(x: 0, y: 36, width: 198, height: 206)

    init(species: Pix.Species) { self.species = species }

    func poke() { pokeT = 0 }
    /// A failed tool call glitches it; an interruption freezes it like a paused frame. `t` and `stateT` are the
    /// rig's clocks at that moment (the frozen frame keeps showing them).
    func react(_ kind: Reaction, t: Double, stateT: Double) { re = (kind, 0, (t, stateT)) }
    func step(_ dt: Double) {
        pokeT += dt
        if re != nil { re!.t += dt; if re!.t > 1.2 { re = nil } }
    }
    /// The Lab's hit box: the apple is 53 pt wide and 60 pt up and down from `at`; the banana 45 and 69.
    func hit(_ pt: CGPoint) -> Bool {
        let (hx, top, bottom) = species == .apple ? (53.0, 60.0, 60.0) : (45.0, 69.0, 69.0)
        return abs(pt.x - at.x) < hx + 6 && pt.y > at.y - top - 6 && pt.y < at.y + bottom + 6
    }
    /// waiting: when it looks up at the clock (the Lab's clockLook), for anything that wants to play along.
    static func clockLook(_ stateT: Double) -> Bool { let p = stateT.truncatingRemainder(dividingBy: 4); return p > 1.2 && p < 2.6 }

    /// Pix's inputs for this frame, as pixChar builds them.
    private func params(_ s: Scene) -> (Pix.Params, cy: Double) {
        let free = !s.thumb && s.free != nil
        let cx = free ? Double(s.free!.x) : 99
        var cy = free ? Double(s.free!.y) : 118, px = 7.0
        if !free && s.state == .needs { cy = 146 }                    // room above the head for the !
        if !free && s.state == .working { cy = 134 }                  // room above it for the tool calls rising
        let approval = !free && s.approval
        if approval { cy = 80; px = 3 }                               // small, above the card; the card is the request, so no !
        let poking = !s.thumb && pokeT < 0.45 && Self.pokeable.contains(s.state)
        let hop = poking ? Pix.jsRound(sin(pokeT / 0.45 * Double.pi) * 8) : 0
        if !s.thumb { at = CGPoint(x: cx, y: cy - hop) }
        let frozen = !s.thumb && re?.kind == .interrupt && re!.t < 0.7
        var p = Pix.Params()
        p.species = species; p.cx = cx; p.cy = cy - hop; p.px = px
        p.t = frozen ? re!.at.0 : s.t
        p.state = poking ? .idle : approval ? .needs : s.state
        p.stateT = frozen ? re!.at.1 : s.stateT
        p.voice = s.voice
        p.text = s.caption.isEmpty ? nil : s.caption
        p.tools = s.tools
        p.subagents = s.subagents
        p.screen = Self.screen
        p.room = approval ? 60 : 150
        p.bang = !approval
        p.eyeMode = poking || (re?.kind == .fail && re!.t < 0.5) ? .cam : nil
        if let k = s.ripe, k >= 0, k < Pix.RIPENESS.count {
            p.ripe = Pix.RIPENESS[k]
            // green it's alert, ripe it's pleased, overripe it's had enough
            if p.eyeMode == nil { p.eyeMode = [Pix.EyeMode.cam, .cam, nil, nil, .happy, .happy, .squint][k] }
        }
        if s.petted { p.eyeMode = .happy }
        if let l = s.look, !s.petted { p.look = l; if p.eyeMode == nil && p.state == .idle { p.eyeMode = .side } }
        return (p, cy)
    }

    /// Render the frame into `r` with the design space mapped by `m` (design pt → pixels).
    func render(_ s: Scene, into r: Pix.Raster, transform m: Pix.Matrix) {
        let (p, cy) = params(s)
        r.fill(Pix.RGBA(0, 0, 0))
        let g = Pix.G(r); g.m = m
        Pix.draw(g, p)
        // glitch: three bands of rows tear sideways for half a second
        if !s.thumb, let re, re.kind == .fail, re.t < 0.5 {
            let seed = Int(floor(re.t * 20))
            for i in 0..<3 {
                let y0 = cy - 60 + Double((seed * 37 + i * 53) % 110), h = Double(6 + ((seed + i) % 3) * 5), dx = Double(((seed + i) % 2 != 0 ? 1 : -1) * (5 + i * 3))
                g.save(); g.clipRect(0, y0, 198, h); g.fill = Pix.RGBA(0, 0, 0); g.fillRect(0, y0, 198, h)
                g.translate(dx, 0); Pix.draw(g, p); g.restore()
            }
        }
        if s.ao { Self.alwaysOn(r) }
    }

    /// Dimmed (always on): its own colors at half brightness.
    static func alwaysOn(_ r: Pix.Raster) {
        var i = 0
        for _ in 0..<(r.w * r.h) {
            let p = r.data + i
            p[0] >>= 1; p[1] >>= 1; p[2] >>= 1
            i += 4
        }
    }

    /// Draw into a SwiftUI canvas of `size` points on a screen with `scale` pixels per point: the 198 × 242 design
    /// space is fitted and centred like Renderer.fit, rendered at the screen's pixels, and shown 1:1.
    func draw(_ ctx: GraphicsContext, size: CGSize, scale: Double, _ s: Scene) {
        let pw = max(1, Int((size.width * scale).rounded())), ph = max(1, Int((size.height * scale).rounded()))
        if rasters.count != 2 || rasters[0].w != pw || rasters[0].h != ph { rasters = [Pix.Raster(w: pw, h: ph), Pix.Raster(w: pw, h: ph)] }
        which = (which + 1) % 2                                      // double buffered: the canvas may still read the last one
        let r = rasters[which]
        let fit = min(size.width / 198, size.height / 242), ox = (size.width - 198 * fit) / 2, oy = (size.height - 242 * fit) / 2
        render(s, into: r, transform: Pix.Matrix(a: fit * scale, b: 0, c: 0, d: fit * scale, e: ox * scale, f: oy * scale))
        guard let img = r.image() else { return }
        ctx.draw(Image(decorative: img, scale: 1).resizable().interpolation(.none), in: CGRect(origin: .zero, size: size))
    }
}
