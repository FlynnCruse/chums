import SwiftUI

/// Ray: a flat golden sun with ten long wavy arms, traced one to one from its character sheet (design/characters, the
/// squiggly sun): a small round middle, each arm its own S-curve, wide where it leaves the middle, narrowing to a slightly
/// pointed round tip. Big cream eyes close together, black pupils and a black mouth, every face taken from the sheet.
/// The arms are never still: a slow wave runs out along each one, its own phase, and the mood changes their shape (the
/// sheet's jagged angry arms, its melting asleep arms, its pinwheel dizzy arms) and how fast they move.
///   idle: ● ● ‿, a slow wave · listening: the surprised face, its O opening with your voice · thinking: tilted, eyes up
///   and to the right, a small o, a ? · working: turning, eyes reading, an arm reaching out at each tool call ·
///   subagents: three small suns going round it · speaking: its mouth opens with its voice · done: ◠ ◠ D, a hop, the arms
///   shake and the sheet's motion strokes fly round it · needs you: the sad face, a knock · blocked: angry, the jagged
///   arms, brows, a zigzag mouth · dizzy: spirals, a wavy mouth, the pinwheel arms · sleep: the arms melt down, — — and a
///   small yawn that breathes
///   tap: a wink with its tongue out, the arms snap in · poke it often: angry for a moment · drag: it follows your finger,
///   the arms trailing · pet: ◠ ◠ ‿, the arms go slow · crown: it turns, the arms trailing; turned fast it gets dizzy ·
///   shake: the arms flop about
final class RayStage: Staged {
    static let shared = RayStage()

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 2.6, .dizzy: 3.4]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { false }
    var calm: Bool { t - busyAt > 1.2 }

    // the sheet's colours
    static let yellow = Color(red: 242 / 255, green: 174 / 255, blue: 8 / 255)
    static let cream = Color(red: 249 / 255, green: 236 / 255, blue: 205 / 255)
    static let ink = Color(red: 4 / 255, green: 2 / 255, blue: 1 / 255)
    static let pink = Color(red: 230 / 255, green: 78 / 255, blue: 75 / 255)

    /// The middle's radius in pt. Everything in SolArt is in these units, centred on the middle.
    static let RC = 37.0
    private static let K = SolArt.K

    // MARK: how the arms move, per state

    private struct Body {
        var amp = 0.24, speed = 1.5, len = 0.0, turn = 0.0, tilt = 0.0
        var shape = SIMD4<Double>(1, 0, 0, 0)            // base, angry, melt, dizzy
        // how the arms hold themselves: lifted toward you, curled one way, hanging down, shivering, the top ones waving
        var up = 0.0, curl = 0.0, droop = 0.0, shiver = 0.0, wave = 0.0
    }
    private func body(_ s: ChumsState) -> Body {
        switch s {
        case .idle: return Body()
        case .listening: return Body(amp: 0.2, speed: 2.4, len: 0.05, up: 0.4)
        case .thinking: return Body(amp: 0.14, speed: 0.9, tilt: -9 * DEG, curl: 0.5)
        case .working: return Body(amp: 0.42, speed: 4.2, turn: 0.45, curl: -0.3)
        case .subagents: return Body(amp: 0.3, speed: 2)
        case .speaking: return Body(amp: 0.26, speed: 2.2)
        case .done: return Body(amp: 0.36, speed: 2.4, len: 0.03, up: 0.25)
        case .needs: return Body(amp: 0.18, speed: 1.3, up: 0.15, wave: 1)
        case .approval: return Body(amp: 0.22, speed: 1.6, droop: 0.4)
        case .blocked: return Body(amp: 0.08, speed: 1.2, shape: SIMD4(0, 1, 0, 0), shiver: 1)
        case .dizzy: return Body(amp: 0.3, speed: 2.6, shape: SIMD4(0, 0, 0, 1))
        case .sleep: return Body(amp: 0.12, speed: 0.6, shape: SIMD4(0, 0, 1, 0), droop: 0.2)
        }
    }

    // MARK: faces (every part a shape from the sheet; "" is none)

    private struct Face {
        var wl = "wSurL", wr = "wSurR", ll = "", lr = "", bl = "", br = "", mouth = "smile", tongue = ""
        var pl = "pNeuL", pr = "pNeuR"
        var look = 1.0                                     // how much the pupils follow the gaze
        var spirals = false, question = false
        var clip = true                                    // pupils kept inside the whites (the wink's sits over the edge)
    }
    private func face(_ s: ChumsState) -> Face {
        switch s {
        case .idle, .subagents, .speaking: return Face()
        case .listening: return Face(mouth: "O", pl: "pSurL", pr: "pSurR", look: 0.6)
        case .thinking: return Face(wl: "wThkL", wr: "wThkR", mouth: "dot", pl: "pThkL", pr: "pThkR", look: 0, question: true)
        case .working: return Face(mouth: "flat")
        case .done: return Face(wl: "", wr: "", ll: "happyL", lr: "happyR", mouth: "D")
        case .needs: return Face(wl: "wSadL", wr: "wSadR", mouth: "frown", pl: "pSadL", pr: "pSadR", look: 0.4)
        case .approval: return Face(mouth: "dotC")
        case .blocked: return Face(wl: "wAngL", wr: "wAngR", bl: "browL", br: "browR", mouth: "zig", pl: "pAngL", pr: "pAngR", look: 0)
        case .dizzy: return Face(wl: "", wr: "", mouth: "wavy", spirals: true)
        case .sleep: return Face(wl: "", wr: "", ll: "dashL", lr: "dashR", mouth: "yawn")
        }
    }
    private static let wink = Face(wl: "wWinkL", wr: "", lr: "winkR", mouth: "winkMouth", tongue: "tongue", pl: "pWinkL", pr: "pWinkL", look: 0, clip: false)
    private static let content = Face(wl: "", wr: "", ll: "happyL", lr: "happyR", mouth: "smile")
    private static let startled = Face(mouth: "O", pl: "pSurL", pr: "pSurR", look: 0)
    private static let cross = Face(wl: "wAngL", wr: "wAngR", bl: "browL", br: "browR", mouth: "zig", pl: "pAngL", pr: "pAngR", look: 0)

    // MARK: the parts

    /// A face part: its outline blends from one shape into the next on a spring (all of them 64 points, leftmost first,
    /// clockwise, so any two blend), or shrinks to nothing and grows back.
    private struct Part {
        var from: [P2], to: [P2], b = 1.0, bv = 0.0, name = "", none = true
        var shape: [P2] { b >= 1 ? to : Strokes.mix(from, to, b) }
        var shown: Bool { !(none && b > 0.98) }
        mutating func set(_ n: String) {
            guard n != name else { return }
            let cur = shape
            if n.isEmpty {
                let c = RayStage.centroid(cur); from = cur; to = [P2](repeating: c, count: cur.count); none = true
            } else {
                let g = SolArt.glyph(n)
                from = none && b > 0.98 ? [P2](repeating: RayStage.centroid(g), count: g.count) : cur
                to = g; none = false
            }
            name = n; b = 0; bv = 0
        }
    }
    private static func centroid(_ p: [P2]) -> P2 { p.reduce(P2.zero, +) / Double(max(1, p.count)) }
    private static let empty = [P2](repeating: .zero, count: SolArt.N)
    // whites L R, closed-eye lines L R, brows L R, mouth, tongue
    private var parts: [Part] = (0..<8).map { _ in Part(from: RayStage.empty, to: RayStage.empty) }
    private var pupils: [SIMD4<Double>] = [SolArt.pupil("pNeuL"), SolArt.pupil("pNeuR")]   // cx cy rx ry
    private var look = 1.0
    private var spiralsK = 0.0, questionK = 0.0
    /// Where the thinking dots sit: the middle of the sheet's question mark (up and to the right).
    private static let thinkAt: P2 = { let g = SolArt.glyph("qHook") + SolArt.glyph("qDot"); return g.reduce(P2.zero, +) / Double(max(1, g.count)) }()
    private var shown = Face(), shownKey = "", faceStarted = false

    // MARK: state

    private struct Arm { var phase, gain: Double; var flop = 0.0, fv = 0.0, len = 0.0, lv = 0.0, grab = 0.0 }
    private var arms: [Arm] = (0..<10).map { (i: Int) -> Arm in
        let x = Double(i)
        let ph: Double = x * 2.399 + 0.7 * sin(x * 1.7)
        let gn: Double = 0.82 + 0.18 * (1 + sin(x * 2.9 + 1))
        return Arm(phase: ph, gain: gn)
    }
    private var cur = Body()
    private var shapeV = SIMD4<Double>(0, 0, 0, 0)
    private var blend: [Double] = SolArt.base, blendKey = SIMD4<Double>(1, 0, 0, 0)
    private var state: ChumsState = .idle
    private var t = 0.0, busyAt = 0.0
    private var wavePhase = 0.0, turn = 0.0, spinV = 0.0, crownIdle = 9.0, fastFor = 0.0
    private var squash = (k: 0.0, v: 0.0), hop = (y: 0.0, v: 0.0), bump = 0.0
    private var center = P2(99, 128), cv = P2.zero, fingerOff = P2.zero, dragV = P2.zero
    private var finger: CGPoint?
    private var trauma = 0.0, knock = 0.0, nextTool = 0.8, toolFlash = 0.0
    private var winkT = 0.0, crossT = 0.0, petT = 0.0, startT = 0.0, pokes: [Double] = []
    private var minis = 0.0
    private var scale = 1.0, scaleV = 0.0
    private var tilt = 0.0

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        state = s
        // every change: a little gather first (the arms draw in, it squashes), then it springs into the new state
        if prev != s && prev != nil {
            for i in arms.indices { arms[i].lv -= 1.5; arms[i].fv += Double(i % 2 == 0 ? 1 : -1) * 0.8 }
            squash.v -= 1.4
        }
        switch s {
        case .done:
            hop.v = -240; squash.v += 3
            for i in arms.indices { arms[i].fv += rnd(-5, 5) }
        case .listening: squash.v += 2
        case .needs: knock = 0
        case .blocked: squash.v -= 2
        default: break
        }
        busyAt = t
    }

    func step(_ r: Rig, _ dt0: Double) {
        let dt = min(dt0, 0.05)
        t += dt
        guard !r.ao else {
            // dimmed: drawn about once a second, so nothing in flight; it rests in its state's pose
            winkT = 0; crossT = 0; startT = 0; petT = 0; trauma = 0; spinV = 0; hop = (0, 0); squash = (0, 0); bump = 0
            for i in arms.indices { arms[i].flop = 0; arms[i].fv = 0; arms[i].len = 0; arms[i].lv = 0; arms[i].grab = 0 }
            return
        }
        var target = body(state)
        // the voice, done's shake, being petted, poked too often
        if state == .listening { target.len += r.voice * 0.12; target.amp += r.voice * 0.25 }
        if state == .speaking { target.amp += r.voice * 0.3; target.len += r.voice * 0.08 }
        if state == .done && r.stateT < 1.5 { let k = 1 - r.stateT / 1.5; target.amp += 0.3 * k; target.speed += 9 * k }
        if petT > 0 { target.amp *= 0.6; target.speed *= 0.5 }
        if crossT > 0 { target.shape = SIMD4(0.45, 0.55, 0, 0); target.amp = 0.1 }
        if startT > 0 { target.shape = SIMD4(0.75, 0, 0.25, 0); target.amp = 0.3; target.speed = 3 }
        let e = min(1, dt * 3.5)
        cur.amp += (target.amp - cur.amp) * e; cur.speed += (target.speed - cur.speed) * e
        cur.len += (target.len - cur.len) * e; cur.turn += (target.turn - cur.turn) * min(1, dt * 1.5)
        cur.up += (target.up - cur.up) * e; cur.curl += (target.curl - cur.curl) * e; cur.droop += (target.droop - cur.droop) * e
        cur.shiver += (target.shiver - cur.shiver) * e; cur.wave += (target.wave - cur.wave) * e
        tilt += (target.tilt + (state == .dizzy ? sin(t * 2.2) * 0.12 : 0) - tilt) * min(1, dt * 4)
        wavePhase += cur.speed * dt
        // the arms' shape: the sheet's shapes, on a spring (melting takes its time)
        let ws = TAU * (state == .sleep ? 0.9 : 1.6)
        let acc: SIMD4<Double> = (target.shape - cur.shape) * (ws * ws) - shapeV * (2 * 0.62 * ws)
        shapeV += acc * dt; cur.shape += shapeV * dt
        // the crown turns it (and the state's own slow turn); fast for a second, dizzy
        crownIdle += dt
        spinV *= exp(-dt * 1.3)
        turn += (cur.turn + spinV) * dt
        // done turning: it comes back round to the sheet's pose (the nearest whole turn)
        if target.turn == 0 && abs(spinV) < 0.8 {
            let home = (turn / TAU).rounded() * TAU
            turn += (home - turn) * min(1, dt * (abs(spinV) < 0.2 ? 1.6 : 0.6))
        }
        if abs(spinV) > 9 && crownIdle < 0.2 && state != .dizzy { fastFor += dt } else { fastFor = 0 }
        if fastFor > 1 { fastFor = 0; r.setState(.dizzy) }
        trauma = max(0, trauma - dt * 0.75)
        winkT = max(0, winkT - dt); crossT = max(0, crossT - dt); petT = max(0, petT - dt); startT = max(0, startT - dt)
        toolFlash = max(0, toolFlash - dt)
        // each arm: a flop (a shake, a turn, a drag pulls it behind), its length (a tap snaps them in, a tool call reaches)
        for i in arms.indices {
            let wf = TAU * (1.9 + Double(i % 3) * 0.25)
            arms[i].fv += (-wf * wf * arms[i].flop - 2 * 0.16 * wf * arms[i].fv + trauma * rnd(-1, 1) * 160) * dt
            arms[i].flop = clamp(arms[i].flop + arms[i].fv * dt, -2.2, 2.2)
            let wl = TAU * 2.6
            arms[i].lv += (-wl * wl * arms[i].len - 2 * 0.3 * wl * arms[i].lv) * dt
            arms[i].len = clamp(arms[i].len + arms[i].lv * dt, -0.6, 0.6)
            arms[i].grab = max(0, arms[i].grab - dt * 1.8)
        }
        let wsq = TAU * 3
        squash.v += (-wsq * wsq * squash.k - 2 * 0.22 * wsq * squash.v) * dt; squash.k = clamp(squash.k + squash.v * dt, -0.25, 0.25)
        hop.v += 1000 * dt; hop.y += hop.v * dt
        if hop.y > 0 { if hop.v > 100 { squash.v -= hop.v / 160 }; hop.y = 0; hop.v = 0 }
        bump = max(0, bump - dt * 3)
        // where it is: home, a finger pulling it
        var home = P2(99, state == .approval ? 74 : state == .listening ? 140 : state == .sleep ? 134 : 128)
        // a finger pulls it toward itself: eased in and out, so letting go never jerks it
        let fo: P2 = finger.map { P2(clamp(($0.x - 99) * 0.35, -30, 30), clamp(($0.y - 128) * 0.3, -26, 26)) } ?? .zero
        fingerOff += (fo - fingerOff) * min(1, dt * 6); home += fingerOff
        let wc = TAU * 2.2
        let pull: P2 = (home - center) * (wc * wc), damp: P2 = cv * (wc * 1.1)
        cv += (pull - damp) * dt; center += cv * dt
        dragV += (cv - dragV) * min(1, dt * 7)
        // the work: each tool call, the arm at the top reaches out and the eyes glance up at it
        nextTool -= dt
        if nextTool <= 0 && (!r.worlds.queue.isEmpty || state == .working), let c = r.worlds.nextEvent(r) {
            nextTool = r.worlds.queue.isEmpty ? rnd(1.4, 2.4) : 0.5
            if c.kind != .stop, let i = arms.indices.min(by: { armOff($0, -Double.pi / 2) < armOff($1, -Double.pi / 2) }) {
                arms[i].grab = 1; arms[i].lv += 3; toolFlash = 0.5
            }
        }
        // needs you: a knock every few seconds
        if state == .needs {
            let was = knock; knock += dt; if knock >= 3.2 { knock = 0 }
            if was < 0.2 && knock >= 0.2 { bump = 1; squash.v += 2.5; r.onHaptic?(.strong) }
        }
        minis += ((state == .subagents ? 1 : 0) - minis) * min(1, dt * 3)
        // small for an approval: eased there and back (with a little overshoot)
        let wsc = TAU * 2.2, sgoal = state == .approval ? 0.5 : state == .subagents ? 0.8 : 1.0
        scaleV += (wsc * wsc * (sgoal - scale) - 2 * 0.7 * wsc * scaleV) * dt; scale += scaleV * dt
        stepFace(r, dt)
        let moving = finger != nil || abs(spinV) > 0.1 || trauma > 0.01 || hop.v != 0 || abs(squash.v) > 0.05 || simd_length(cv) > 2
            || winkT > 0 || crossT > 0 || petT > 0 || startT > 0 || minis > 0.02 || parts.contains { abs($0.bv) > 0.05 }
            || simd_length(shapeV) > 0.02 || !(state == .idle || state == .sleep || state == .needs || state == .approval || state == .thinking)
        if moving { busyAt = t }
    }
    private func armOff(_ i: Int, _ a: Double) -> Double { abs(remainder(SolArt.armAngle[i] + turn + tilt - a, TAU)) }

    private func stepFace(_ r: Rig, _ dt: Double) {
        var f = face(state)
        if state == .done && r.stateT > 1.8 { f = Self.content }
        if petT > 0 && state != .sleep && state != .dizzy { f = Self.content }
        if trauma > 0.12 && state != .dizzy { f = Self.startled }      // shaken: whoa
        if startT > 0 { f = Self.startled }
        if winkT > 0 { f = Self.wink }
        if crossT > 0 { f = Self.cross }
        shown = f
        let names = [f.wl, f.wr, f.ll, f.lr, f.bl, f.br, f.mouth, f.tongue]
        for i in 0..<8 {
            parts[i].set(names[i])
            if !faceStarted { parts[i].b = 1; parts[i].from = parts[i].to }
        }
        if !faceStarted { for k in 0..<2 { pupils[k] = [SolArt.pupil(f.pl), SolArt.pupil(f.pr)][k] }; look = f.look }
        faceStarted = true
        for i in 0..<8 {
            let w = TAU * 4.2
            parts[i].bv += (-w * w * (parts[i].b - 1) - 2 * 0.66 * w * parts[i].bv) * dt
            parts[i].b += parts[i].bv * dt
        }
        let e = min(1, dt * 12)
        let pt: [SIMD4<Double>] = [SolArt.pupil(f.pl), SolArt.pupil(f.pr)]
        for i in 0..<2 { pupils[i] += (pt[i] - pupils[i]) * e }
        look += (f.look - look) * e
        spiralsK += ((f.spirals ? 1 : 0) - spiralsK) * min(1, dt * 8)
        questionK += ((f.question ? 1 : 0) - questionK) * min(1, dt * 4)
    }

    // MARK: input

    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        let e = max(0, sqrt(ax * ax + ay * ay + az * az) - 0.9)
        trauma = min(1, trauma + e * e * 0.25)
        // the arms swing behind the watch's moves (above a little, so walking doesn't keep them busy)
        let lat = sqrt(ax * ax + ay * ay)
        if lat > 0.3 {
            let k = min(2.5, lat - 0.3) * 6.5
            for i in arms.indices {
                let ang = SolArt.armAngle[i] + turn + tilt
                let torque = cos(ang) * (-ay) - sin(ang) * (-ax)              // the push across the arm
                arms[i].fv += torque / max(lat, 1e-6) * k
            }
            busyAt = t
        }
        if e > 0 { busyAt = t }
    }
    func crown(_ r: Rig, _ delta: Double) { spinV = clamp(spinV + delta * 1.6, -14, 14); crownIdle = 0; busyAt = t }
    func touched(_ r: Rig, at pt: CGPoint) { finger = pt; busyAt = t }
    func dragged(_ r: Rig, at pt: CGPoint) { finger = pt; busyAt = t }
    func released(_ r: Rig) { finger = nil }
    func poke(_ r: Rig) {
        pokes = pokes.filter { t - $0 < 3 } + [t]
        for i in arms.indices { arms[i].lv -= 5.5 }                    // the arms snap in (and spring back out)
        squash.v -= 3
        switch state {
        case .sleep:                                                   // woken with a start, then back to sleep
            startT = 1.3; squash.v -= 1.5
        case .blocked:                                                 // crosser
            crossT = max(crossT, 1.2); for i in arms.indices { arms[i].fv += rnd(-2, 2) }
        case .dizzy:
            for i in arms.indices { arms[i].fv += rnd(-3, 3) }
        default:
            if pokes.count >= 4 { pokes = []; crossT = 2.2; winkT = 0; squash.v -= 1 }
            else if crossT <= 0 { winkT = 1.1 }
        }
        busyAt = t
    }
    func pet(_ r: Rig) { petT = 0.45; busyAt = t }
    func deny(_ r: Rig) { crossT = 1.2 }
    func hit(_ pt: CGPoint) -> Bool {
        simd_length(P2(pt.x, pt.y) - center) < Self.RC * (state == .approval ? 1.2 : 2.1)
    }

    // MARK: drawing

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        // dimmed: drawn as one layer at half strength (piece by piece, the overlaps would show through lighter)
        if r.ao { var c = ctx; c.opacity = 0.5; c.drawLayer { l in self.paint(r, l) } } else { paint(r, ctx) }
    }

    private func paint(_ r: Rig, _ ctx: GraphicsContext) {
        let p = r.pose(raw: true)
        let g = ctx
        let RC = Self.RC
        let scale = self.scale
        let breathe = state == .sleep ? 0.012 * sin(t * TAU / 4.2) : 0
        let pulse = 1 + 0.05 * bump
        var b = g
        b.translateBy(x: center.x, y: center.y + hop.y)
        b.scaleBy(x: scale * pulse * (1 - squash.k * 0.5 - breathe), y: scale * pulse * (1 + squash.k + breathe))
        // the arms, from the sheet's shapes, bent by their wave
        refreshBlend()
        let pts = deformed(scale: RC, rot: turn + tilt, drag: dragV, wave: true)
        b.fill(Strokes.smoothClosed(pts), with: .color(Self.yellow))
        // the face
        var fc = b
        fc.rotate(by: .radians(tilt * 0.6))
        fc.scaleBy(x: RC, y: RC)
        drawFace(fc, r: r, pose: p)
        // thinking: three dots up and to the right, swelling one after another (on it). Not the sheet's question mark,
        // which read as "I didn't get that" right after you'd spoken
        if questionK > 0.02 {
            var q = b; q.rotate(by: .radians(tilt * 0.3 + sin(t * 1.3) * 0.05)); q.scaleBy(x: RC, y: RC)
            q.translateBy(x: 0, y: (1 - questionK) * 0.3 + sin(t * 1.6) * 0.03)
            let qa = q.faded(questionK), c = Self.thinkAt
            var dots = Path()
            for i in 0..<3 {
                let k = 0.5 + 0.5 * sin(t * 5.2 - Double(i) * 0.9), r = 0.1 + 0.045 * k
                let x = c.x + 0.3 + (Double(i) - 1) * 0.34, y = c.y - 0.22 - 0.06 * k
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            qa.fill(dots, with: .color(Self.yellow))
        }
        // done: the sheet's motion strokes around it while it shakes
        if state == .done && r.stateT < 1.9 {
            let st = r.stateT, a = min(1, st / 0.12) * clamp((1.9 - st) / 0.5, 0, 1)
            var d = b; d.scaleBy(x: RC, y: RC)
            let dd = SolArt.dashes
            for j in 0..<(dd.count / 6) {
                let p0 = P2(dd[j * 6], dd[j * 6 + 1]), c = P2(dd[j * 6 + 2], dd[j * 6 + 3]), p1 = P2(dd[j * 6 + 4], dd[j * 6 + 5])
                let m = (p0 + p1) / 2, out = m / max(0.01, simd_length(m))
                let o: P2 = out * (0.035 * sin(st * 38 + Double(j) * 1.9) + 0.12 * outQ(min(1, st / 0.3)) - 0.12)
                var path = Path()
                path.move(to: CGPoint(x: p0.x + o.x, y: p0.y + o.y))
                path.addQuadCurve(to: CGPoint(x: p1.x + o.x, y: p1.y + o.y), control: CGPoint(x: c.x + o.x, y: c.y + o.y))
                d.faded(a).stroke(path, with: .color(Self.yellow), style: StrokeStyle(lineWidth: 0.085, lineCap: .round))
            }
        }
        // subagents: three small suns going round it
        if minis > 0.02 {
            let small = Self.miniPath
            var o = g; o.translateBy(x: center.x, y: center.y + hop.y)          // their orbit doesn't shrink with it
            for k in 0..<3 {
                let a = t * 0.7 + Double(k) * TAU / 3, c = P2(cos(a) * 82, sin(a) * 80) * minis
                let bob = sin(t * 3.1 + Double(k) * 2) * 3
                var m = o.faded(minis); m.translateBy(x: c.x, y: c.y + bob); m.rotate(by: .radians(t * 0.5 + Double(k)))
                m.scaleBy(x: RC * 0.26, y: RC * 0.26)
                m.fill(small, with: .color(Self.yellow))
                m.rotate(by: .radians(-(t * 0.5 + Double(k))))
                for side in [-1.0, 1.0] {
                    m.fill(Path(ellipseIn: CGRect(x: side * 0.37 - 0.3, y: -0.5, width: 0.6, height: 0.6)), with: .color(Self.cream))
                    m.fill(Path(ellipseIn: CGRect(x: side * 0.37 - 0.15 + cos(a) * 0.08, y: -0.35, width: 0.3, height: 0.3)), with: .color(Self.ink))
                }
            }
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}

    /// The base shape's outline, for the small suns: built once.
    private static let miniPath: Path = {
        let s = SolArt.base, K = SolArt.K
        var pts: [P2] = []
        for a in 0..<10 {
            let o = a * K * 4
            for k in stride(from: 0, to: K, by: 2) { pts.append(P2(s[o + 2 * k], s[o + 2 * k + 1])) }
            for k in stride(from: K - 2, to: 0, by: -2) { pts.append(P2(s[o + 2 * K + 2 * k], s[o + 2 * K + 2 * k + 1])) }
        }
        return Strokes.smoothClosed(pts)
    }()

    /// The four shapes mixed by the state's weights (only when the weights move).
    private func refreshBlend() {
        let w = cur.shape
        if simd_length(w - blendKey) < 1e-4 { return }
        blendKey = w
        let A = SolArt.base, B = SolArt.angry, C = SolArt.melt, D = SolArt.dizzy
        var out = [Double](repeating: 0, count: A.count)
        for i in 0..<A.count {
            let ab = A[i] * w.x + B[i] * w.y
            let cd = C[i] * w.z + D[i] * w.w
            out[i] = ab + cd
        }
        let sum = max(1e-6, w.x + w.y + w.z + w.w)
        if abs(sum - 1) > 1e-4 { for i in out.indices { out[i] /= sum } }
        blend = out
    }

    /// The outline, every arm bent by its wave (and its flop, its length), turned by `rot`, in pt.
    private func deformed(scale RC: Double, rot: Double, drag: P2, wave: Bool) -> [P2] {
        let K = Self.K, s = blend
        var out: [P2] = []
        out.reserveCapacity(10 * (2 * K - 2))
        let cr = cos(rot), sr = sin(rot)
        var R = [P2](repeating: .zero, count: K), L = R, C = R, sl = [Double](repeating: 0, count: K)
        var nR = R, nL = R
        for a in 0..<10 {
            let o = a * K * 4, arm = arms[a]
            for k in 0..<K {
                R[k] = P2(s[o + 2 * k], s[o + 2 * k + 1])
                L[k] = P2(s[o + 2 * K + 2 * k], s[o + 2 * K + 2 * k + 1])
                C[k] = (R[k] + L[k]) * 0.5
            }
            sl[0] = 0
            for k in 1..<K { sl[k] = sl[k - 1] + simd_length(C[k] - C[k - 1]) }
            let total = max(1e-6, sl[K - 1])
            // the arm's direction, turned: a drag pulls it behind, a turn leaves it trailing
            let ang = SolArt.armAngle[a] + rot
            let dir = P2(cos(ang), sin(ang))
            let crossV = dir.x * drag.y - dir.y * drag.x
            var bias = arm.flop - clamp(crossV * 0.012, -1.2, 1.2) - clamp(spinV * 0.09, -1.1, 1.1)
            // how it holds them: up toward you, hanging, curled round one way, shivering, the top ones waving
            bias += (cur.up * -dir.x + cur.droop * dir.x) * 1.1 + cur.curl * 0.9
            if cur.shiver > 0.01 { bias += cur.shiver * 0.2 * sin(t * 31 + arm.phase * 3) }
            if cur.wave > 0.01 { bias += cur.wave * 1.3 * max(0, -dir.y - 0.2) * sin(t * 7 + Double(a) * 0.9) }
            // the small suns going round: the arm nearest each reaches for it as it passes
            var near = 0.0
            if minis > 0.02 && wave {
                for k in 0..<3 {
                    let ak = t * 0.7 + Double(k) * TAU / 3, off = remainder(ak - ang, TAU)
                    let c = pow(max(0, cos(off)), 8) * minis
                    near += c; bias += c * clamp(off, -0.6, 0.6) * 1.4
                }
            }
            let amp = wave ? cur.amp * arm.gain * (1 + 0.6 * arm.grab) : 0
            let len = cur.len + arm.len + 0.3 * sin(arm.grab * Double.pi) + 0.3 * near
            var phi = 0.0
            var nc = C[0]
            nR[0] = R[0]; nL[0] = L[0]
            for k in 1..<K {
                let u = sl[k] / total, du = (sl[k] - sl[k - 1]) / total
                let wgt = smooth(0.1, 0.45, u)
                let wv = amp * sin(TAU * 0.85 * u - wavePhase + arm.phase) * 2.2
                phi += du * (wv + bias * 1.6) * wgt
                let seg: P2 = (C[k] - C[k - 1]) * (1 + len * wgt)
                let c = cos(phi), sn = sin(phi)
                nc += P2(seg.x * c - seg.y * sn, seg.x * sn + seg.y * c)
                let dr = R[k] - C[k], dl = L[k] - C[k]
                nR[k] = nc + P2(dr.x * c - dr.y * sn, dr.x * sn + dr.y * c)
                nL[k] = nc + P2(dl.x * c - dl.y * sn, dl.x * sn + dl.y * c)
            }
            for k in 0..<K { out.append(nR[k]) }
            for k in stride(from: K - 2, to: 0, by: -1) { out.append(nL[k]) }
        }
        return out.map { q in P2((q.x * cr - q.y * sr) * RC, (q.x * sr + q.y * cr) * RC) }
    }
    private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { let k = clamp((x - a) / (b - a), 0, 1); return k * k * (3 - 2 * k) }

    /// The face, in units of the middle's radius: cream whites with black pupils, black lines and mouth, a pink tongue.
    private func drawFace(_ g0: GraphicsContext, r: Rig, pose p: Pose) {
        var e = p.eye
        if let f = finger { let d = P2(f.x, f.y) - center; let l = max(1, simd_length(d)); e.gx = d.x / l * min(1, l / 40); e.gy = d.y / l * min(1, l / 40) }
        if state == .working { e.gx = sin(t * 2.2) * 0.8; e.gy = toolFlash > 0 ? -0.9 : 0.45 }
        if state == .approval { e.gx = 0; e.gy = 0.9 }
        if abs(spinV) > 0.5 { e.gx = clamp(spinV * 0.2, -1, 1) }
        var g = g0
        g.translateBy(x: e.gx * 0.05 * look, y: e.gy * 0.04 * look)       // the whole face turns a little toward it
        let open = r.ao ? 1 : clamp(e.open, 0, 1)
        // whites, squashed shut by a blink; pupils inside them
        for i in 0..<2 where parts[i].shown {
            var w = parts[i].shape
            let c = Self.centroid(w)
            if open < 0.999 { w = w.map { P2($0.x, c.y + ($0.y - c.y) * max(0.06, open)) } }
            let white = Strokes.smoothClosed(w)
            g.fill(white, with: .color(Self.cream))
            var inner = g; if shown.clip || open < 0.95 { inner.clip(to: white) }
            let pp = pupils[i]
            let wr = Self.extent(w)
            let gx = clamp(e.gx, -1, 1) * max(0, wr.x - pp.z) * 0.8 * look
            let gy = clamp(e.gy, -1, 1) * max(0, wr.y - pp.w) * 0.7 * look
            inner.fill(Path(ellipseIn: CGRect(x: pp.x + gx - pp.z, y: pp.y + gy - pp.w, width: 2 * pp.z, height: 2 * pp.w)), with: .color(Self.ink))
            if open < 0.3 {                                          // shut for a blink: the sheet's closed line
                let d = SolArt.glyph(i == 0 ? "dashL" : "dashR"), dc = Self.centroid(d)
                g.fill(Strokes.smoothClosed(d.map { $0 - dc + c }), with: .color(Self.ink))
            }
        }
        // dizzy: spirals turning where the eyes are
        if spiralsK > 0.02 {
            for (i, sp) in Self.spirals.enumerated() {
                var s = g.faded(spiralsK); s.translateBy(x: sp.c.x, y: sp.c.y)
                s.rotate(by: .radians(t * 4.2 * (i == 0 ? 1 : 1.15))); s.scaleBy(x: spiralsK, y: spiralsK)
                s.fill(sp.path, with: .color(Self.ink))
            }
        }
        // the tongue under the mouth line, then lines, brows and the mouth
        var mouthPts = parts[6].shape
        if state == .speaking && winkT <= 0 && petT <= 0 {
            let v = clamp(r.voice * 1.5, 0, 1)
            mouthPts = Strokes.mix(SolArt.glyph("smile"), SolArt.glyph("Dtalk"), v)
        } else if state == .listening && parts[6].name == "O" && parts[6].b > 0.9 {
            let k = 0.72 + 0.55 * clamp(r.voice * 1.4, 0, 1), c = Self.centroid(mouthPts)
            mouthPts = mouthPts.map { c + ($0 - c) * P2(0.9 + 0.1 * k, k) }
        } else if state == .sleep && parts[6].name == "yawn" {
            let k = 0.96 + 0.07 * sin(t * TAU / 4.2), c = Self.centroid(mouthPts)
            mouthPts = mouthPts.map { c + ($0 - c) * k }
        }
        if parts[7].shown { g.fill(Strokes.smoothClosed(parts[7].shape), with: .color(Self.pink)) }
        for i in 2..<6 where parts[i].shown { g.fill(Strokes.smoothClosed(parts[i].shape), with: .color(Self.ink)) }
        if parts[6].shown { g.fill(Strokes.smoothClosed(mouthPts), with: .color(Self.ink)) }
    }
    private static func extent(_ p: [P2]) -> P2 {
        var lo = P2(9, 9), hi = P2(-9, -9)
        for q in p { lo = simd_min(lo, q); hi = simd_max(hi, q) }
        return (hi - lo) * 0.5
    }
    /// The sheet's spiral eyes, each round its own middle (they turn there).
    private static let spirals: [(c: P2, path: Path)] = ["spiralL", "spiralR"].map { n in
        let g = SolArt.glyph(n), e = extent(g)
        var lo = P2(9, 9); for q in g { lo = simd_min(lo, q) }
        let c = lo + e
        return (c, Strokes.smoothClosed(g.map { $0 - c }))
    }
}

/// Ray, traced from its character sheet: in units of the middle's radius, centred
/// on it, y down. Each shape is ten arms (from the top, clockwise), each arm its right then its left edge, 16 points
/// each from the valley beside it to its tip. base: the sheet's sun · angry: its jagged arms · melt: asleep, the arms
/// dripping down · dizzy: its pinwheel. Glyphs: the face parts, each 64 points round its outline, leftmost first, clockwise.
enum SolArt {
    static let K = 16, N = 64
    static let base: [Double] = [-0.445, -0.996, -0.408, -1.019, -0.377, -1.052, -0.351, -1.094, -0.329, -1.152, -0.312, -1.242, -0.296, -1.367, -0.274, -1.489, -0.247, -1.597, -0.212, -1.694, -0.179, -1.765, -0.149, -1.812, -0.12, -1.844, -0.09, -1.866, -0.056, -1.88, -0.02, -1.884, 0.345, -0.938, 0.307, -0.963, 0.275, -0.997, 0.25, -1.041, 0.233, -1.098, 0.227, -1.178, 0.23, -1.31, 0.23, -1.448, 0.22, -1.561, 0.202, -1.653, 0.175, -1.727, 0.144, -1.783, 0.11, -1.825, 0.072, -1.854, 0.028, -1.875, -0.02, -1.884, 0.345, -0.938, 0.4, -0.926, 0.455, -0.93, 0.508, -0.949, 0.558, -0.987, 0.609, -1.051, 0.669, -1.166, 0.732, -1.32, 0.792, -1.443, 0.852, -1.529, 0.927, -1.597, 1.025, -1.658, 1.121, -1.699, 1.204, -1.716, 1.272, -1.716, 1.332, -1.698, 0.903, -0.525, 0.902, -0.566, 0.929, -0.62, 0.974, -0.717, 1.009, -0.849, 1.044, -1.01, 1.083, -1.123, 1.142, -1.222, 1.225, -1.319, 1.321, -1.411, 1.371, -1.479, 1.395, -1.536, 1.402, -1.585, 1.394, -1.63, 1.37, -1.668, 1.332, -1.698, 0.903, -0.525, 0.931, -0.497, 0.973, -0.481, 1.028, -0.477, 1.091, -0.488, 1.161, -0.523, 1.254, -0.601, 1.364, -0.7, 1.469, -0.769, 1.573, -0.816, 1.682, -0.841, 1.801, -0.847, 1.902, -0.836, 1.976, -0.812, 2.029, -0.778, 2.066, -0.732, 1.018, 0.022, 1.033, -0.014, 1.071, -0.04, 1.14, -0.052, 1.254, -0.067, 1.363, -0.105, 1.463, -0.171, 1.573, -0.28, 1.681, -0.387, 1.779, -0.451, 1.903, -0.494, 1.993, -0.529, 2.044, -0.57, 2.073, -0.619, 2.081, -0.675, 2.066, -0.732, 1.018, 0.022, 1.036, 0.064, 1.086, 0.098, 1.189, 0.132, 1.344, 0.16, 1.46, 0.186, 1.544, 0.231, 1.616, 0.31, 1.682, 0.404, 1.751, 0.46, 1.848, 0.491, 1.951, 0.513, 2.013, 0.545, 2.051, 0.589, 2.066, 0.645, 2.057, 0.709, 0.829, 0.577, 0.867, 0.542, 0.922, 0.523, 1.004, 0.519, 1.098, 0.53, 1.19, 0.565, 1.289, 0.631, 1.417, 0.742, 1.516, 0.813, 1.605, 0.853, 1.704, 0.87, 1.806, 0.868, 1.896, 0.846, 1.969, 0.809, 2.022, 0.764, 2.057, 0.709, 0.829, 0.577, 0.811, 0.626, 0.823, 0.68, 0.873, 0.739, 0.984, 0.818, 1.067, 0.897, 1.122, 1.007, 1.175, 1.173, 1.232, 1.291, 1.311, 1.379, 1.414, 1.445, 1.483, 1.492, 1.514, 1.542, 1.519, 1.597, 1.497, 1.652, 1.447, 1.699, 0.318, 0.964, 0.363, 0.958, 0.416, 0.971, 0.484, 1.003, 0.554, 1.054, 0.62, 1.131, 0.7, 1.262, 0.784, 1.421, 0.849, 1.521, 0.918, 1.592, 1.006, 1.651, 1.11, 1.699, 1.212, 1.727, 1.306, 1.733, 1.382, 1.725, 1.447, 1.699, 0.318, 0.964, 0.287, 0.984, 0.261, 1.017, 0.242, 1.062, 0.228, 1.127, 0.223, 1.218, 0.227, 1.343, 0.221, 1.46, 0.205, 1.566, 0.176, 1.67, 0.141, 1.756, 0.103, 1.819, 0.068, 1.863, 0.032, 1.892, -0.008, 1.91, -0.052, 1.916, -0.321, 0.995, -0.29, 1.012, -0.266, 1.043, -0.249, 1.087, -0.238, 1.153, -0.237, 1.246, -0.251, 1.364, -0.268, 1.494, -0.273, 1.596, -0.264, 1.68, -0.243, 1.752, -0.213, 1.812, -0.179, 1.857, -0.142, 1.89, -0.099, 1.909, -0.052, 1.916, -0.321, 0.995, -0.376, 0.996, -0.439, 1.027, -0.518, 1.097, -0.619, 1.229, -0.711, 1.337, -0.806, 1.409, -0.919, 1.456, -1.05, 1.49, -1.134, 1.53, -1.203, 1.602, -1.267, 1.699, -1.316, 1.752, -1.364, 1.777, -1.415, 1.781, -1.465, 1.762, -0.859, 0.704, -0.85, 0.737, -0.862, 0.779, -0.898, 0.842, -0.987, 0.961, -1.087, 1.077, -1.182, 1.16, -1.299, 1.238, -1.386, 1.308, -1.448, 1.384, -1.495, 1.474, -1.521, 1.559, -1.529, 1.628, -1.521, 1.683, -1.499, 1.728, -1.465, 1.762, -0.859, 0.704, -0.903, 0.676, -0.967, 0.674, -1.051, 0.7, -1.153, 0.757, -1.252, 0.785, -1.359, 0.78, -1.482, 0.74, -1.591, 0.693, -1.671, 0.683, -1.752, 0.709, -1.844, 0.769, -1.918, 0.802, -1.98, 0.803, -2.034, 0.78, -2.071, 0.734, -1.009, 0.083, -1.022, 0.127, -1.065, 0.177, -1.144, 0.242, -1.233, 0.289, -1.328, 0.312, -1.462, 0.311, -1.617, 0.3, -1.748, 0.31, -1.853, 0.339, -1.938, 0.385, -2.006, 0.446, -2.055, 0.518, -2.081, 0.592, -2.087, 0.666, -2.071, 0.734, -1.009, 0.083, -1.028, 0.045, -1.073, 0.016, -1.17, -0.011, -1.31, -0.054, -1.433, -0.117, -1.533, -0.192, -1.624, -0.299, -1.703, -0.402, -1.773, -0.46, -1.864, -0.493, -1.947, -0.517, -1.997, -0.549, -2.027, -0.593, -2.039, -0.646, -2.03, -0.704, -0.869, -0.527, -0.905, -0.492, -0.961, -0.47, -1.04, -0.46, -1.129, -0.469, -1.219, -0.503, -1.31, -0.562, -1.411, -0.661, -1.51, -0.745, -1.607, -0.8, -1.704, -0.831, -1.798, -0.839, -1.879, -0.827, -1.946, -0.798, -1.997, -0.758, -2.03, -0.704, -0.869, -0.527, -0.865, -0.571, -0.895, -0.62, -0.985, -0.694, -1.097, -0.794, -1.171, -0.897, -1.227, -1.038, -1.274, -1.208, -1.31, -1.302, -1.361, -1.357, -1.438, -1.39, -1.503, -1.42, -1.539, -1.464, -1.552, -1.518, -1.542, -1.575, -1.505, -1.627, -0.445, -0.996, -0.505, -0.981, -0.569, -0.986, -0.639, -1.011, -0.712, -1.056, -0.779, -1.123, -0.844, -1.226, -0.918, -1.372, -0.982, -1.476, -1.056, -1.555, -1.138, -1.616, -1.222, -1.654, -1.309, -1.673, -1.387, -1.673, -1.451, -1.658, -1.505, -1.627]
    static let angry: [Double] = [-0.44, -0.976, -0.374, -1.03, -0.325, -1.116, -0.294, -1.229, -0.286, -1.349, -0.296, -1.463, -0.291, -1.53, -0.271, -1.573, -0.234, -1.591, -0.191, -1.591, -0.154, -1.617, -0.132, -1.689, -0.103, -1.823, -0.083, -1.905, -0.054, -1.95, -0.011, -1.968, 0.346, -0.929, 0.278, -0.981, 0.235, -1.068, 0.212, -1.19, 0.217, -1.316, 0.249, -1.431, 0.261, -1.498, 0.248, -1.544, 0.213, -1.566, 0.17, -1.562, 0.131, -1.583, 0.113, -1.651, 0.097, -1.789, 0.072, -1.889, 0.038, -1.946, -0.011, -1.968, 0.346, -0.929, 0.416, -0.915, 0.485, -0.931, 0.55, -0.973, 0.602, -1.043, 0.638, -1.158, 0.664, -1.282, 0.697, -1.357, 0.757, -1.408, 0.804, -1.478, 0.861, -1.534, 0.951, -1.57, 1.048, -1.635, 1.131, -1.708, 1.198, -1.74, 1.258, -1.742, 0.883, -0.523, 0.878, -0.585, 0.93, -0.704, 0.99, -0.835, 1.001, -0.923, 0.982, -0.999, 0.997, -1.067, 1.061, -1.132, 1.134, -1.196, 1.166, -1.271, 1.17, -1.359, 1.221, -1.458, 1.282, -1.577, 1.302, -1.656, 1.295, -1.711, 1.258, -1.742, 0.883, -0.523, 0.941, -0.488, 1.029, -0.491, 1.144, -0.536, 1.249, -0.61, 1.319, -0.7, 1.367, -0.747, 1.416, -0.755, 1.45, -0.72, 1.491, -0.682, 1.564, -0.684, 1.685, -0.731, 1.805, -0.805, 1.881, -0.846, 1.94, -0.847, 1.977, -0.811, 0.996, 0.01, 1.029, -0.04, 1.121, -0.064, 1.275, -0.09, 1.426, -0.143, 1.497, -0.181, 1.51, -0.241, 1.531, -0.305, 1.606, -0.358, 1.71, -0.385, 1.775, -0.423, 1.793, -0.494, 1.828, -0.571, 1.923, -0.656, 1.977, -0.736, 1.977, -0.811, 0.996, 0.01, 1.044, 0.076, 1.176, 0.127, 1.316, 0.144, 1.399, 0.173, 1.439, 0.246, 1.519, 0.284, 1.609, 0.289, 1.66, 0.323, 1.649, 0.383, 1.63, 0.445, 1.683, 0.501, 1.828, 0.54, 1.971, 0.583, 2.037, 0.641, 2.045, 0.707, 0.815, 0.554, 0.855, 0.521, 0.911, 0.502, 0.987, 0.496, 1.083, 0.51, 1.173, 0.539, 1.252, 0.587, 1.339, 0.67, 1.414, 0.732, 1.492, 0.768, 1.599, 0.788, 1.723, 0.795, 1.856, 0.777, 1.961, 0.754, 2.013, 0.736, 2.045, 0.707, 0.815, 0.554, 0.797, 0.602, 0.807, 0.656, 0.853, 0.716, 0.953, 0.795, 1.033, 0.873, 1.083, 0.977, 1.131, 1.132, 1.187, 1.246, 1.258, 1.331, 1.36, 1.394, 1.436, 1.44, 1.473, 1.485, 1.483, 1.536, 1.468, 1.59, 1.424, 1.641, 0.318, 0.937, 0.367, 0.934, 0.425, 0.951, 0.493, 0.987, 0.56, 1.04, 0.627, 1.128, 0.716, 1.28, 0.793, 1.417, 0.861, 1.505, 0.94, 1.576, 1.031, 1.632, 1.124, 1.668, 1.218, 1.685, 1.302, 1.684, 1.369, 1.67, 1.424, 1.641, 0.318, 0.937, 0.283, 0.956, 0.257, 0.99, 0.238, 1.039, 0.225, 1.114, 0.223, 1.234, 0.22, 1.372, 0.206, 1.486, 0.184, 1.578, 0.142, 1.665, 0.094, 1.751, 0.068, 1.828, 0.054, 1.881, 0.039, 1.917, 0.017, 1.94, -0.01, 1.95, -0.319, 0.962, -0.283, 0.984, -0.256, 1.022, -0.237, 1.08, -0.229, 1.167, -0.234, 1.286, -0.255, 1.426, -0.268, 1.551, -0.269, 1.63, -0.249, 1.691, -0.21, 1.751, -0.153, 1.808, -0.109, 1.868, -0.077, 1.913, -0.045, 1.94, -0.01, 1.95, -0.319, 0.962, -0.373, 0.963, -0.434, 0.995, -0.509, 1.06, -0.596, 1.175, -0.682, 1.275, -0.788, 1.355, -0.904, 1.417, -1.016, 1.45, -1.091, 1.483, -1.149, 1.546, -1.208, 1.644, -1.246, 1.698, -1.283, 1.725, -1.326, 1.729, -1.369, 1.713, -0.844, 0.686, -0.832, 0.722, -0.837, 0.766, -0.864, 0.822, -0.932, 0.915, -1.029, 1.026, -1.123, 1.11, -1.233, 1.186, -1.316, 1.259, -1.377, 1.339, -1.419, 1.423, -1.441, 1.503, -1.444, 1.572, -1.433, 1.629, -1.408, 1.677, -1.369, 1.713, -0.844, 0.686, -0.91, 0.655, -1.011, 0.673, -1.132, 0.728, -1.237, 0.738, -1.329, 0.7, -1.413, 0.693, -1.487, 0.724, -1.549, 0.722, -1.581, 0.676, -1.62, 0.638, -1.697, 0.664, -1.826, 0.745, -1.919, 0.789, -1.983, 0.787, -2.016, 0.745, -0.99, 0.078, -1.03, 0.157, -1.136, 0.242, -1.271, 0.297, -1.411, 0.307, -1.528, 0.277, -1.597, 0.24, -1.652, 0.25, -1.68, 0.303, -1.735, 0.344, -1.815, 0.357, -1.867, 0.392, -1.874, 0.463, -1.928, 0.547, -1.999, 0.648, -2.016, 0.745, -0.99, 0.078, -1.03, 0.017, -1.151, -0.021, -1.314, -0.083, -1.453, -0.168, -1.554, -0.193, -1.61, -0.223, -1.608, -0.277, -1.593, -0.33, -1.637, -0.376, -1.719, -0.39, -1.793, -0.411, -1.837, -0.483, -1.96, -0.554, -2.053, -0.619, -2.078, -0.689, -0.853, -0.523, -0.94, -0.47, -1.064, -0.459, -1.175, -0.486, -1.239, -0.545, -1.272, -0.611, -1.33, -0.63, -1.4, -0.629, -1.491, -0.709, -1.589, -0.785, -1.66, -0.8, -1.719, -0.756, -1.8, -0.727, -1.939, -0.739, -2.033, -0.73, -2.078, -0.689, -0.853, -0.523, -0.837, -0.571, -0.851, -0.624, -0.902, -0.679, -1.014, -0.754, -1.126, -0.848, -1.192, -0.925, -1.218, -1.012, -1.237, -1.109, -1.291, -1.206, -1.325, -1.298, -1.384, -1.38, -1.469, -1.463, -1.507, -1.514, -1.516, -1.557, -1.498, -1.592, -0.44, -0.976, -0.549, -0.953, -0.639, -0.99, -0.688, -1.082, -0.707, -1.176, -0.754, -1.215, -0.815, -1.191, -0.879, -1.206, -0.932, -1.31, -0.984, -1.484, -1.028, -1.566, -1.089, -1.58, -1.154, -1.545, -1.263, -1.581, -1.396, -1.616, -1.498, -1.592]
    static let melt: [Double] = [-0.405, -0.982, -0.348, -1.018, -0.304, -1.077, -0.271, -1.183, -0.234, -1.309, -0.184, -1.396, -0.116, -1.463, -0.029, -1.509, 0.104, -1.538, 0.228, -1.57, 0.313, -1.615, 0.381, -1.686, 0.436, -1.759, 0.484, -1.796, 0.534, -1.808, 0.585, -1.798, 0.377, -0.957, 0.32, -0.992, 0.282, -1.04, 0.262, -1.097, 0.262, -1.158, 0.281, -1.216, 0.321, -1.267, 0.395, -1.313, 0.489, -1.362, 0.56, -1.424, 0.614, -1.503, 0.649, -1.585, 0.659, -1.658, 0.651, -1.718, 0.627, -1.765, 0.585, -1.798, 0.377, -0.957, 0.448, -0.945, 0.531, -0.96, 0.671, -1.026, 0.815, -1.084, 0.933, -1.105, 1.043, -1.097, 1.149, -1.062, 1.246, -1.001, 1.351, -0.891, 1.47, -0.747, 1.581, -0.651, 1.644, -0.602, 1.671, -0.563, 1.678, -0.521, 1.665, -0.478, 0.907, -0.515, 0.893, -0.548, 0.898, -0.584, 0.921, -0.616, 0.96, -0.643, 1.017, -0.659, 1.085, -0.66, 1.154, -0.643, 1.224, -0.601, 1.314, -0.523, 1.397, -0.461, 1.466, -0.427, 1.53, -0.416, 1.586, -0.422, 1.632, -0.442, 1.665, -0.478, 0.907, -0.515, 0.957, -0.475, 1.053, -0.441, 1.194, -0.404, 1.309, -0.353, 1.405, -0.284, 1.48, -0.198, 1.546, -0.08, 1.611, 0.081, 1.664, 0.18, 1.733, 0.253, 1.819, 0.311, 1.869, 0.353, 1.893, 0.395, 1.899, 0.439, 1.888, 0.484, 1.069, 0.129, 1.077, 0.102, 1.103, 0.086, 1.142, 0.084, 1.191, 0.095, 1.249, 0.127, 1.308, 0.188, 1.38, 0.295, 1.449, 0.396, 1.517, 0.464, 1.595, 0.513, 1.676, 0.543, 1.749, 0.553, 1.808, 0.545, 1.856, 0.522, 1.888, 0.484, 1.069, 0.129, 1.083, 0.165, 1.126, 0.201, 1.211, 0.265, 1.293, 0.347, 1.35, 0.435, 1.398, 0.561, 1.442, 0.701, 1.479, 0.777, 1.541, 0.84, 1.643, 0.914, 1.708, 0.978, 1.748, 1.045, 1.769, 1.11, 1.771, 1.169, 1.755, 1.223, 0.838, 0.626, 0.877, 0.606, 0.924, 0.613, 0.973, 0.649, 1.022, 0.731, 1.074, 0.868, 1.129, 0.968, 1.202, 1.038, 1.306, 1.088, 1.429, 1.122, 1.506, 1.165, 1.561, 1.231, 1.612, 1.271, 1.665, 1.28, 1.715, 1.264, 1.755, 1.223, 0.838, 0.626, 0.822, 0.667, 0.827, 0.723, 0.868, 0.822, 0.923, 0.95, 0.945, 1.05, 0.939, 1.162, 0.914, 1.299, 0.907, 1.395, 0.926, 1.475, 0.979, 1.566, 1.019, 1.636, 1.033, 1.686, 1.028, 1.729, 1.005, 1.763, 0.968, 1.786, 0.343, 0.969, 0.396, 0.966, 0.45, 0.983, 0.501, 1.015, 0.54, 1.058, 0.564, 1.114, 0.573, 1.195, 0.567, 1.325, 0.572, 1.429, 0.598, 1.515, 0.642, 1.596, 0.709, 1.671, 0.788, 1.734, 0.86, 1.773, 0.917, 1.79, 0.968, 1.786, 0.343, 0.969, 0.313, 0.984, 0.289, 1.009, 0.27, 1.045, 0.256, 1.095, 0.251, 1.177, 0.251, 1.304, 0.245, 1.413, 0.225, 1.523, 0.194, 1.636, 0.161, 1.724, 0.131, 1.782, 0.1, 1.821, 0.067, 1.848, 0.031, 1.865, -0.01, 1.87, -0.282, 1.004, -0.248, 1.021, -0.221, 1.05, -0.201, 1.09, -0.189, 1.146, -0.185, 1.225, -0.196, 1.334, -0.212, 1.465, -0.216, 1.562, -0.206, 1.648, -0.188, 1.717, -0.162, 1.772, -0.13, 1.814, -0.094, 1.844, -0.054, 1.863, -0.01, 1.87, -0.282, 1.004, -0.327, 0.999, -0.366, 1.014, -0.396, 1.046, -0.413, 1.1, -0.414, 1.201, -0.424, 1.313, -0.466, 1.44, -0.504, 1.559, -0.513, 1.66, -0.509, 1.748, -0.52, 1.806, -0.546, 1.846, -0.583, 1.87, -0.63, 1.877, -0.682, 1.863, -0.803, 0.707, -0.798, 0.75, -0.818, 0.817, -0.845, 0.909, -0.851, 0.987, -0.834, 1.065, -0.789, 1.162, -0.76, 1.247, -0.754, 1.325, -0.774, 1.421, -0.804, 1.533, -0.811, 1.625, -0.801, 1.703, -0.773, 1.77, -0.733, 1.825, -0.682, 1.863, -0.803, 0.707, -0.83, 0.694, -0.867, 0.705, -0.909, 0.747, -0.97, 0.822, -1.043, 0.878, -1.146, 0.918, -1.245, 0.951, -1.308, 0.993, -1.35, 1.057, -1.38, 1.152, -1.401, 1.235, -1.43, 1.284, -1.469, 1.312, -1.516, 1.318, -1.564, 1.3, -1.013, 0.129, -1.024, 0.2, -1.065, 0.3, -1.129, 0.417, -1.192, 0.498, -1.276, 0.568, -1.4, 0.646, -1.488, 0.716, -1.552, 0.791, -1.599, 0.875, -1.629, 0.969, -1.642, 1.068, -1.637, 1.159, -1.623, 1.222, -1.599, 1.267, -1.564, 1.3, -1.013, 0.129, -1.022, 0.099, -1.045, 0.079, -1.079, 0.075, -1.12, 0.087, -1.17, 0.122, -1.231, 0.193, -1.309, 0.311, -1.38, 0.405, -1.452, 0.471, -1.534, 0.518, -1.617, 0.545, -1.689, 0.551, -1.747, 0.541, -1.792, 0.516, -1.822, 0.476, -0.901, -0.502, -0.935, -0.464, -1.002, -0.436, -1.134, -0.395, -1.253, -0.34, -1.344, -0.276, -1.415, -0.195, -1.477, -0.085, -1.545, 0.08, -1.596, 0.181, -1.657, 0.249, -1.741, 0.307, -1.793, 0.349, -1.819, 0.39, -1.829, 0.433, -1.822, 0.476, -0.901, -0.502, -0.884, -0.564, -0.889, -0.623, -0.911, -0.671, -0.945, -0.704, -0.989, -0.719, -1.04, -0.711, -1.095, -0.678, -1.156, -0.608, -1.22, -0.52, -1.281, -0.464, -1.35, -0.432, -1.422, -0.422, -1.486, -0.433, -1.536, -0.458, -1.568, -0.501, -0.405, -0.982, -0.464, -0.977, -0.539, -1.009, -0.675, -1.094, -0.789, -1.144, -0.91, -1.161, -1.024, -1.154, -1.118, -1.118, -1.202, -1.056, -1.275, -0.961, -1.349, -0.814, -1.417, -0.71, -1.504, -0.635, -1.553, -0.588, -1.572, -0.545, -1.568, -0.501]
    static let dizzy: [Double] = [-0.57, -0.985, -0.515, -1.025, -0.481, -1.075, -0.468, -1.141, -0.471, -1.239, -0.459, -1.338, -0.42, -1.439, -0.371, -1.537, -0.35, -1.616, -0.356, -1.701, -0.39, -1.808, -0.421, -1.89, -0.427, -1.946, -0.414, -1.991, -0.386, -2.026, -0.345, -2.047, 0.19, -1.037, 0.136, -1.057, 0.09, -1.094, 0.049, -1.154, 0.016, -1.23, 0.001, -1.316, 0.007, -1.43, 0.019, -1.565, 0.013, -1.676, -0.013, -1.774, -0.059, -1.866, -0.118, -1.948, -0.179, -2.005, -0.235, -2.038, -0.289, -2.051, -0.345, -2.047, 0.19, -1.037, 0.253, -1.035, 0.309, -1.049, 0.359, -1.075, 0.4, -1.116, 0.435, -1.175, 0.464, -1.273, 0.494, -1.381, 0.535, -1.465, 0.598, -1.546, 0.694, -1.636, 0.816, -1.734, 0.889, -1.788, 0.937, -1.812, 0.98, -1.82, 1.02, -1.811, 0.83, -0.694, 0.814, -0.736, 0.822, -0.796, 0.852, -0.898, 0.866, -0.996, 0.853, -1.106, 0.849, -1.195, 0.87, -1.272, 0.92, -1.354, 1.004, -1.451, 1.06, -1.535, 1.088, -1.614, 1.096, -1.681, 1.085, -1.736, 1.06, -1.781, 1.02, -1.811, 0.83, -0.694, 0.866, -0.665, 0.916, -0.652, 0.98, -0.652, 1.054, -0.669, 1.127, -0.705, 1.204, -0.772, 1.295, -0.867, 1.375, -0.931, 1.465, -0.977, 1.572, -1.009, 1.675, -1.021, 1.751, -1.021, 1.802, -1.007, 1.841, -0.981, 1.868, -0.944, 1.045, -0.135, 1.053, -0.177, 1.082, -0.216, 1.14, -0.253, 1.253, -0.301, 1.348, -0.354, 1.42, -0.418, 1.487, -0.517, 1.548, -0.603, 1.618, -0.661, 1.722, -0.714, 1.8, -0.754, 1.845, -0.795, 1.87, -0.842, 1.879, -0.892, 1.868, -0.944, 1.045, -0.135, 1.063, -0.091, 1.105, -0.056, 1.185, -0.029, 1.314, 0.001, 1.424, 0.046, 1.524, 0.119, 1.615, 0.197, 1.69, 0.235, 1.787, 0.246, 1.885, 0.249, 1.946, 0.268, 1.987, 0.301, 2.012, 0.346, 2.018, 0.399, 2.002, 0.456, 0.92, 0.503, 0.95, 0.461, 0.995, 0.429, 1.053, 0.408, 1.119, 0.4, 1.187, 0.408, 1.263, 0.438, 1.368, 0.505, 1.465, 0.562, 1.556, 0.593, 1.65, 0.607, 1.745, 0.602, 1.834, 0.581, 1.908, 0.547, 1.963, 0.506, 2.002, 0.456, 0.92, 0.503, 0.912, 0.547, 0.933, 0.593, 0.996, 0.649, 1.084, 0.728, 1.144, 0.815, 1.187, 0.937, 1.225, 1.066, 1.266, 1.147, 1.323, 1.2, 1.409, 1.236, 1.48, 1.27, 1.519, 1.313, 1.537, 1.361, 1.535, 1.411, 1.51, 1.456, 0.456, 0.95, 0.514, 0.938, 0.586, 0.948, 0.668, 0.976, 0.734, 1.014, 0.784, 1.068, 0.831, 1.161, 0.885, 1.277, 0.942, 1.359, 1.011, 1.422, 1.092, 1.467, 1.188, 1.496, 1.305, 1.507, 1.401, 1.503, 1.463, 1.487, 1.51, 1.456, 0.456, 0.95, 0.415, 0.981, 0.388, 1.031, 0.373, 1.111, 0.368, 1.229, 0.348, 1.336, 0.299, 1.451, 0.262, 1.551, 0.252, 1.631, 0.268, 1.715, 0.312, 1.823, 0.333, 1.895, 0.332, 1.948, 0.318, 1.99, 0.289, 2.022, 0.249, 2.04, -0.221, 1.051, -0.173, 1.075, -0.131, 1.116, -0.097, 1.171, -0.075, 1.236, -0.072, 1.313, -0.092, 1.423, -0.105, 1.548, -0.102, 1.654, -0.079, 1.747, -0.038, 1.837, 0.02, 1.92, 0.084, 1.983, 0.142, 2.02, 0.196, 2.039, 0.249, 2.04, -0.221, 1.051, -0.271, 1.054, -0.319, 1.085, -0.373, 1.162, -0.442, 1.273, -0.528, 1.363, -0.627, 1.427, -0.744, 1.468, -0.855, 1.497, -0.925, 1.539, -0.975, 1.603, -1.013, 1.7, -1.049, 1.763, -1.09, 1.797, -1.14, 1.809, -1.193, 1.797, -0.82, 0.796, -0.798, 0.836, -0.793, 0.894, -0.801, 0.963, -0.83, 1.031, -0.881, 1.095, -0.965, 1.155, -1.074, 1.221, -1.151, 1.29, -1.208, 1.368, -1.247, 1.458, -1.267, 1.562, -1.268, 1.657, -1.257, 1.721, -1.232, 1.767, -1.193, 1.797, -0.82, 0.796, -0.86, 0.782, -0.912, 0.791, -0.987, 0.833, -1.075, 0.88, -1.163, 0.9, -1.264, 0.894, -1.386, 0.864, -1.483, 0.848, -1.565, 0.858, -1.653, 0.899, -1.729, 0.945, -1.783, 0.961, -1.83, 0.955, -1.871, 0.931, -1.9, 0.888, -1.039, 0.228, -1.039, 0.277, -1.058, 0.327, -1.1, 0.381, -1.166, 0.436, -1.25, 0.48, -1.35, 0.508, -1.478, 0.519, -1.599, 0.528, -1.688, 0.551, -1.762, 0.591, -1.825, 0.648, -1.874, 0.714, -1.901, 0.777, -1.91, 0.834, -1.9, 0.888, -1.039, 0.228, -1.068, 0.176, -1.124, 0.136, -1.229, 0.108, -1.353, 0.075, -1.465, 0.013, -1.571, -0.08, -1.666, -0.179, -1.741, -0.227, -1.83, -0.245, -1.927, -0.24, -1.995, -0.246, -2.042, -0.272, -2.072, -0.312, -2.082, -0.363, -2.068, -0.42, -0.977, -0.425, -1.009, -0.376, -1.057, -0.338, -1.121, -0.313, -1.193, -0.302, -1.261, -0.31, -1.329, -0.34, -1.417, -0.41, -1.518, -0.487, -1.604, -0.531, -1.691, -0.553, -1.79, -0.553, -1.897, -0.533, -1.977, -0.504, -2.032, -0.467, -2.068, -0.42, -0.977, -0.425, -0.97, -0.477, -0.992, -0.529, -1.056, -0.585, -1.169, -0.667, -1.254, -0.755, -1.307, -0.848, -1.337, -0.97, -1.361, -1.072, -1.4, -1.135, -1.465, -1.179, -1.559, -1.209, -1.622, -1.238, -1.656, -1.278, -1.668, -1.328, -1.654, -1.383, -0.57, -0.985, -0.651, -0.955, -0.741, -0.952, -0.855, -0.975, -0.937, -1.005, -0.989, -1.046, -1.028, -1.122, -1.077, -1.242, -1.131, -1.328, -1.197, -1.388, -1.288, -1.434, -1.402, -1.463, -1.499, -1.469, -1.567, -1.457, -1.618, -1.428, -1.654, -1.383]
    static let dashes: [Double] = [0.684, -2.039, 0.640, -1.957, 0.599, -1.873, 1.569, -1.581, 1.587, -1.777, 1.419, -1.880, -1.445, -1.870, -1.651, -1.813, -1.717, -1.611, 1.827, -1.610, 1.816, -1.571, 1.799, -1.532, 2.183, -1.569, 2.079, -1.484, 1.977, -1.398, 2.169, -1.169, 2.111, -1.157, 2.052, -1.154, -2.000, -1.000, -2.153, -0.911, -2.173, -0.733, -2.303, -0.918, -2.350, -0.832, -2.352, -0.734, 2.082, -0.385, 1.903, -0.345, 1.766, -0.223, 2.228, 0.635, 2.208, 0.899, 1.959, 0.989, -2.113, 1.039, -2.178, 1.052, -2.244, 1.053, -2.023, 1.231, -2.124, 1.310, -2.225, 1.390, -1.879, 1.379, -1.895, 1.413, -1.906, 1.449, -1.682, 1.757, -1.632, 1.889, -1.500, 1.939, 0.620, 1.772, 0.657, 1.858, 0.710, 1.935, -0.407, 1.806, -0.365, 1.964, -0.227, 2.053]
    /// Each arm's direction, middle to tip, in the base shape.
    static let armAngle: [Double] = [-1.581, -0.906, -0.341, 0.332, 0.865, 1.598, 2.264, 2.801, -2.808, -2.317]
    static let pupils: [String: SIMD4<Double>] = [
        "pSurL": SIMD4(-0.373, -0.203, 0.118, 0.120),
        "pSurR": SIMD4(0.346, -0.214, 0.118, 0.121),
        "pSadL": SIMD4(-0.389, -0.140, 0.179, 0.195),
        "pSadR": SIMD4(0.314, -0.132, 0.163, 0.189),
        "pThkL": SIMD4(-0.257, -0.054, 0.143, 0.150),
        "pThkR": SIMD4(0.396, -0.336, 0.146, 0.148),
        "pAngL": SIMD4(-0.343, -0.094, 0.151, 0.136),
        "pAngR": SIMD4(0.332, -0.097, 0.149, 0.137),
        "pWinkL": SIMD4(-0.234, -0.161, 0.153, 0.153),
        "pNeuL": SIMD4(-0.380, -0.197, 0.140, 0.145),
        "pNeuR": SIMD4(0.349, -0.207, 0.140, 0.145),
    ]
    static func pupil(_ n: String) -> SIMD4<Double> { pupils[n] ?? pupils["pNeuL"]! }
    private static let raw: [String: [Double]] = [
        "wSurL": [-0.688, -0.195, -0.688, -0.226, -0.687, -0.256, -0.681, -0.287, -0.667, -0.314, -0.657, -0.344, -0.645, -0.372, -0.627, -0.397, -0.607, -0.420, -0.587, -0.444, -0.562, -0.462, -0.536, -0.478, -0.508, -0.491, -0.480, -0.504, -0.450, -0.510, -0.419, -0.515, -0.389, -0.520, -0.358, -0.521, -0.327, -0.517, -0.297, -0.511, -0.267, -0.505, -0.239, -0.492, -0.213, -0.476, -0.188, -0.456, -0.164, -0.438, -0.143, -0.415, -0.123, -0.392, -0.109, -0.364, -0.093, -0.338, -0.083, -0.309, -0.079, -0.278, -0.073, -0.248, -0.072, -0.217, -0.073, -0.186, -0.076, -0.156, -0.082, -0.125, -0.088, -0.095, -0.104, -0.069, -0.115, -0.040, -0.134, -0.016, -0.151, 0.010, -0.173, 0.031, -0.200, 0.047, -0.224, 0.066, -0.253, 0.077, -0.279, 0.093, -0.309, 0.099, -0.340, 0.102, -0.371, 0.103, -0.402, 0.102, -0.432, 0.100, -0.463, 0.098, -0.493, 0.092, -0.520, 0.077, -0.549, 0.065, -0.572, 0.045, -0.598, 0.028, -0.619, 0.006, -0.633, -0.022, -0.651, -0.047, -0.660, -0.076, -0.671, -0.105, -0.684, -0.133, -0.687, -0.164],
        "wSurR": [0.039, -0.245, 0.041, -0.276, 0.050, -0.305, 0.063, -0.333, 0.072, -0.363, 0.089, -0.388, 0.104, -0.415, 0.126, -0.437, 0.151, -0.454, 0.174, -0.475, 0.201, -0.490, 0.228, -0.504, 0.257, -0.515, 0.286, -0.524, 0.316, -0.532, 0.347, -0.534, 0.378, -0.533, 0.408, -0.528, 0.437, -0.519, 0.467, -0.510, 0.495, -0.498, 0.521, -0.481, 0.547, -0.465, 0.569, -0.443, 0.588, -0.419, 0.608, -0.396, 0.621, -0.368, 0.637, -0.342, 0.645, -0.312, 0.649, -0.281, 0.655, -0.251, 0.656, -0.221, 0.655, -0.190, 0.652, -0.159, 0.646, -0.129, 0.639, -0.099, 0.622, -0.073, 0.611, -0.045, 0.591, -0.021, 0.572, 0.003, 0.548, 0.022, 0.523, 0.040, 0.498, 0.058, 0.469, 0.070, 0.441, 0.082, 0.413, 0.093, 0.382, 0.097, 0.351, 0.098, 0.320, 0.098, 0.290, 0.095, 0.260, 0.087, 0.233, 0.072, 0.204, 0.062, 0.180, 0.042, 0.154, 0.026, 0.131, 0.006, 0.110, -0.017, 0.092, -0.042, 0.073, -0.066, 0.063, -0.095, 0.051, -0.123, 0.043, -0.153, 0.040, -0.184, 0.040, -0.214],
        "wSadL": [-0.658, -0.143, -0.657, -0.175, -0.654, -0.206, -0.644, -0.236, -0.633, -0.266, -0.625, -0.296, -0.609, -0.323, -0.592, -0.350, -0.571, -0.373, -0.548, -0.395, -0.525, -0.416, -0.498, -0.432, -0.469, -0.446, -0.439, -0.454, -0.410, -0.465, -0.379, -0.472, -0.347, -0.474, -0.316, -0.472, -0.285, -0.466, -0.254, -0.458, -0.225, -0.447, -0.196, -0.434, -0.170, -0.416, -0.145, -0.396, -0.120, -0.377, -0.103, -0.351, -0.085, -0.325, -0.072, -0.296, -0.058, -0.269, -0.051, -0.238, -0.046, -0.207, -0.041, -0.175, -0.040, -0.144, -0.043, -0.113, -0.048, -0.082, -0.053, -0.050, -0.061, -0.020, -0.078, 0.007, -0.091, 0.035, -0.110, 0.060, -0.129, 0.086, -0.153, 0.106, -0.176, 0.127, -0.203, 0.144, -0.231, 0.158, -0.262, 0.165, -0.292, 0.175, -0.322, 0.184, -0.353, 0.186, -0.385, 0.185, -0.416, 0.180, -0.446, 0.170, -0.476, 0.161, -0.506, 0.150, -0.532, 0.132, -0.557, 0.113, -0.579, 0.090, -0.597, 0.065, -0.615, 0.038, -0.628, 0.010, -0.637, -0.020, -0.649, -0.049, -0.655, -0.080, -0.657, -0.112],
        "wSadR": [0.060, -0.130, 0.063, -0.161, 0.066, -0.191, 0.070, -0.222, 0.077, -0.251, 0.093, -0.277, 0.106, -0.305, 0.125, -0.329, 0.141, -0.354, 0.162, -0.377, 0.188, -0.394, 0.212, -0.412, 0.240, -0.423, 0.266, -0.440, 0.296, -0.445, 0.326, -0.448, 0.357, -0.451, 0.387, -0.451, 0.418, -0.448, 0.448, -0.443, 0.477, -0.432, 0.503, -0.417, 0.529, -0.401, 0.553, -0.382, 0.575, -0.361, 0.594, -0.337, 0.613, -0.313, 0.625, -0.285, 0.640, -0.258, 0.645, -0.228, 0.652, -0.198, 0.658, -0.168, 0.659, -0.138, 0.657, -0.107, 0.650, -0.077, 0.646, -0.047, 0.639, -0.017, 0.624, 0.009, 0.611, 0.037, 0.594, 0.062, 0.576, 0.087, 0.552, 0.106, 0.530, 0.127, 0.505, 0.145, 0.478, 0.158, 0.448, 0.165, 0.420, 0.178, 0.391, 0.185, 0.360, 0.186, 0.330, 0.185, 0.300, 0.178, 0.271, 0.168, 0.241, 0.160, 0.214, 0.147, 0.188, 0.131, 0.163, 0.113, 0.139, 0.094, 0.122, 0.068, 0.103, 0.044, 0.091, 0.016, 0.074, -0.009, 0.068, -0.039, 0.066, -0.070, 0.062, -0.100],
        "wThkL": [-0.690, -0.003, -0.689, -0.034, -0.686, -0.065, -0.678, -0.094, -0.667, -0.123, -0.656, -0.152, -0.639, -0.178, -0.623, -0.204, -0.602, -0.227, -0.580, -0.248, -0.556, -0.267, -0.531, -0.285, -0.502, -0.296, -0.473, -0.306, -0.444, -0.318, -0.414, -0.323, -0.383, -0.324, -0.352, -0.323, -0.322, -0.318, -0.292, -0.310, -0.264, -0.299, -0.234, -0.289, -0.209, -0.271, -0.182, -0.256, -0.161, -0.233, -0.143, -0.209, -0.125, -0.184, -0.109, -0.157, -0.093, -0.131, -0.084, -0.102, -0.079, -0.071, -0.076, -0.041, -0.074, -0.010, -0.076, 0.021, -0.081, 0.051, -0.084, 0.082, -0.093, 0.111, -0.109, 0.138, -0.120, 0.167, -0.140, 0.190, -0.159, 0.215, -0.182, 0.235, -0.208, 0.252, -0.234, 0.269, -0.262, 0.281, -0.291, 0.292, -0.319, 0.303, -0.350, 0.308, -0.381, 0.309, -0.411, 0.309, -0.442, 0.305, -0.472, 0.297, -0.501, 0.286, -0.529, 0.275, -0.554, 0.257, -0.580, 0.240, -0.602, 0.219, -0.623, 0.196, -0.640, 0.170, -0.657, 0.145, -0.669, 0.116, -0.683, 0.089, -0.687, 0.058, -0.689, 0.028],
        "wThkR": [-0.030, -0.287, -0.030, -0.318, -0.027, -0.348, -0.024, -0.379, -0.018, -0.409, -0.006, -0.437, 0.008, -0.464, 0.028, -0.487, 0.046, -0.512, 0.067, -0.534, 0.092, -0.552, 0.117, -0.570, 0.142, -0.587, 0.170, -0.598, 0.201, -0.603, 0.230, -0.612, 0.260, -0.616, 0.291, -0.616, 0.321, -0.612, 0.351, -0.604, 0.380, -0.598, 0.408, -0.585, 0.435, -0.570, 0.461, -0.554, 0.485, -0.535, 0.505, -0.512, 0.523, -0.487, 0.542, -0.463, 0.555, -0.436, 0.568, -0.408, 0.579, -0.379, 0.582, -0.349, 0.582, -0.318, 0.582, -0.288, 0.580, -0.257, 0.576, -0.227, 0.563, -0.199, 0.553, -0.170, 0.541, -0.142, 0.524, -0.117, 0.504, -0.094, 0.482, -0.072, 0.458, -0.053, 0.433, -0.037, 0.405, -0.023, 0.377, -0.012, 0.349, 0.001, 0.319, 0.006, 0.288, 0.007, 0.258, 0.007, 0.227, 0.006, 0.197, 0.002, 0.168, -0.008, 0.140, -0.020, 0.112, -0.032, 0.087, -0.050, 0.065, -0.071, 0.041, -0.090, 0.023, -0.115, 0.008, -0.141, -0.003, -0.170, -0.018, -0.196, -0.024, -0.227, -0.027, -0.257],
        "wAngL": [-0.669, -0.141, -0.664, -0.167, -0.661, -0.193, -0.657, -0.219, -0.650, -0.245, -0.635, -0.266, -0.623, -0.289, -0.604, -0.307, -0.578, -0.311, -0.552, -0.304, -0.531, -0.289, -0.506, -0.280, -0.481, -0.273, -0.458, -0.260, -0.434, -0.249, -0.409, -0.243, -0.386, -0.229, -0.362, -0.218, -0.337, -0.211, -0.314, -0.198, -0.290, -0.188, -0.264, -0.181, -0.239, -0.174, -0.217, -0.159, -0.193, -0.148, -0.170, -0.136, -0.145, -0.130, -0.120, -0.121, -0.099, -0.106, -0.080, -0.089, -0.080, -0.063, -0.084, -0.037, -0.092, -0.012, -0.106, 0.010, -0.119, 0.033, -0.134, 0.054, -0.149, 0.076, -0.169, 0.092, -0.187, 0.111, -0.210, 0.124, -0.232, 0.139, -0.257, 0.147, -0.281, 0.156, -0.305, 0.167, -0.331, 0.170, -0.358, 0.172, -0.384, 0.172, -0.410, 0.170, -0.436, 0.167, -0.462, 0.160, -0.486, 0.149, -0.511, 0.141, -0.533, 0.127, -0.554, 0.112, -0.573, 0.093, -0.594, 0.077, -0.607, 0.054, -0.624, 0.034, -0.635, 0.011, -0.649, -0.011, -0.657, -0.037, -0.660, -0.063, -0.663, -0.089, -0.667, -0.115],
        "wAngR": [0.062, -0.084, 0.074, -0.107, 0.096, -0.121, 0.122, -0.129, 0.147, -0.138, 0.170, -0.151, 0.195, -0.158, 0.220, -0.167, 0.243, -0.180, 0.268, -0.188, 0.293, -0.196, 0.315, -0.211, 0.340, -0.218, 0.364, -0.229, 0.386, -0.244, 0.412, -0.250, 0.433, -0.265, 0.458, -0.275, 0.483, -0.283, 0.505, -0.297, 0.529, -0.309, 0.554, -0.317, 0.579, -0.322, 0.600, -0.305, 0.613, -0.282, 0.624, -0.258, 0.637, -0.236, 0.643, -0.210, 0.647, -0.184, 0.650, -0.158, 0.653, -0.131, 0.651, -0.105, 0.647, -0.079, 0.644, -0.052, 0.638, -0.026, 0.627, -0.003, 0.614, 0.021, 0.603, 0.044, 0.584, 0.063, 0.568, 0.084, 0.548, 0.102, 0.526, 0.116, 0.505, 0.132, 0.481, 0.144, 0.455, 0.150, 0.430, 0.159, 0.405, 0.166, 0.379, 0.170, 0.352, 0.172, 0.326, 0.170, 0.300, 0.167, 0.274, 0.160, 0.249, 0.151, 0.224, 0.143, 0.201, 0.130, 0.181, 0.113, 0.159, 0.097, 0.138, 0.082, 0.124, 0.059, 0.105, 0.040, 0.094, 0.016, 0.082, -0.007, 0.071, -0.031, 0.066, -0.057],
        "wWinkL": [-0.681, -0.151, -0.680, -0.182, -0.678, -0.212, -0.673, -0.242, -0.664, -0.271, -0.648, -0.296, -0.635, -0.323, -0.616, -0.347, -0.597, -0.370, -0.578, -0.394, -0.552, -0.409, -0.528, -0.428, -0.500, -0.441, -0.474, -0.455, -0.444, -0.461, -0.414, -0.463, -0.384, -0.465, -0.354, -0.466, -0.323, -0.463, -0.294, -0.458, -0.267, -0.444, -0.239, -0.432, -0.213, -0.416, -0.188, -0.400, -0.165, -0.380, -0.147, -0.356, -0.129, -0.332, -0.111, -0.307, -0.099, -0.279, -0.092, -0.250, -0.086, -0.220, -0.074, -0.192, -0.075, -0.162, -0.073, -0.132, -0.075, -0.102, -0.087, -0.074, -0.095, -0.045, -0.105, -0.016, -0.123, 0.008, -0.137, 0.035, -0.157, 0.057, -0.178, 0.079, -0.203, 0.096, -0.227, 0.114, -0.255, 0.125, -0.282, 0.139, -0.312, 0.144, -0.342, 0.147, -0.372, 0.149, -0.403, 0.147, -0.433, 0.144, -0.463, 0.140, -0.491, 0.130, -0.519, 0.117, -0.546, 0.105, -0.570, 0.087, -0.592, 0.065, -0.614, 0.045, -0.634, 0.022, -0.646, -0.006, -0.660, -0.033, -0.671, -0.061, -0.674, -0.091, -0.678, -0.121],
        "happyL": [-0.702, -0.154, -0.701, -0.183, -0.694, -0.211, -0.688, -0.239, -0.676, -0.266, -0.662, -0.291, -0.647, -0.316, -0.628, -0.338, -0.608, -0.358, -0.586, -0.377, -0.561, -0.392, -0.536, -0.406, -0.510, -0.418, -0.482, -0.428, -0.454, -0.435, -0.426, -0.439, -0.397, -0.440, -0.368, -0.437, -0.340, -0.432, -0.312, -0.424, -0.284, -0.415, -0.259, -0.401, -0.235, -0.385, -0.212, -0.367, -0.191, -0.348, -0.171, -0.327, -0.153, -0.304, -0.139, -0.279, -0.127, -0.252, -0.116, -0.226, -0.110, -0.197, -0.106, -0.169, -0.107, -0.140, -0.116, -0.112, -0.136, -0.092, -0.164, -0.084, -0.192, -0.090, -0.212, -0.111, -0.224, -0.137, -0.232, -0.165, -0.240, -0.193, -0.252, -0.219, -0.266, -0.244, -0.286, -0.265, -0.309, -0.283, -0.334, -0.297, -0.360, -0.309, -0.389, -0.313, -0.418, -0.313, -0.446, -0.308, -0.473, -0.298, -0.499, -0.284, -0.521, -0.266, -0.541, -0.245, -0.560, -0.223, -0.572, -0.197, -0.583, -0.170, -0.589, -0.142, -0.597, -0.114, -0.613, -0.090, -0.639, -0.079, -0.668, -0.081, -0.692, -0.098, -0.701, -0.125],
        "happyR": [0.115, -0.177, 0.119, -0.206, 0.126, -0.234, 0.134, -0.262, 0.147, -0.288, 0.160, -0.313, 0.179, -0.336, 0.197, -0.359, 0.217, -0.379, 0.240, -0.396, 0.262, -0.415, 0.288, -0.429, 0.314, -0.441, 0.342, -0.448, 0.370, -0.455, 0.399, -0.458, 0.428, -0.458, 0.457, -0.455, 0.485, -0.449, 0.514, -0.442, 0.540, -0.430, 0.565, -0.417, 0.590, -0.401, 0.612, -0.383, 0.633, -0.363, 0.651, -0.340, 0.669, -0.317, 0.682, -0.291, 0.693, -0.265, 0.703, -0.237, 0.709, -0.209, 0.714, -0.181, 0.713, -0.152, 0.703, -0.125, 0.680, -0.107, 0.652, -0.101, 0.624, -0.109, 0.605, -0.130, 0.597, -0.158, 0.588, -0.186, 0.581, -0.214, 0.570, -0.240, 0.552, -0.263, 0.532, -0.284, 0.510, -0.303, 0.484, -0.315, 0.456, -0.325, 0.427, -0.327, 0.398, -0.326, 0.370, -0.322, 0.343, -0.312, 0.317, -0.298, 0.293, -0.282, 0.274, -0.261, 0.257, -0.237, 0.245, -0.211, 0.233, -0.184, 0.227, -0.156, 0.219, -0.128, 0.201, -0.106, 0.174, -0.096, 0.146, -0.102, 0.124, -0.121, 0.115, -0.148],
        "dashL": [-0.638, -0.104, -0.633, -0.123, -0.624, -0.140, -0.608, -0.152, -0.590, -0.158, -0.571, -0.160, -0.552, -0.160, -0.532, -0.161, -0.513, -0.163, -0.494, -0.163, -0.474, -0.165, -0.455, -0.166, -0.436, -0.168, -0.416, -0.170, -0.397, -0.171, -0.378, -0.172, -0.358, -0.174, -0.339, -0.175, -0.320, -0.178, -0.301, -0.180, -0.282, -0.182, -0.262, -0.184, -0.243, -0.185, -0.224, -0.187, -0.204, -0.188, -0.185, -0.188, -0.166, -0.189, -0.146, -0.189, -0.127, -0.187, -0.110, -0.179, -0.095, -0.166, -0.085, -0.149, -0.084, -0.130, -0.088, -0.111, -0.099, -0.095, -0.114, -0.083, -0.131, -0.074, -0.150, -0.070, -0.169, -0.068, -0.188, -0.067, -0.208, -0.067, -0.227, -0.066, -0.246, -0.065, -0.266, -0.064, -0.285, -0.063, -0.304, -0.061, -0.324, -0.060, -0.343, -0.058, -0.362, -0.057, -0.382, -0.056, -0.401, -0.055, -0.420, -0.055, -0.440, -0.054, -0.459, -0.051, -0.478, -0.049, -0.497, -0.048, -0.517, -0.046, -0.536, -0.044, -0.555, -0.042, -0.574, -0.042, -0.593, -0.047, -0.610, -0.057, -0.625, -0.068, -0.635, -0.085],
        "dashR": [0.128, -0.138, 0.130, -0.157, 0.140, -0.174, 0.154, -0.186, 0.173, -0.192, 0.192, -0.194, 0.211, -0.194, 0.231, -0.193, 0.250, -0.192, 0.269, -0.191, 0.289, -0.190, 0.308, -0.189, 0.327, -0.189, 0.347, -0.188, 0.366, -0.187, 0.385, -0.185, 0.404, -0.184, 0.424, -0.183, 0.443, -0.180, 0.462, -0.178, 0.481, -0.177, 0.501, -0.175, 0.520, -0.173, 0.539, -0.172, 0.558, -0.171, 0.578, -0.171, 0.597, -0.170, 0.616, -0.168, 0.635, -0.164, 0.654, -0.158, 0.669, -0.146, 0.677, -0.129, 0.682, -0.110, 0.678, -0.091, 0.670, -0.074, 0.654, -0.063, 0.636, -0.056, 0.616, -0.055, 0.597, -0.055, 0.578, -0.055, 0.558, -0.055, 0.539, -0.056, 0.520, -0.057, 0.500, -0.058, 0.481, -0.059, 0.462, -0.060, 0.442, -0.062, 0.423, -0.064, 0.404, -0.065, 0.385, -0.066, 0.365, -0.067, 0.346, -0.067, 0.327, -0.068, 0.307, -0.069, 0.288, -0.070, 0.269, -0.070, 0.249, -0.071, 0.230, -0.073, 0.211, -0.074, 0.192, -0.077, 0.173, -0.083, 0.155, -0.090, 0.140, -0.102, 0.131, -0.119],
        "winkR": [0.108, -0.230, 0.110, -0.252, 0.113, -0.274, 0.118, -0.296, 0.127, -0.317, 0.138, -0.337, 0.149, -0.356, 0.161, -0.375, 0.174, -0.393, 0.188, -0.410, 0.204, -0.427, 0.221, -0.441, 0.238, -0.455, 0.258, -0.466, 0.278, -0.477, 0.298, -0.487, 0.320, -0.492, 0.342, -0.495, 0.364, -0.497, 0.386, -0.497, 0.409, -0.495, 0.431, -0.492, 0.453, -0.487, 0.474, -0.479, 0.494, -0.470, 0.514, -0.460, 0.533, -0.448, 0.551, -0.434, 0.568, -0.420, 0.584, -0.404, 0.598, -0.386, 0.609, -0.367, 0.617, -0.346, 0.618, -0.324, 0.609, -0.303, 0.594, -0.286, 0.573, -0.279, 0.551, -0.279, 0.530, -0.285, 0.512, -0.300, 0.497, -0.316, 0.480, -0.331, 0.461, -0.343, 0.442, -0.355, 0.421, -0.363, 0.399, -0.368, 0.377, -0.369, 0.355, -0.366, 0.334, -0.359, 0.314, -0.348, 0.295, -0.336, 0.278, -0.322, 0.263, -0.305, 0.251, -0.286, 0.241, -0.266, 0.233, -0.245, 0.225, -0.224, 0.216, -0.204, 0.204, -0.185, 0.185, -0.173, 0.162, -0.171, 0.140, -0.175, 0.122, -0.188, 0.112, -0.208],
        "browL": [-0.567, -0.496, -0.565, -0.514, -0.555, -0.529, -0.539, -0.539, -0.523, -0.548, -0.504, -0.548, -0.487, -0.542, -0.471, -0.532, -0.455, -0.523, -0.438, -0.516, -0.423, -0.505, -0.406, -0.498, -0.390, -0.490, -0.373, -0.481, -0.357, -0.472, -0.341, -0.463, -0.324, -0.455, -0.309, -0.446, -0.293, -0.436, -0.276, -0.428, -0.261, -0.418, -0.245, -0.409, -0.228, -0.400, -0.212, -0.392, -0.196, -0.382, -0.180, -0.373, -0.164, -0.365, -0.148, -0.355, -0.132, -0.346, -0.116, -0.336, -0.104, -0.323, -0.096, -0.306, -0.092, -0.288, -0.097, -0.270, -0.105, -0.254, -0.119, -0.241, -0.137, -0.236, -0.155, -0.238, -0.173, -0.244, -0.190, -0.251, -0.206, -0.259, -0.222, -0.269, -0.238, -0.278, -0.254, -0.287, -0.269, -0.297, -0.285, -0.306, -0.302, -0.314, -0.318, -0.323, -0.334, -0.333, -0.350, -0.341, -0.366, -0.350, -0.382, -0.359, -0.399, -0.368, -0.415, -0.376, -0.431, -0.385, -0.447, -0.394, -0.464, -0.402, -0.480, -0.411, -0.496, -0.420, -0.512, -0.430, -0.528, -0.438, -0.543, -0.449, -0.557, -0.461, -0.566, -0.477],
        "browR": [0.067, -0.288, 0.070, -0.306, 0.079, -0.322, 0.091, -0.335, 0.105, -0.346, 0.120, -0.355, 0.135, -0.366, 0.151, -0.373, 0.166, -0.383, 0.182, -0.392, 0.197, -0.402, 0.212, -0.411, 0.228, -0.420, 0.243, -0.429, 0.259, -0.437, 0.275, -0.446, 0.290, -0.456, 0.306, -0.463, 0.322, -0.472, 0.338, -0.480, 0.352, -0.491, 0.368, -0.499, 0.384, -0.508, 0.399, -0.517, 0.415, -0.525, 0.431, -0.534, 0.447, -0.542, 0.464, -0.548, 0.482, -0.547, 0.497, -0.537, 0.512, -0.528, 0.521, -0.513, 0.523, -0.495, 0.521, -0.477, 0.514, -0.460, 0.501, -0.449, 0.487, -0.437, 0.471, -0.429, 0.456, -0.419, 0.441, -0.409, 0.426, -0.400, 0.410, -0.391, 0.395, -0.382, 0.379, -0.373, 0.363, -0.365, 0.348, -0.355, 0.333, -0.346, 0.316, -0.339, 0.301, -0.329, 0.286, -0.320, 0.271, -0.310, 0.254, -0.303, 0.239, -0.294, 0.224, -0.283, 0.209, -0.275, 0.193, -0.266, 0.178, -0.257, 0.161, -0.249, 0.145, -0.243, 0.127, -0.238, 0.109, -0.238, 0.093, -0.245, 0.078, -0.255, 0.069, -0.271],
        "O": [-0.264, 0.469, -0.263, 0.441, -0.260, 0.414, -0.251, 0.388, -0.245, 0.361, -0.234, 0.335, -0.222, 0.311, -0.207, 0.288, -0.190, 0.265, -0.172, 0.245, -0.152, 0.226, -0.129, 0.210, -0.107, 0.194, -0.081, 0.185, -0.054, 0.177, -0.027, 0.174, 0.001, 0.170, 0.028, 0.171, 0.055, 0.177, 0.081, 0.185, 0.108, 0.194, 0.130, 0.210, 0.153, 0.225, 0.173, 0.244, 0.192, 0.264, 0.208, 0.286, 0.222, 0.311, 0.235, 0.335, 0.246, 0.360, 0.251, 0.387, 0.258, 0.414, 0.261, 0.441, 0.262, 0.469, 0.261, 0.497, 0.257, 0.524, 0.252, 0.551, 0.246, 0.578, 0.233, 0.602, 0.220, 0.626, 0.204, 0.649, 0.188, 0.672, 0.170, 0.693, 0.150, 0.711, 0.128, 0.728, 0.104, 0.741, 0.078, 0.751, 0.052, 0.761, 0.025, 0.765, -0.003, 0.766, -0.030, 0.765, -0.058, 0.762, -0.084, 0.755, -0.109, 0.744, -0.134, 0.731, -0.154, 0.712, -0.175, 0.694, -0.194, 0.674, -0.209, 0.651, -0.223, 0.627, -0.236, 0.603, -0.246, 0.577, -0.253, 0.551, -0.261, 0.524, -0.263, 0.497],
        "frown": [-0.398, 0.532, -0.391, 0.503, -0.377, 0.478, -0.357, 0.457, -0.335, 0.438, -0.312, 0.421, -0.287, 0.405, -0.261, 0.393, -0.234, 0.381, -0.207, 0.372, -0.179, 0.362, -0.152, 0.353, -0.124, 0.344, -0.095, 0.339, -0.067, 0.335, -0.038, 0.331, -0.009, 0.330, 0.020, 0.330, 0.049, 0.330, 0.078, 0.331, 0.107, 0.335, 0.136, 0.340, 0.164, 0.345, 0.192, 0.354, 0.219, 0.364, 0.247, 0.374, 0.272, 0.388, 0.298, 0.401, 0.322, 0.418, 0.345, 0.435, 0.367, 0.454, 0.387, 0.476, 0.401, 0.501, 0.405, 0.529, 0.399, 0.558, 0.379, 0.578, 0.351, 0.584, 0.322, 0.581, 0.296, 0.568, 0.271, 0.554, 0.245, 0.539, 0.220, 0.526, 0.192, 0.516, 0.166, 0.504, 0.138, 0.496, 0.109, 0.490, 0.080, 0.488, 0.051, 0.485, 0.022, 0.485, -0.007, 0.485, -0.036, 0.488, -0.065, 0.491, -0.094, 0.494, -0.122, 0.501, -0.149, 0.511, -0.177, 0.520, -0.204, 0.530, -0.230, 0.543, -0.256, 0.555, -0.283, 0.565, -0.310, 0.578, -0.338, 0.582, -0.367, 0.578, -0.389, 0.559],
        "dot": [0.070, 0.362, 0.070, 0.350, 0.072, 0.338, 0.075, 0.327, 0.080, 0.316, 0.085, 0.305, 0.091, 0.295, 0.098, 0.285, 0.106, 0.277, 0.116, 0.270, 0.125, 0.263, 0.134, 0.255, 0.145, 0.251, 0.157, 0.248, 0.168, 0.245, 0.180, 0.244, 0.192, 0.243, 0.204, 0.244, 0.215, 0.246, 0.227, 0.248, 0.238, 0.252, 0.248, 0.259, 0.257, 0.266, 0.267, 0.273, 0.276, 0.281, 0.283, 0.290, 0.290, 0.300, 0.295, 0.311, 0.299, 0.322, 0.303, 0.333, 0.306, 0.344, 0.307, 0.356, 0.307, 0.368, 0.306, 0.380, 0.305, 0.392, 0.300, 0.403, 0.296, 0.413, 0.291, 0.424, 0.285, 0.434, 0.278, 0.444, 0.271, 0.454, 0.262, 0.461, 0.252, 0.467, 0.241, 0.473, 0.230, 0.478, 0.220, 0.483, 0.209, 0.487, 0.197, 0.488, 0.185, 0.488, 0.173, 0.487, 0.162, 0.485, 0.151, 0.480, 0.140, 0.476, 0.129, 0.470, 0.119, 0.464, 0.109, 0.458, 0.100, 0.450, 0.094, 0.440, 0.088, 0.429, 0.083, 0.418, 0.079, 0.408, 0.073, 0.397, 0.071, 0.385, 0.070, 0.374],
        "D": [-0.551, 0.246, -0.540, 0.204, -0.513, 0.170, -0.475, 0.149, -0.433, 0.140, -0.389, 0.142, -0.346, 0.148, -0.305, 0.160, -0.263, 0.172, -0.221, 0.184, -0.179, 0.191, -0.136, 0.200, -0.093, 0.206, -0.050, 0.209, -0.006, 0.209, 0.037, 0.208, 0.080, 0.206, 0.122, 0.195, 0.165, 0.189, 0.208, 0.179, 0.249, 0.166, 0.290, 0.152, 0.332, 0.139, 0.374, 0.130, 0.417, 0.130, 0.460, 0.136, 0.497, 0.160, 0.522, 0.195, 0.533, 0.237, 0.532, 0.280, 0.524, 0.323, 0.511, 0.364, 0.493, 0.404, 0.470, 0.441, 0.447, 0.478, 0.421, 0.512, 0.391, 0.544, 0.359, 0.573, 0.324, 0.598, 0.288, 0.622, 0.250, 0.644, 0.211, 0.663, 0.170, 0.677, 0.128, 0.687, 0.085, 0.697, 0.042, 0.700, -0.001, 0.700, -0.045, 0.698, -0.087, 0.689, -0.130, 0.683, -0.172, 0.673, -0.213, 0.657, -0.253, 0.640, -0.291, 0.619, -0.328, 0.597, -0.364, 0.572, -0.397, 0.545, -0.429, 0.515, -0.458, 0.483, -0.484, 0.448, -0.507, 0.411, -0.525, 0.372, -0.541, 0.332, -0.550, 0.289],
        "zig": [-0.564, 0.557, -0.544, 0.517, -0.516, 0.481, -0.485, 0.448, -0.455, 0.416, -0.421, 0.386, -0.381, 0.365, -0.337, 0.368, -0.298, 0.390, -0.262, 0.417, -0.228, 0.446, -0.193, 0.474, -0.156, 0.452, -0.126, 0.419, -0.094, 0.387, -0.059, 0.359, -0.017, 0.343, 0.027, 0.349, 0.065, 0.372, 0.100, 0.400, 0.133, 0.430, 0.173, 0.450, 0.207, 0.423, 0.240, 0.391, 0.273, 0.362, 0.311, 0.337, 0.355, 0.334, 0.395, 0.353, 0.430, 0.381, 0.464, 0.411, 0.497, 0.442, 0.529, 0.473, 0.550, 0.512, 0.541, 0.555, 0.501, 0.573, 0.460, 0.557, 0.428, 0.525, 0.397, 0.493, 0.364, 0.462, 0.321, 0.456, 0.290, 0.489, 0.257, 0.520, 0.226, 0.552, 0.188, 0.575, 0.143, 0.572, 0.105, 0.547, 0.073, 0.517, 0.040, 0.486, 0.004, 0.459, -0.036, 0.479, -0.069, 0.509, -0.101, 0.540, -0.135, 0.570, -0.173, 0.593, -0.217, 0.585, -0.256, 0.562, -0.291, 0.534, -0.325, 0.505, -0.364, 0.482, -0.400, 0.507, -0.431, 0.539, -0.461, 0.572, -0.497, 0.598, -0.541, 0.595],
        "yawn": [-0.242, 0.499, -0.239, 0.475, -0.235, 0.451, -0.229, 0.427, -0.217, 0.406, -0.208, 0.383, -0.198, 0.361, -0.181, 0.343, -0.167, 0.323, -0.150, 0.306, -0.130, 0.291, -0.112, 0.275, -0.090, 0.263, -0.069, 0.250, -0.047, 0.239, -0.024, 0.233, 0, 0.228, 0.024, 0.223, 0.049, 0.222, 0.073, 0.222, 0.097, 0.225, 0.121, 0.230, 0.145, 0.237, 0.167, 0.247, 0.189, 0.258, 0.210, 0.270, 0.228, 0.287, 0.246, 0.303, 0.261, 0.323, 0.275, 0.343, 0.285, 0.365, 0.293, 0.388, 0.301, 0.411, 0.306, 0.435, 0.308, 0.460, 0.307, 0.484, 0.300, 0.508, 0.286, 0.528, 0.268, 0.544, 0.246, 0.555, 0.222, 0.562, 0.198, 0.563, 0.174, 0.558, 0.150, 0.552, 0.126, 0.549, 0.101, 0.549, 0.077, 0.551, 0.054, 0.559, 0.031, 0.568, 0.010, 0.580, -0.010, 0.594, -0.030, 0.609, -0.048, 0.625, -0.069, 0.638, -0.092, 0.646, -0.116, 0.651, -0.141, 0.648, -0.164, 0.641, -0.185, 0.628, -0.204, 0.612, -0.217, 0.592, -0.231, 0.572, -0.236, 0.548, -0.240, 0.524],
        "winkMouth": [-0.370, 0.352, -0.346, 0.319, -0.306, 0.313, -0.266, 0.323, -0.227, 0.334, -0.187, 0.343, -0.146, 0.348, -0.105, 0.353, -0.065, 0.354, -0.024, 0.352, 0.017, 0.346, 0.057, 0.338, 0.096, 0.325, 0.135, 0.313, 0.173, 0.297, 0.209, 0.278, 0.244, 0.257, 0.276, 0.232, 0.307, 0.205, 0.337, 0.177, 0.365, 0.147, 0.390, 0.115, 0.412, 0.080, 0.432, 0.044, 0.447, 0.006, 0.467, -0.029, 0.504, -0.045, 0.540, -0.028, 0.550, 0.011, 0.540, 0.051, 0.522, 0.088, 0.504, 0.124, 0.481, 0.158, 0.461, 0.194, 0.435, 0.225, 0.407, 0.256, 0.383, 0.288, 0.394, 0.327, 0.420, 0.359, 0.442, 0.393, 0.458, 0.431, 0.452, 0.471, 0.416, 0.487, 0.383, 0.462, 0.359, 0.429, 0.337, 0.394, 0.312, 0.362, 0.272, 0.362, 0.237, 0.383, 0.200, 0.400, 0.163, 0.417, 0.124, 0.430, 0.085, 0.441, 0.044, 0.447, 0.003, 0.452, -0.037, 0.456, -0.078, 0.455, -0.119, 0.454, -0.160, 0.450, -0.201, 0.446, -0.240, 0.436, -0.279, 0.423, -0.318, 0.410, -0.353, 0.389],
        "tongue": [0.149, 0.423, 0.166, 0.402, 0.188, 0.386, 0.211, 0.371, 0.234, 0.356, 0.261, 0.351, 0.281, 0.332, 0.308, 0.331, 0.327, 0.350, 0.346, 0.370, 0.359, 0.394, 0.376, 0.415, 0.389, 0.440, 0.407, 0.460, 0.430, 0.464, 0.438, 0.439, 0.425, 0.415, 0.414, 0.390, 0.403, 0.366, 0.384, 0.346, 0.366, 0.326, 0.357, 0.301, 0.367, 0.277, 0.383, 0.255, 0.397, 0.232, 0.416, 0.212, 0.435, 0.193, 0.457, 0.179, 0.481, 0.189, 0.498, 0.210, 0.517, 0.230, 0.535, 0.251, 0.550, 0.273, 0.565, 0.296, 0.579, 0.320, 0.592, 0.344, 0.600, 0.370, 0.608, 0.396, 0.614, 0.423, 0.616, 0.450, 0.613, 0.478, 0.607, 0.504, 0.599, 0.530, 0.590, 0.556, 0.574, 0.578, 0.557, 0.599, 0.536, 0.616, 0.511, 0.629, 0.486, 0.639, 0.459, 0.646, 0.432, 0.648, 0.405, 0.649, 0.378, 0.645, 0.351, 0.636, 0.326, 0.627, 0.302, 0.614, 0.281, 0.596, 0.262, 0.576, 0.240, 0.559, 0.225, 0.536, 0.207, 0.515, 0.194, 0.492, 0.177, 0.470, 0.167, 0.444],
        "wavy": [-0.493, 0.593, -0.487, 0.547, -0.470, 0.504, -0.445, 0.466, -0.412, 0.433, -0.374, 0.407, -0.331, 0.390, -0.286, 0.386, -0.240, 0.389, -0.196, 0.403, -0.155, 0.424, -0.113, 0.444, -0.068, 0.453, -0.023, 0.445, 0.015, 0.419, 0.044, 0.383, 0.068, 0.344, 0.097, 0.308, 0.129, 0.275, 0.167, 0.249, 0.210, 0.232, 0.255, 0.224, 0.301, 0.229, 0.345, 0.242, 0.388, 0.258, 0.430, 0.278, 0.473, 0.293, 0.519, 0.288, 0.559, 0.265, 0.581, 0.225, 0.614, 0.193, 0.659, 0.196, 0.680, 0.237, 0.668, 0.281, 0.646, 0.321, 0.615, 0.356, 0.577, 0.382, 0.534, 0.398, 0.488, 0.401, 0.442, 0.396, 0.399, 0.380, 0.357, 0.360, 0.315, 0.341, 0.270, 0.332, 0.225, 0.338, 0.185, 0.361, 0.155, 0.396, 0.130, 0.435, 0.104, 0.472, 0.071, 0.505, 0.033, 0.531, -0.009, 0.549, -0.055, 0.554, -0.101, 0.552, -0.145, 0.538, -0.187, 0.519, -0.227, 0.497, -0.272, 0.488, -0.318, 0.491, -0.358, 0.514, -0.385, 0.551, -0.401, 0.594, -0.427, 0.632, -0.471, 0.632],
        "spiralL": [-0.761, -0.153, -0.761, -0.177, -0.759, -0.200, -0.755, -0.224, -0.749, -0.247, -0.741, -0.269, -0.732, -0.291, -0.721, -0.312, -0.708, -0.331, -0.694, -0.351, -0.678, -0.368, -0.662, -0.385, -0.644, -0.402, -0.626, -0.416, -0.606, -0.429, -0.586, -0.441, -0.565, -0.452, -0.543, -0.461, -0.521, -0.469, -0.498, -0.474, -0.474, -0.476, -0.450, -0.477, -0.427, -0.477, -0.403, -0.475, -0.380, -0.471, -0.358, -0.463, -0.336, -0.454, -0.314, -0.444, -0.294, -0.432, -0.275, -0.418, -0.256, -0.403, -0.240, -0.386, -0.224, -0.368, -0.210, -0.349, -0.197, -0.330, -0.186, -0.308, -0.176, -0.287, -0.166, -0.265, -0.160, -0.243, -0.157, -0.219, -0.156, -0.195, -0.158, -0.172, -0.160, -0.148, -0.166, -0.125, -0.176, -0.104, -0.186, -0.082, -0.198, -0.062, -0.213, -0.044, -0.230, -0.027, -0.249, -0.013, -0.269, 0, -0.290, 0.011, -0.312, 0.020, -0.334, 0.029, -0.356, 0.035, -0.380, 0.037, -0.404, 0.037, -0.427, 0.035, -0.450, 0.030, -0.473, 0.022, -0.495, 0.014, -0.516, 0.003, -0.534, -0.011, -0.552, -0.028, -0.567, -0.046, -0.581, -0.065, -0.592, -0.086, -0.602, -0.107, -0.609, -0.130, -0.611, -0.153, -0.611, -0.177, -0.606, -0.200, -0.597, -0.222, -0.587, -0.244, -0.574, -0.264, -0.558, -0.281, -0.540, -0.296, -0.520, -0.308, -0.499, -0.319, -0.476, -0.324, -0.452, -0.327, -0.429, -0.326, -0.405, -0.322, -0.384, -0.312, -0.363, -0.301, -0.345, -0.286, -0.330, -0.268, -0.318, -0.248, -0.311, -0.225, -0.311, -0.201, -0.315, -0.178, -0.325, -0.157, -0.340, -0.139, -0.359, -0.124, -0.381, -0.116, -0.404, -0.114, -0.427, -0.120, -0.448, -0.132, -0.464, -0.148, -0.472, -0.170, -0.465, -0.192, -0.443, -0.199, -0.420, -0.193, -0.397, -0.191, -0.384, -0.210, -0.391, -0.232, -0.409, -0.247, -0.432, -0.253, -0.456, -0.252, -0.479, -0.246, -0.499, -0.233, -0.516, -0.217, -0.526, -0.196, -0.533, -0.173, -0.535, -0.150, -0.531, -0.127, -0.522, -0.105, -0.509, -0.085, -0.492, -0.069, -0.472, -0.055, -0.451, -0.045, -0.428, -0.039, -0.405, -0.036, -0.381, -0.036, -0.358, -0.039, -0.335, -0.047, -0.313, -0.056, -0.293, -0.068, -0.274, -0.082, -0.259, -0.100, -0.248, -0.121, -0.238, -0.143, -0.233, -0.166, -0.232, -0.189, -0.232, -0.213, -0.236, -0.236, -0.243, -0.259, -0.252, -0.281, -0.263, -0.302, -0.278, -0.320, -0.294, -0.338, -0.312, -0.354, -0.330, -0.369, -0.351, -0.380, -0.373, -0.389, -0.395, -0.397, -0.418, -0.403, -0.441, -0.405, -0.465, -0.404, -0.488, -0.400, -0.511, -0.393, -0.533, -0.384, -0.555, -0.374, -0.575, -0.362, -0.594, -0.349, -0.613, -0.334, -0.630, -0.317, -0.644, -0.299, -0.656, -0.278, -0.667, -0.257, -0.674, -0.235, -0.679, -0.211, -0.683, -0.188, -0.685, -0.165, -0.684, -0.141, -0.681, -0.117, -0.676, -0.094, -0.671, -0.071, -0.663, -0.049, -0.652, -0.028, -0.639, -0.008, -0.625, 0.011, -0.609, 0.029, -0.592, 0.045, -0.573, 0.059, -0.553, 0.071, -0.532, 0.082, -0.509, 0.090, -0.486, 0.096, -0.463, 0.099, -0.439, 0.100, -0.416, 0.100, -0.392, 0.099, -0.368, 0.096, -0.345, 0.090, -0.323, 0.082, -0.302, 0.073, -0.278, 0.069, -0.256, 0.076, -0.244, 0.096, -0.248, 0.119, -0.266, 0.135, -0.286, 0.147, -0.308, 0.156, -0.331, 0.162, -0.354, 0.169, -0.377, 0.172, -0.401, 0.172, -0.425, 0.172, -0.448, 0.172, -0.472, 0.172, -0.495, 0.170, -0.519, 0.165, -0.541, 0.158, -0.563, 0.149, -0.584, 0.137, -0.604, 0.125, -0.623, 0.111, -0.641, 0.096, -0.658, 0.080, -0.674, 0.062, -0.689, 0.044, -0.703, 0.025, -0.715, 0.004, -0.727, -0.016, -0.736, -0.038, -0.744, -0.060, -0.750, -0.083, -0.756, -0.106, -0.760, -0.129],
        "spiralR": [0.008, -0.335, 0.009, -0.358, 0.013, -0.380, 0.019, -0.403, 0.025, -0.425, 0.035, -0.446, 0.046, -0.466, 0.059, -0.485, 0.073, -0.503, 0.088, -0.521, 0.104, -0.537, 0.121, -0.553, 0.139, -0.567, 0.158, -0.580, 0.178, -0.592, 0.199, -0.602, 0.220, -0.611, 0.242, -0.619, 0.264, -0.625, 0.287, -0.629, 0.310, -0.631, 0.333, -0.632, 0.356, -0.632, 0.379, -0.630, 0.401, -0.628, 0.424, -0.623, 0.446, -0.615, 0.467, -0.607, 0.488, -0.597, 0.508, -0.585, 0.527, -0.572, 0.545, -0.558, 0.563, -0.543, 0.579, -0.527, 0.593, -0.509, 0.607, -0.490, 0.620, -0.471, 0.630, -0.451, 0.640, -0.430, 0.649, -0.409, 0.656, -0.387, 0.661, -0.364, 0.664, -0.341, 0.662, -0.318, 0.651, -0.299, 0.629, -0.293, 0.608, -0.302, 0.597, -0.322, 0.591, -0.344, 0.585, -0.366, 0.578, -0.389, 0.571, -0.410, 0.561, -0.431, 0.547, -0.450, 0.534, -0.468, 0.518, -0.485, 0.501, -0.501, 0.482, -0.514, 0.463, -0.526, 0.442, -0.536, 0.420, -0.544, 0.398, -0.551, 0.376, -0.555, 0.353, -0.557, 0.330, -0.558, 0.307, -0.556, 0.284, -0.554, 0.262, -0.547, 0.240, -0.539, 0.219, -0.530, 0.199, -0.519, 0.179, -0.506, 0.161, -0.492, 0.144, -0.476, 0.129, -0.459, 0.116, -0.440, 0.104, -0.420, 0.095, -0.399, 0.088, -0.377, 0.084, -0.355, 0.083, -0.332, 0.083, -0.309, 0.084, -0.286, 0.088, -0.263, 0.095, -0.241, 0.104, -0.220, 0.113, -0.199, 0.127, -0.180, 0.142, -0.163, 0.158, -0.147, 0.175, -0.131, 0.194, -0.117, 0.214, -0.107, 0.236, -0.098, 0.258, -0.091, 0.280, -0.086, 0.303, -0.085, 0.326, -0.087, 0.349, -0.092, 0.370, -0.100, 0.391, -0.111, 0.410, -0.124, 0.426, -0.139, 0.441, -0.157, 0.454, -0.176, 0.464, -0.197, 0.471, -0.219, 0.474, -0.242, 0.474, -0.265, 0.470, -0.288, 0.463, -0.309, 0.453, -0.330, 0.442, -0.350, 0.427, -0.368, 0.409, -0.382, 0.389, -0.393, 0.368, -0.402, 0.345, -0.407, 0.322, -0.407, 0.299, -0.404, 0.278, -0.394, 0.261, -0.379, 0.246, -0.362, 0.236, -0.341, 0.233, -0.318, 0.234, -0.295, 0.242, -0.274, 0.256, -0.256, 0.276, -0.244, 0.299, -0.241, 0.319, -0.251, 0.324, -0.273, 0.317, -0.295, 0.316, -0.318, 0.332, -0.334, 0.355, -0.335, 0.375, -0.325, 0.390, -0.308, 0.398, -0.286, 0.399, -0.263, 0.397, -0.240, 0.389, -0.219, 0.375, -0.201, 0.357, -0.186, 0.337, -0.176, 0.315, -0.169, 0.292, -0.167, 0.269, -0.169, 0.247, -0.175, 0.226, -0.185, 0.207, -0.198, 0.191, -0.215, 0.178, -0.234, 0.169, -0.255, 0.163, -0.277, 0.161, -0.300, 0.161, -0.323, 0.163, -0.346, 0.170, -0.368, 0.179, -0.389, 0.191, -0.408, 0.206, -0.427, 0.222, -0.443, 0.241, -0.456, 0.261, -0.467, 0.283, -0.475, 0.305, -0.479, 0.328, -0.481, 0.351, -0.480, 0.374, -0.478, 0.397, -0.473, 0.418, -0.464, 0.438, -0.453, 0.457, -0.440, 0.475, -0.425, 0.492, -0.409, 0.506, -0.391, 0.517, -0.371, 0.529, -0.351, 0.537, -0.330, 0.542, -0.307, 0.547, -0.285, 0.549, -0.262, 0.549, -0.239, 0.546, -0.216, 0.541, -0.193, 0.535, -0.171, 0.526, -0.150, 0.514, -0.130, 0.501, -0.111, 0.486, -0.094, 0.469, -0.077, 0.452, -0.063, 0.433, -0.050, 0.412, -0.040, 0.391, -0.030, 0.369, -0.023, 0.346, -0.019, 0.324, -0.015, 0.301, -0.014, 0.278, -0.015, 0.255, -0.018, 0.232, -0.021, 0.210, -0.027, 0.189, -0.037, 0.168, -0.047, 0.148, -0.058, 0.130, -0.072, 0.113, -0.088, 0.097, -0.104, 0.082, -0.122, 0.067, -0.140, 0.054, -0.159, 0.044, -0.179, 0.033, -0.200, 0.025, -0.221, 0.018, -0.243, 0.013, -0.266, 0.011, -0.289, 0.010, -0.312],
        "smile": [-0.250, 0.355, -0.245, 0.338, -0.231, 0.326, -0.214, 0.324, -0.196, 0.327, -0.179, 0.335, -0.163, 0.341, -0.146, 0.348, -0.130, 0.357, -0.113, 0.363, -0.096, 0.369, -0.079, 0.374, -0.062, 0.379, -0.044, 0.381, -0.026, 0.383, -0.008, 0.384, 0.010, 0.384, 0.028, 0.384, 0.046, 0.383, 0.064, 0.381, 0.082, 0.377, 0.099, 0.372, 0.115, 0.365, 0.132, 0.359, 0.148, 0.351, 0.164, 0.342, 0.179, 0.333, 0.196, 0.325, 0.214, 0.323, 0.231, 0.326, 0.244, 0.339, 0.247, 0.357, 0.245, 0.375, 0.236, 0.390, 0.224, 0.404, 0.210, 0.415, 0.195, 0.426, 0.181, 0.436, 0.165, 0.445, 0.149, 0.453, 0.132, 0.459, 0.115, 0.466, 0.098, 0.471, 0.080, 0.474, 0.062, 0.478, 0.045, 0.480, 0.027, 0.481, 0.009, 0.481, -0.009, 0.481, -0.027, 0.480, -0.045, 0.477, -0.063, 0.475, -0.081, 0.472, -0.098, 0.466, -0.115, 0.461, -0.132, 0.455, -0.149, 0.449, -0.165, 0.441, -0.182, 0.434, -0.197, 0.424, -0.212, 0.414, -0.225, 0.402, -0.237, 0.389, -0.246, 0.373],
        "flat": [-0.172, 0.452, -0.170, 0.439, -0.167, 0.426, -0.162, 0.414, -0.153, 0.404, -0.141, 0.398, -0.128, 0.396, -0.115, 0.396, -0.102, 0.394, -0.089, 0.393, -0.076, 0.392, -0.063, 0.391, -0.050, 0.389, -0.037, 0.387, -0.024, 0.385, -0.011, 0.384, 0.002, 0.382, 0.015, 0.381, 0.028, 0.378, 0.041, 0.376, 0.054, 0.373, 0.067, 0.371, 0.080, 0.370, 0.093, 0.369, 0.106, 0.368, 0.120, 0.367, 0.133, 0.367, 0.146, 0.370, 0.156, 0.378, 0.163, 0.389, 0.168, 0.401, 0.171, 0.414, 0.171, 0.427, 0.170, 0.440, 0.166, 0.452, 0.160, 0.464, 0.152, 0.474, 0.141, 0.482, 0.129, 0.487, 0.116, 0.488, 0.103, 0.489, 0.090, 0.490, 0.076, 0.491, 0.063, 0.492, 0.050, 0.493, 0.037, 0.495, 0.024, 0.496, 0.011, 0.498, -0.002, 0.499, -0.015, 0.500, -0.028, 0.501, -0.041, 0.502, -0.054, 0.504, -0.067, 0.506, -0.080, 0.508, -0.093, 0.510, -0.106, 0.512, -0.119, 0.514, -0.132, 0.514, -0.145, 0.509, -0.154, 0.500, -0.163, 0.490, -0.168, 0.478, -0.171, 0.465],
        "qHook": [1.377, -1.555, 1.384, -1.588, 1.400, -1.618, 1.422, -1.644, 1.447, -1.666, 1.476, -1.684, 1.509, -1.694, 1.542, -1.701, 1.575, -1.706, 1.609, -1.712, 1.642, -1.719, 1.672, -1.734, 1.698, -1.756, 1.714, -1.786, 1.719, -1.819, 1.712, -1.853, 1.697, -1.883, 1.672, -1.906, 1.642, -1.921, 1.609, -1.927, 1.575, -1.922, 1.547, -1.903, 1.524, -1.878, 1.502, -1.853, 1.470, -1.840, 1.439, -1.853, 1.422, -1.882, 1.423, -1.916, 1.433, -1.948, 1.454, -1.975, 1.480, -1.997, 1.508, -2.016, 1.539, -2.029, 1.572, -2.037, 1.606, -2.039, 1.640, -2.038, 1.674, -2.032, 1.705, -2.019, 1.734, -2.002, 1.761, -1.981, 1.786, -1.958, 1.807, -1.932, 1.823, -1.902, 1.834, -1.870, 1.840, -1.836, 1.840, -1.802, 1.835, -1.769, 1.825, -1.736, 1.810, -1.706, 1.792, -1.677, 1.768, -1.654, 1.741, -1.633, 1.711, -1.617, 1.679, -1.605, 1.647, -1.595, 1.613, -1.589, 1.580, -1.583, 1.547, -1.578, 1.515, -1.564, 1.493, -1.539, 1.472, -1.512, 1.443, -1.495, 1.410, -1.499, 1.385, -1.522],
        "qDot": [1.281, -1.348, 1.282, -1.366, 1.288, -1.383, 1.297, -1.399, 1.309, -1.412, 1.324, -1.422, 1.341, -1.428, 1.359, -1.430, 1.376, -1.426, 1.392, -1.417, 1.405, -1.404, 1.414, -1.389, 1.419, -1.371, 1.419, -1.353, 1.415, -1.336, 1.405, -1.321, 1.393, -1.307, 1.378, -1.297, 1.361, -1.292, 1.343, -1.292, 1.325, -1.295, 1.309, -1.303, 1.296, -1.316, 1.286, -1.331],
        "dotC": [-0.119, 0.447, -0.118, 0.435, -0.117, 0.423, -0.113, 0.412, -0.108, 0.401, -0.104, 0.390, -0.097, 0.380, -0.091, 0.370, -0.083, 0.362, -0.073, 0.355, -0.063, 0.348, -0.054, 0.341, -0.043, 0.336, -0.032, 0.333, -0.020, 0.330, -0.008, 0.329, 0.004, 0.329, 0.015, 0.329, 0.027, 0.331, 0.039, 0.333, 0.050, 0.337, 0.060, 0.344, 0.069, 0.352, 0.079, 0.358, 0.088, 0.366, 0.095, 0.375, 0.101, 0.385, 0.106, 0.396, 0.111, 0.407, 0.114, 0.418, 0.117, 0.429, 0.118, 0.441, 0.119, 0.453, 0.118, 0.465, 0.116, 0.477, 0.112, 0.488, 0.107, 0.498, 0.103, 0.509, 0.096, 0.519, 0.090, 0.529, 0.083, 0.539, 0.073, 0.546, 0.063, 0.552, 0.053, 0.558, 0.042, 0.563, 0.031, 0.568, 0.020, 0.572, 0.008, 0.573, -0.003, 0.573, -0.015, 0.572, -0.027, 0.570, -0.038, 0.565, -0.049, 0.561, -0.059, 0.555, -0.069, 0.549, -0.080, 0.543, -0.088, 0.535, -0.094, 0.525, -0.100, 0.514, -0.105, 0.504, -0.110, 0.493, -0.115, 0.482, -0.117, 0.470, -0.118, 0.459],
        "Dtalk": [-0.364, 0.387, -0.357, 0.359, -0.339, 0.336, -0.314, 0.323, -0.286, 0.317, -0.257, 0.318, -0.229, 0.322, -0.201, 0.330, -0.174, 0.338, -0.146, 0.346, -0.118, 0.351, -0.090, 0.356, -0.061, 0.361, -0.033, 0.362, -0.004, 0.362, 0.024, 0.362, 0.053, 0.360, 0.081, 0.353, 0.109, 0.349, 0.137, 0.343, 0.164, 0.334, 0.191, 0.325, 0.219, 0.316, 0.247, 0.310, 0.276, 0.310, 0.304, 0.314, 0.328, 0.330, 0.345, 0.353, 0.352, 0.381, 0.351, 0.409, 0.346, 0.438, 0.337, 0.465, 0.325, 0.491, 0.310, 0.516, 0.295, 0.540, 0.278, 0.562, 0.258, 0.583, 0.237, 0.603, 0.214, 0.619, 0.190, 0.635, 0.165, 0.650, 0.139, 0.662, 0.112, 0.671, 0.084, 0.678, 0.056, 0.684, 0.028, 0.687, -0.001, 0.686, -0.029, 0.685, -0.057, 0.679, -0.086, 0.675, -0.114, 0.668, -0.140, 0.658, -0.167, 0.647, -0.192, 0.633, -0.216, 0.618, -0.240, 0.602, -0.262, 0.584, -0.283, 0.564, -0.302, 0.543, -0.319, 0.520, -0.334, 0.496, -0.347, 0.470, -0.357, 0.443, -0.363, 0.415],
    ]
    private static let glyphs: [String: [P2]] = raw.mapValues { v in stride(from: 0, to: v.count - 1, by: 2).map { P2(v[$0], v[$0 + 1]) } }
    static func glyph(_ n: String) -> [P2] { glyphs[n] ?? glyphs["smile"]! }
}
