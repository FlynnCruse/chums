import SwiftUI

/// Squint: only a face, drawn in white marker strokes on the black, like a kaomoji. Two eyes, a mouth and two brows,
/// each one stroke that changes shape (a dash, a ring, a chevron, an arc, an open D) and blends from one shape into
/// the next. Each part hangs on its own spring, so a shake rattles them and they settle back one by one.
///   idle: │ │ ‿, now and then another face for a moment · listening: ○ ○, a mouth that opens with your voice ·
///   thinking: ─ ○ ~ tilted · working: ─ ─ ─, eyes reading across · subagents: small faces around it · speaking: its
///   mouth with its voice · done: > < D and a hop, then ◠ ◠ ‿ · needs you: pleading brows, a knock · blocked: angry brows,
///   a zigzag mouth · dizzy: spirals · sleep: ◡ ◡ and a small breathing o, z's
///   tap: on an eye it squeezes that one shut (the other goes wide), on its mouth it giggles, anywhere else a wink ·
///   poke it often: −_− and a shake of the head · your finger near: o o, curious, it follows · dragged fast: > < ·
///   stroked: ◠ ◠ and a pink chalk blush · crown: picks its face (kept, and shown whenever it's idle) · shake: its
///   parts rattle, O O; shaken hard it's dizzy
/// It blinks by squashing its eyes shut and open (never by turning them into another shape). A part changes into a
/// shape of its own kind by bending into it (a line into an arc); into another kind (a line into a ring) it squashes
/// away and pops back as the new one. Idle, it breathes and its parts drift a hair.
final class SquintStage: Staged {
    static let shared = SquintStage()
    /// Each part's spring back to its place, in turns a second: left eye, right eye, mouth, left brow, right brow.
    static let partSprings: [Double] = [3.6, 3.4, 2.6, 3.0, 2.9]

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 2.6, .dizzy: 3.4]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { false }
    var calm: Bool { t - busyAt > 1.2 }

    // MARK: glyphs (points in pt, centred on the part)

    static let M = 32
    private static func g(_ pts: [P2]) -> [P2] { Strokes.resample(pts, M) }
    private static let glyphs: [String: [P2]] = {
        var d: [String: [P2]] = [:]

        d["none"] = [P2](repeating: .zero, count: M)
        d["vdash"] = g([P2(-1.5, -14), P2(1.5, 14)])
        d["slant"] = g([P2(-4, -12), P2(3, 12)])                                // ツ's strokes
        d["hdash"] = g([P2(-13, 0), P2(13, 0)])
        d["ring"] = g(Strokes.arc(.zero, 15, -Double.pi / 2, Double.pi * 1.55))
        d["bigring"] = g(Strokes.arc(.zero, 18, -Double.pi / 2, Double.pi * 1.55))
        d["happy"] = g(Strokes.arc(P2(0, 9), 13, Double.pi * 1.12, Double.pi * 1.88))       // ◠
        d["shut"] = g(Strokes.arc(P2(0, -7), 13, Double.pi * 0.12, Double.pi * 0.88))       // ◡
        d["chev"] = g([P2(-9, -11), P2(8, 0), P2(-9, 11)])                       // > (the right eye is mirrored: <)
        d["spiral"] = g((0...90).map { i in let u = Double(i) / 90, a = u * 1.7 * Double.pi * 2; return P2(cos(a), sin(a)) * (2 + u * 17) })
        d["dot"] = g(Strokes.arc(.zero, 5, 0, Double.pi * 2.1))
        // mouths
        d["smile"] = g(Strokes.arc(P2(0, -24), 30, Double.pi * 0.33, Double.pi * 0.67))
        d["bigsmile"] = g(Strokes.arc(P2(0, -30), 40, Double.pi * 0.27, Double.pi * 0.73))
        d["flat"] = g([P2(-15, 0), P2(15, 0)])
        d["short"] = g([P2(-8, 0), P2(8, 0)])
        d["o"] = g(Strokes.arc(.zero, 9, -Double.pi / 2, Double.pi * 1.55))
        d["O"] = g(Strokes.arc(.zero, 16, -Double.pi / 2, Double.pi * 1.55, rx: 12))
        d["D"] = g([P2(-24, -9), P2(24, -9)] + Strokes.arc(P2(0, -9), 24, 0, Double.pi) + [P2(-24, -9.5)])
        d["frown"] = g(Strokes.arc(P2(0, 26), 28, Double.pi * 1.32, Double.pi * 1.68))
        d["wave"] = g((0...60).map { i in let x = -19 + 38 * Double(i) / 60; return P2(x, 4.5 * sin(x / 38 * Double.pi * 3)) })
        d["zig"] = g([P2(-20, 2), P2(-12, -4), P2(-4, 3), P2(4, -4), P2(12, 3), P2(20, -3)])
        d["tsu"] = g(Strokes.arc(P2(-22, -26), 42, Double.pi * 0.08, Double.pi * 0.46))     // ツ's long curve
        // brows (left; the right one is mirrored)
        d["brow"] = g([P2(-12, 0), P2(12, 0)])
        d["angry"] = g([P2(-12, -6), P2(12, 6)])
        d["worried"] = g([P2(-12, 6), P2(12, -6)])
        d["up"] = g(Strokes.arc(P2(0, 10), 15, Double.pi * 1.2, Double.pi * 1.8))
        return d
    }()

    /// Kinds of shape: within a kind one bends into the other point by point; across kinds the part swaps.
    private enum Fam { case none, v, h, loop, chev, spiral, talk }
    private static func fam(_ name: String) -> Fam {
        switch name {
        case "none": return .none
        case "vdash", "slant": return .v
        case "ring", "bigring", "o", "O", "dot": return .loop
        case "chev": return .chev
        case "spiral": return .spiral
        case "D": return .talk
        default: return .h
        }
    }
    /// Its mouth talking, `v` open (0 shut … 1 wide): a top edge, then its lower lip swinging down and back, like the D.
    private static func talk(_ v: Double) -> [P2] {
        let W = 17 + 5 * v, d = 2.5 + 21 * v, y0 = -d * 0.2
        var p: [P2] = (0...10).map { i in P2(-W + 2 * W * Double(i) / 10, y0) }
        p += (1...22).map { i in let a = Double.pi * Double(i) / 22; return P2(W * cos(a), y0 + d * sin(a)) }
        return Strokes.resample(p, M)
    }

    // MARK: faces

    struct Face {
        var le = "vdash", re: String? = nil, mouth = "smile", lb = "none", rb: String? = nil
        var eyeY = 0.0, mouthY = 0.0, browY = 0.0, gap = 0.0, tilt = 0.0, scale = 1.0
    }
    private func face(_ s: ChumsState) -> Face {
        switch s {
        case .idle: return Face()
        case .listening: return Face(le: "ring", mouth: "o", lb: "up", browY: -2, scale: 1.04)
        case .thinking: return Face(le: "hdash", re: "ring", mouth: "wave", lb: "none", rb: "up", mouthY: 2, tilt: -0.12)
        case .working: return Face(le: "hdash", mouth: "short", eyeY: 4, mouthY: -2)
        case .subagents: return Face(le: "vdash", mouth: "smile", scale: 0.82)
        case .speaking: return Face(le: "vdash", mouth: "flat")
        case .done: return Face(le: "chev", mouth: "D", eyeY: -2)
        case .needs: return Face(le: "vdash", mouth: "frown", lb: "worried", browY: 2, scale: 1.06)
        case .approval: return Face(le: "ring", mouth: "o", scale: 0.5)
        case .blocked: return Face(le: "vdash", mouth: "zig", lb: "angry", browY: 6)
        case .dizzy: return Face(le: "spiral", mouth: "wave")
        case .sleep: return Face(le: "shut", mouth: "o", eyeY: 6, mouthY: 2, scale: 0.94)
        }
    }
    /// What the crown flips through.
    private static let deck: [Face] = [
        Face(), Face(le: "happy", mouth: "bigsmile"), Face(le: "chev", mouth: "D", eyeY: -2),
        Face(le: "vdash", re: "happy", mouth: "D"), Face(le: "bigring", mouth: "O", lb: "up", browY: -6),
        Face(le: "vdash", mouth: "frown", lb: "worried", browY: 2), Face(le: "vdash", mouth: "zig", lb: "angry", browY: 6),
        Face(le: "hdash", re: "ring", mouth: "flat", rb: "up"), Face(le: "slant", mouth: "tsu", mouthY: -4),
        Face(le: "hdash", mouth: "dot", mouthY: 4), Face(le: "shut", mouth: "o", eyeY: 6),
    ]
    /// Now and then, idle, it pulls one of these for a moment.
    private static let fidgets: [Face] = [
        Face(le: "hdash", re: "ring", mouth: "flat", rb: "up"), Face(le: "happy", mouth: "smile"),
        Face(le: "slant", mouth: "tsu", mouthY: -4), Face(le: "shut", mouth: "o", eyeY: 6),
    ]

    // MARK: the parts

    private struct Part {
        var from: [P2], to: [P2], b = 1.0, bv = 0.0          // shape: from → to on a spring
        var fam: Fam
        var pending: [P2]? = nil, pendingFam = Fam.none      // a shape of another kind it is swapping to
        var sc = 1.0, scv = 0.0                              // its size in a swap: squashing away, popping back
        var off = P2.zero, v = P2.zero                       // its own spring off its place
        var shape: [P2] { Strokes.mix(from, to, b) }
        mutating func set(_ g: [P2], _ f: Fam) {
            func same(_ a: [P2], _ c: [P2]) -> Bool { zip(a, c).allSatisfy { simd_length($0 - $1) < 0.01 } }
            if let p = pending { if !same(p, g) { pending = g; pendingFam = f }; return }
            if same(to, g) { return }
            if f == fam || f == .none || fam == .none { from = shape; to = g; b = 0; bv = 0; fam = f } else { pending = g; pendingFam = f }
        }
    }
    private var parts: [Part] = (0..<5).map { i in
        let g = SquintStage.glyphs[i < 3 ? (i < 2 ? "vdash" : "smile") : "none"]!
        return Part(from: g, to: g, fam: i < 2 ? .v : i == 2 ? .h : .none)
    }
    private enum Slot: Int { case le, re, mouth, lb, rb }
    private var cur = Face()                                  // layout, eased toward the face's
    private var shown = Face()                                 // the face on screen (state, a fidget, the crown, a wink)
    private var state: ChumsState = .idle
    private var t = 0.0, busyAt = 0.0

    private var center = P2(99, 122), cv = P2.zero            // the face, on a spring (a finger drags it)
    private var hop = (y: 0.0, v: 0.0)
    private var finger: CGPoint?, lookFor = 0.0, look = P2.zero
    private var wink = 0.0, annoyed = 0.0, pokes: [Double] = []
    private var reaction: (face: Face, until: Double)?       // a tap's face, for a moment
    private var touchT = 0.0
    private var touchAt: CGPoint?, lastDrag: (p: CGPoint, t: Double)?, fingerSpeed = 0.0
    private var petFor = 0.0, blush = 0.0, energy = 0.0
    private var wob = (a: 0.0, v: 0.0)                        // a little rock of the head (each crown click)
    /// The face the crown picked (0: its own), kept between launches.
    private var chosen = UserDefaults.standard.integer(forKey: "squintFace")
    private var crownPos = 0.0, crownIdle = 9.0
    private var fidget: (face: Face, t: Double)?, nextFidget = 14.0
    private var knock = 0.0, shakeT = 0.0, trauma = 0.0
    private var minis = 0.0
    private var toolFlash = 0.0, nextTool = 0.8
    private var blinkT = -1.0, rigBlink = 0                  // its own blink (when the rig blinks): time into it
    private var mv = 0.0                                      // the voice, eased, for its mouth
    private struct Z { var x, y, t: Double }
    private var zs: [Z] = [], nextZ = 0.5

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        state = s; fidget = nil; nextFidget = rnd(12, 20)
        if s == .done { hop.v = -230; for i in 0..<5 { parts[i].v += P2(rnd(-30, 30), rnd(-60, -20)) } }
        if s == .needs { knock = 0 }
        busyAt = t
    }

    func step(_ r: Rig, _ dt0: Double) {
        let dt = min(dt0, 0.05)
        t += dt
        guard !r.ao else { return }
        crownIdle += dt; wink = max(0, wink - dt); annoyed = max(0, annoyed - dt); lookFor = max(0, lookFor - dt)
        trauma = max(0, trauma - dt * 0.75)
        // which face: a wink, annoyed, the crown's, a fidget, done's second beat, or the state's
        var f = face(state)
        let picked = Self.deck[((chosen % Self.deck.count) + Self.deck.count) % Self.deck.count]
        if state == .idle && chosen != 0 { f = picked }                                // the face the crown picked
        if state == .done && r.stateT > 1.1 { f = Face(le: "happy", mouth: "bigsmile") }
        if state == .idle && finger == nil && crownIdle > 3 && chosen == 0 {
            nextFidget -= dt
            if nextFidget <= 0 && fidget == nil { fidget = (Self.fidgets.randomElement()!, 0) }
            if var fd = fidget { fd.t += dt; fidget = fd.t > 1.8 ? nil : fd; if fd.t > 1.8 { nextFidget = rnd(12, 22) } }
            if let fd = fidget { f = fd.face }
        }
        if crownIdle < 2.4 { f = picked }                                              // (in another state, for a moment)
        // your finger: curious (o o) near it, > < dragged fast, ◠ ◠ and blushing stroked
        petFor = max(0, petFor - dt); fingerSpeed *= exp(-dt * 6)
        if finger != nil && (t - touchT > 0.25 || fingerSpeed > 40) { f = fingerSpeed > 260 ? Face(le: "chev", mouth: "D", eyeY: -2) : Face(le: "ring", mouth: "o", lb: "up", browY: -3, scale: 1.04) }
        if petFor > 0 { f = Face(le: "happy", mouth: "bigsmile") }
        blush += ((petFor > 0 || (reaction?.face.mouth == "D" && reaction?.face.le == "happy") ? 1 : 0) - blush) * min(1, dt * 5)
        // shaken: O O while it rattles; hard, it's dizzy
        energy *= exp(-dt * 1.5)
        if trauma > 0.3 && state != .dizzy && state != .sleep { f = Face(le: "bigring", mouth: "O", lb: "up", browY: -6) }
        if let re = reaction { if t < re.until { f = re.face } else { reaction = nil } }
        if annoyed > 0 { f = Face(le: "hdash", mouth: "flat") }                       // −_−
        // working: each tool call, a glance up at it (o o) and back to reading
        nextTool -= dt; toolFlash = max(0, toolFlash - dt)
        if nextTool <= 0 && (!r.worlds.queue.isEmpty || state == .working), let c = r.worlds.nextEvent(r) {
            nextTool = r.worlds.queue.isEmpty ? rnd(1.6, 2.6) : 0.6
            if c.kind != .stop && state == .working { toolFlash = 0.5; for i in 0..<5 { parts[i].v += P2(0, -50) } }
        }
        if toolFlash > 0 && state == .working { f = Face(le: "ring", mouth: "o", lb: "up", browY: -2) }
        if wink > 0 { f = Face(le: "vdash", re: "happy", mouth: "D") }
        let ww = TAU * 2.6
        wob.v += (-ww * ww * wob.a - 2 * 0.3 * ww * wob.v) * dt; wob.a += wob.v * dt
        if annoyed > 2.0 { wob.a = sin((2.6 - annoyed) * 30) * 0.12 * (annoyed - 2.0) / 0.6 }   // a shake of the head
        shown = f
        // the shapes
        let G = Self.glyphs
        parts[0].set(G[f.le] ?? G["vdash"]!, Self.fam(f.le))
        parts[1].set(Strokes.mirrored(G[f.re ?? f.le] ?? G["vdash"]!), Self.fam(f.re ?? f.le))
        mv += (clamp(r.voice * 1.4, 0, 1) - mv) * min(1, dt * 16)
        if state == .speaking { parts[2].set(Self.talk(0), .talk) } else { parts[2].set(G[f.mouth] ?? G["smile"]!, Self.fam(f.mouth)) }
        parts[3].set(G[f.lb] ?? G["none"]!, Self.fam(f.lb))
        parts[4].set(Strokes.mirrored(G[f.rb ?? f.lb] ?? G["none"]!), Self.fam(f.rb ?? f.lb))
        // a blink: when the rig blinks, it squashes its eyes shut and open
        if r.blink.phase == 1 && rigBlink != 1 && blinkT < 0 { blinkT = 0 }
        rigBlink = r.blink.phase
        if blinkT >= 0 { blinkT += dt; if blinkT > 0.34 { blinkT = -1 } }
        // springs: the shapes blend (a hair of overshoot), each part settles on its own. In steps of at most 1/120 s:
        // stepped once per frame, the shape's spring (26 rad/s) is unstable past about 1/25 s a frame, and a run of slow
        // frames (or the offline renderer at 20 a second) made the eyes grow without end
        let steps = max(1, Int((dt * 120).rounded(.up))), frameDT: Double = dt
        if trauma > 0.05 { for i in 0..<5 { parts[i].v += P2(rnd(-1, 1), rnd(-1, 1)) * trauma * 900 * frameDT } }
        for _ in 0..<steps {
            let dt = frameDT / Double(steps)
            for i in 0..<5 {
                let w = TAU * 4.2
                parts[i].bv += (-w * w * (parts[i].b - 1) - 2 * 0.62 * w * parts[i].bv) * dt
                parts[i].b += parts[i].bv * dt
                // a swap: it squashes away, faster and faster, becomes the new shape, and pops back a little past full size
                if let g = parts[i].pending {
                    parts[i].scv = min(parts[i].scv, 0) - 190 * dt; parts[i].sc += parts[i].scv * dt
                    if parts[i].sc <= 0.04 {
                        parts[i].from = g; parts[i].to = g; parts[i].b = 1; parts[i].bv = 0
                        parts[i].fam = parts[i].pendingFam; parts[i].pending = nil; parts[i].sc = 0.04; parts[i].scv = 0
                    }
                } else {
                    let ws = TAU * 3.1
                    parts[i].scv += (-ws * ws * (parts[i].sc - 1) - 2 * 0.48 * ws * parts[i].scv) * dt
                    parts[i].sc += parts[i].scv * dt
                }
                // in parts, with their types: whole, this was more than Xcode 26.6's type checker would take
                let k: Double = TAU * Self.partSprings[i]
                let pull: P2 = parts[i].off * (-k * k), damping: P2 = parts[i].v * (2 * 0.32 * k)
                parts[i].v += (pull - damping) * dt
                parts[i].off += parts[i].v * dt
            }
        }
        // layout eases toward the face's
        let e = min(1, dt * 9)
        cur.eyeY += (f.eyeY - cur.eyeY) * e; cur.mouthY += (f.mouthY - cur.mouthY) * e; cur.browY += (f.browY - cur.browY) * e
        cur.tilt += (f.tilt - cur.tilt) * e; cur.scale += (f.scale - cur.scale) * e
        // the face's place: home, a finger pulling it, a hop
        var home = P2(99, state == .approval ? 70 : state == .sleep ? 132 : 122)
        if let fp = finger { home += P2(clamp((fp.x - 99) * 0.35, -34, 34), clamp((fp.y - 122) * 0.3, -30, 30)) }
        if state == .dizzy { home += P2(cos(t * 3.4), sin(t * 3.4)) * 9 }
        let wc = TAU * 2.2
        let pull: P2 = (home - center) * (wc * wc), damp: P2 = cv * (wc * 1.0)
        cv += (pull - damp) * dt; center += cv * dt
        let trail: [Double] = [5, 5, 8, 6, 6]
        if finger != nil { for i in 0..<5 { parts[i].v -= cv * (dt * trail[i]) } }   // they trail behind
        hop.v += 1100 * dt; hop.y += hop.v * dt; if hop.y > 0 { hop.y = 0; hop.v = 0 }
        // needs you: a knock every few seconds
        if state == .needs {
            let was = knock; knock += dt; if knock >= 3.2 { knock = 0 }
            if was < 0.2 && knock >= 0.2 { hop.v = -120; r.onHaptic?(.strong); for i in 0..<5 { parts[i].v += P2(0, 60) } }
        }
        // blocked: a shake of the head now and then
        shakeT = state == .blocked ? shakeT + dt : 0
        minis += ((state == .subagents ? 1 : 0) - minis) * min(1, dt * 3)
        // asleep: z's float up
        if state == .sleep {
            nextZ -= dt; if nextZ <= 0 { nextZ = 1.6; zs.append(Z(x: center.x + 34, y: center.y - 30, t: 0)) }
        }
        for i in zs.indices { zs[i].t += dt * (state == .sleep ? 1 : 4); zs[i].y -= 14 * dt; zs[i].x += 5 * dt }   // awake, they clear fast
        zs.removeAll { $0.t > 2.6 }
        let moving = abs(wob.v) > 0.05 || blush > 0.02 && blush < 0.98 || parts.contains { abs($0.bv) > 0.05 || simd_length($0.v) > 3 || $0.pending != nil || abs($0.scv) > 0.05 } || blinkT >= 0 || simd_length(cv) > 3 || finger != nil || hop.v != 0
            || state == .speaking || state == .listening || state == .dizzy || minis > 0.02 || !zs.isEmpty
        if moving { busyAt = t }
    }

    // MARK: input

    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        let e = max(0, sqrt(ax * ax + ay * ay + az * az) - 0.9)
        trauma = min(1, trauma + e * e * 0.03)
        energy += e * e * 0.05
        if energy > 0.4 && state != .dizzy && state != .sleep { energy = 0; r.onHaptic?(.strong); r.setState(.dizzy) }
        if e > 0 { busyAt = t }
    }
    /// The crown picks its face: each click the next one (round and round), kept.
    func crown(_ r: Rig, _ delta: Double) {
        let was = Int(floor(crownPos + 0.5))
        crownPos += delta * 0.45
        let now = Int(floor(crownPos + 0.5))
        if now != was {
            chosen = ((now % Self.deck.count) + Self.deck.count) % Self.deck.count
            UserDefaults.standard.set(chosen, forKey: "squintFace")
            r.onHaptic?(.click)
            wob.v += (delta > 0 ? 1 : -1) * 2.4
            for i in 0..<5 { parts[i].v += P2(0, delta > 0 ? -40 : 40) }
        }
        crownIdle = 0; fidget = nil; reaction = nil; busyAt = t
    }
    func touched(_ r: Rig, at pt: CGPoint) { finger = pt; touchAt = pt; touchT = t; lastDrag = (pt, t); busyAt = t }
    func dragged(_ r: Rig, at pt: CGPoint) {
        if let l = lastDrag, t - l.t > 0.005 {
            let v = hypot(Double(pt.x - l.p.x), Double(pt.y - l.p.y)) / (t - l.t)
            fingerSpeed = max(fingerSpeed * 0.7, v)
        }
        lastDrag = (pt, t); finger = pt; busyAt = t
    }
    func released(_ r: Rig) { finger = nil; lastDrag = nil }
    /// A tap: where it lands decides. On an eye, that eye squeezes shut and the other goes wide; on the mouth, a giggle;
    /// anywhere else, a wink. Four in a row: −_−.
    func poke(_ r: Rig) {
        pokes = pokes.filter { t - $0 < 3 } + [t]
        busyAt = t
        if pokes.count >= 4 { pokes = []; annoyed = 2.6; wink = 0; reaction = nil; return }
        guard annoyed <= 0 else { return }
        let s = 1.28 * cur.scale, at = touchAt.map { P2($0.x, $0.y) } ?? center
        let eyeL = center + P2(-31, -16 + cur.eyeY) * s, eyeR = center + P2(31, -16 + cur.eyeY) * s, mouth = center + P2(0, 24 + cur.mouthY) * s
        if simd_length(at - eyeL) < 24 || simd_length(at - eyeR) < 24 {
            let left = simd_length(at - eyeL) < simd_length(at - eyeR)
            reaction = (Face(le: left ? "chev" : "bigring", re: left ? "bigring" : "chev", mouth: "o", lb: left ? "angry" : "up", rb: left ? "up" : "angry"), t + 0.95)
            parts[left ? 0 : 1].v += P2(left ? -40 : 40, 30); hop.v = -70
        } else if simd_length(at - mouth) < 28 {
            reaction = (Face(le: "happy", mouth: "D", eyeY: -2), t + 1.1); hop.v = -150
        } else {
            wink = 0.75; hop.v = -110
        }
    }
    /// Stroked across: ◠ ◠, a big smile and a blush, while you keep stroking.
    func pet(_ r: Rig) { petFor = 0.5; busyAt = t }
    func deny(_ r: Rig) {}
    func hit(_ pt: CGPoint) -> Bool { abs(Double(pt.x) - center.x) < 70 && abs(Double(pt.y) - center.y) < 60 }

    // MARK: drawing

    /// How open its eyes are in a blink: shut fast (faster and faster), a beat closed, open a hair past and back.
    private var lid: Double {
        guard blinkT >= 0 else { return 1 }
        if blinkT < 0.075 { let u = blinkT / 0.075; return 1 - 0.93 * u * u }
        if blinkT < 0.115 { return 0.07 }
        let u = min(1, (blinkT - 0.115) / 0.21), c = 1.3
        return 0.07 + 0.93 * (1 + (c + 1) * pow(u - 1, 3) + c * pow(u - 1, 2))
    }

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        // dimmed (always on): the whole face at half brightness as one layer. Faded stroke by stroke, the places where
        // the chalk's strips overlap came out brighter than the rest (half on half).
        if r.ao { var c = ctx; c.opacity = 0.5; c.drawLayer { l in self.paint(r, l) } } else { paint(r, ctx) }
    }

    private func paint(_ r: Rig, _ ctx: GraphicsContext) {
        let p = r.pose(raw: true)
        var g = ctx
        // it breathes: slower and deeper asleep
        let breath = state == .sleep ? sin(t * TAU / 5.5) * 1.8 : sin(t * TAU / 4.4)
        let s = 1.28 * cur.scale * (1 + 0.012 * breath) * (state == .needs ? 1 + 0.05 * max(0, 1 - knock / 0.4) : 1)
        let headShake = state == .blocked ? sin(shakeT * 22) * 6 * max(0, 1 - (shakeT.truncatingRemainder(dividingBy: 2.6)) / 0.5) : 0
        g.translateBy(x: center.x + headShake, y: center.y + hop.y + 0.9 * breath)
        g.rotate(by: .radians(cur.tilt + wob.a + (state == .dizzy ? sin(t * 2.6) * 0.14 : 0)))
        g.scaleBy(x: s, y: s)
        // where they look: the rig's gaze, or your finger
        var gx = p.eye.gx, gy = p.eye.gy
        if let fp = finger { let d = P2(fp.x, fp.y) - center; let l = max(1, simd_length(d)); gx = d.x / l * min(1, l / 40); gy = d.y / l * min(1, l / 40) }
        if state == .working { gx = sin(t * 2.2) * 0.9; gy = 0.2 }
        let look = P2(gx * 6, gy * 4)
        let gap = 31.0
        let places: [P2] = [P2(-gap, -16 + cur.eyeY) + look, P2(gap, -16 + cur.eyeY) + look,
                            P2(0, 24 + cur.mouthY) + look * 0.4,
                            P2(-gap, -44 + cur.browY) + look * 0.5, P2(gap, -44 + cur.browY) + look * 0.5]
        let widths = [8.0, 8.0, 8.0, 7.0, 7.0]
        let l = lid
        for i in 0..<5 {
            var pts = parts[i].shape
            // the mouth with a voice: talking, it opens and shuts; listening, its o grows with yours; asleep, it breathes
            var live = 1.0
            if i == 2 && parts[i].pending == nil {
                if state == .speaking && parts[i].fam == .talk { pts = Strokes.mix(pts, Self.talk(mv), min(1, parts[i].b)) }
                if state == .listening && parts[i].fam == .loop { live = 0.8 + 0.9 * mv }
                if state == .sleep && parts[i].fam == .loop { live = 0.75 + 0.35 * (0.5 + 0.5 * sin(t * TAU / 4)) }
            }
            if state == .dizzy && i < 2 {
                let a = t * 5 * (i == 0 ? 1 : -1); pts = pts.map { P2($0.x * cos(a) - $0.y * sin(a), $0.x * sin(a) + $0.y * cos(a)) }
            }
            // squashed: in a swap (narrower and flatter), in a blink (flatter, a little wider), about a point a bit low
            let sc = max(0, parts[i].sc)
            var sx = 0.3 + 0.7 * sc, sy = sc
            if i < 2 && (parts[i].fam == .v || parts[i].fam == .loop) { sy *= l; sx *= 1 + 0.14 * (1 - l) }
            sx *= live; sy *= live
            let ay = i < 2 ? 4.0 : 0
            // idle, each part drifts a hair on its own
            let drift = P2(sin(t * 0.63 + Double(i) * 1.9), cos(t * 0.47 + Double(i) * 2.7)) * 0.45
            let o = places[i] + parts[i].off + drift
            penPart(i, g.translated(o.x, o.y), pts, widths[i], sx, sy, ay)
        }
        // blushing: a few short pink chalk strokes under each eye
        if blush > 0.02 {
            let pink = Color(red: 1, green: 0.56, blue: 0.62), bg = g.faded(blush)
            for side in [-1.0, 1.0] {
                for k in 0..<3 {
                    let c = P2(side * 40 + (Double(k) - 1) * 5.5, 6 + cur.eyeY)
                    Chalk.draw(bg, [c + P2(-2, 3.5), c + P2(2, -3.5)], width: 2.8, seed: 40 + Double(k) + side * 5, color: pink)
                }
            }
        }
        // done: a few short strokes flying out from it, for a moment
        if state == .done, r.stateT < 0.9 {
            let k = r.stateT / 0.9
            for j in 0..<6 {
                let a = -Double.pi / 2 + (Double(j) - 2.5) * 0.42 + (j > 2 ? 0.6 : -0.6), r0 = 70 + 26 * k, r1 = r0 + 12
                pen(g.faded(1 - k), [P2(cos(a), sin(a)) * r0, P2(cos(a), sin(a)) * r1], 4.5, seed: Double(j))
            }
        }
        // subagents: small faces around it
        if minis > 0.02 {
            for k in 0..<3 {
                let a = t * 0.8 + Double(k) * TAU / 3, c = P2(cos(a) * 84, sin(a) * 66) * minis
                let m = g.faded(minis * (0.6 + 0.4 * (0.5 + 0.5 * sin(a))))
                for side in [-1.0, 1.0] { pen(m, [c + P2(side * 8, -10), c + P2(side * 8 + 0.6, -2)], 3.6, seed: Double(k) + side) }
                pen(m, Strokes.resample(Strokes.arc(c + P2(0, -6), 11, Double.pi * 0.35, Double.pi * 0.65), 12), 3.4, seed: Double(k) + 9)
            }
        }
        // z's
        for z in zs {
            let a = clamp(1 - z.t / 2.6, 0, 1) * clamp(z.t / 0.4, 0, 1), q = P2(z.x - center.x, z.y - center.y), sz = 6 + z.t * 2
            pen(ctx.faded(a).translated(center.x, center.y), [q + P2(-sz, -sz), q + P2(sz, -sz), q + P2(-sz, sz), q + P2(sz, sz)], 3.4, seed: z.x)
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}

    // MARK: the pen

    /// How its lines are drawn: "chalk" (a white paint marker dragged over a board: solid, pressing in, lifting off dry
    /// and split, chalk grain at its edges; see `Chalk`), "clean" (solid, smooth, round ends), or "marker" (the first
    /// version: a wobbling ribbon, cut flat). Set by the `squintLook` default (a launch argument: -squintLook clean).
    static let look = UserDefaults.standard.string(forKey: "squintLook") ?? "chalk"

    /// One stroke through `pts` (the shape, in its own place), each point then moved by `place` (squashed, put on the
    /// face). The pen keeps its width however the shape is squashed; a shape still growing from nothing starts thin.
    private func pen(_ g: GraphicsContext, _ pts: [P2], _ w0: Double, seed: Double, _ place: ((P2) -> P2)? = nil) {
        guard pts.count > 1 else { return }
        let len = Strokes.length(pts)
        guard len > 0.3 else { return }
        let w = w0 * clamp(len / (w0 * 1.2), 0.3, 1)
        let g = len < w0 * 1.5 ? g.faded(len / (w0 * 1.5)) : g        // growing from nothing (a brow coming), it fades in
        switch Self.look {
        case "marker": Strokes.marker(g, place.map { pts.map($0) } ?? pts, width: w, color: .white, seed: seed)
        case "clean":
            g.stroke(Self.smoothPath(place.map { pts.map($0) } ?? pts), with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        default: Chalk.draw(g, pts, width: w, seed: seed, squash: place)
        }
    }

    /// Each face part's stroke as last made, and what it was made from: it's made again only when the part's shape, squash
    /// or width changes (a blink, a swap, a new face), so a face holding still costs only its drawing.
    private var made: [(key: [Float], stroke: Chalk.Stroke)?] = Array(repeating: nil, count: 5)

    /// Part `i`'s stroke (its shape `pts`, squashed `sx`, `sy` about `ay`) into `g`, already moved to its place.
    private func penPart(_ i: Int, _ g: GraphicsContext, _ pts: [P2], _ w0: Double, _ sx: Double, _ sy: Double, _ ay: Double) {
        let squash: (P2) -> P2 = { q in P2(q.x * sx, ay + (q.y - ay) * sy) }
        guard Self.look != "marker" && Self.look != "clean" else { pen(g, pts, w0, seed: Double(i) * 3.1, squash); return }
        let len = Strokes.length(pts)
        guard pts.count > 1, len > 0.3 else { return }
        let w = w0 * clamp(len / (w0 * 1.2), 0.3, 1)
        var key = [Float](); key.reserveCapacity(pts.count * 2 + 3)
        for q in pts { key.append(Float((q.x * 50).rounded())); key.append(Float((q.y * 50).rounded())) }
        key += [Float((sx * 500).rounded()), Float((sy * 500).rounded()), Float((w * 50).rounded())]
        if made[i]?.key != key { made[i] = (key, Chalk.make(pts, width: w, seed: Double(i) * 3.1, squash: squash)) }
        made[i]!.stroke.draw(len < w0 * 1.5 ? g.faded(len / (w0 * 1.5)) : g)      // growing from nothing, it fades in
    }

    /// A smooth path through the points (closed if they meet).
    static func smoothPath(_ p: [P2]) -> Path {
        let closed = p.count > 3 && simd_length(p[0] - p[p.count - 1]) < 0.5
        return closed ? Strokes.smoothClosed(Array(p.dropLast())) : Strokes.smoothOpen(p)
    }
}

extension GraphicsContext {
    func translated(_ x: Double, _ y: Double) -> GraphicsContext { var c = self; c.translateBy(x: x, y: y); return c }
}
