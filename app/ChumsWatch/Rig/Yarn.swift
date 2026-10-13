import SwiftUI

/// Tangle's body: a real ball of yarn. One thread is wound round and round a ball (each turn drifting a little off the
/// last, so it covers the ball the way yarn does, the outer turns over the inner ones), and its end hangs off it.
/// The Digital Crown is the spool. Turned one way it reels the thread in: the end runs to the crown, the thread pays
/// out off the ball, which turns as it goes and gets smaller, all the way down to the last little knot. Turned back,
/// it feeds the thread out again and the ball winds it up. The thread between them hangs and sways on its own weight;
/// a finger on the ball spins it, a finger on the thread plucks it.
/// Everything is in points, round the ball's middle (y down, z toward you).
final class Yarn {
    typealias V3 = SIMD3<Double>

    // MARK: sizes

    /// The full ball's radius and the last knot's; the thread's width; how many turns it is wound.
    static let R0 = 54.0, Rmin = 8.0, width = 7.6, turns = 9.0
    /// Points per turn of the thread on the ball; points in the loose thread.
    static let M = 48, K = 30
    /// Where the spool is: just past the right edge, at the crown.
    static let spool = P2(206, 86)

    // MARK: the thread on the ball

    /// The whole thread wound on a ball of radius 1, from its inner end out: a curve on the sphere that turns a little
    /// off a great circle all the time (more, then less), so each turn crosses the last at a new angle.
    private static let wound: [V3] = {
        let n = Int(turns) * M + 1
        var e1 = V3(1, 0, 0)
        var out: [V3] = []
        for i in 0..<n {
            let u = Double(i) / Double(M)                                     // turns so far
            // each turn's plane tips round as it winds (its axis wandering over the ball), so the turns cross
            // (the axis visits every direction, so from no side do the turns all line up into a star)
            let lam = 1.15 * u + 0.3 * sin(u * 0.7), cz = 0.92 * sin(0.41 * u + 0.35)
            let a = V3(sqrt(1 - cz * cz) * cos(lam), cz, sqrt(1 - cz * cz) * sin(lam))
            e1 = simd_normalize(e1 - a * simd_dot(e1, a))
            let e2 = simd_cross(a, e1), th = TAU * u
            out.append(simd_normalize(e1 * cos(th) + e2 * sin(th)))
        }
        return out
    }()

    // MARK: state

    /// How much of it is reeled off: 0 all wound, 1 down to the last knot.
    private(set) var off = 0.0
    /// The ball's turn, and its spin (rad/s about each axis).
    private var q = simd_quatd(angle: 0.4, axis: simd_normalize(V3(1, 0.3, 0)))
    private var spin = V3.zero
    /// The loose thread: its points and where they were (it moves by Verlet steps).
    private var rope: [P2] = [], was: [P2] = []
    /// How firmly its end is on the spool (0: hanging loose, 1: on it); how slack it is (0 taut).
    private var onSpool = 0.0, slack = 0.08
    private var t = 0.0, reeling = 0.0, lastOff = 0.0
    private var grab: (i: Int, at: P2)?
    /// The thread swinging loose after a shake or a tug (how far each turn bulges off the ball).
    private var loose = 0.0, looseV = 0.0
    /// Where the ball's middle is on screen, how big it's drawn, set by its stage each frame.
    var center = P2(99, 128), scale = 1.0
    /// The face's size for the ball's: the knot keeps a readable face.
    var faceK: Double { 0.62 + 0.38 * radius / Self.R0 }
    var radius: Double { (Self.Rmin + (Self.R0 - Self.Rmin) * pow(max(0, 1 - off), 0.45)) * scale }
    /// Being reeled in or fed out right now.
    var busy: Bool { reeling > 0.05 || simd_length(spin) > 0.05 || grab != nil || abs(looseV) > 0.02 }
    var moving: Double { reeling }

    // MARK: input

    /// The crown: negative reels the thread in (off the ball), positive feeds it back. Returns true at each notch.
    @discardableResult func crown(_ delta: Double) -> Bool {
        let before = (off * 40).rounded(.down)
        off = clamp(off - delta * 0.025, 0, 1)                         // about 40 crown steps from ball to knot
        reeling = min(1, reeling + abs(delta) * 2)
        return (off * 40).rounded(.down) != before
    }
    /// A finger down at `p`: on the thread, it takes hold of it.
    func touch(_ p: P2) -> Bool {
        guard !rope.isEmpty else { return false }
        var best = -1, bd = 16.0
        for i in 2..<rope.count where simd_length(rope[i] - p) < bd { bd = simd_length(rope[i] - p); best = i }
        if best >= 0 { grab = (best, p); return true }
        return false
    }
    /// The finger moving: the thread it holds follows it; on the ball, it spins the ball.
    func drag(from a: P2, to b: P2) {
        if grab != nil { grab!.at = b; return }
        let d = b - a, r = max(20, radius)
        // a trackball: the ball rolls the way the finger goes
        spin += V3(d.y, -d.x, 0) / r * 9
    }
    func release() {
        grab = nil
    }
    /// Shaken or jolted: the thread swings, the turns come loose for a moment.
    func jolt(_ a: P2, hard: Double) {
        for i in rope.indices.dropFirst() { was[i] -= a * (0.00012 * Double(i) / Double(Self.K)) }   // a push to its speed
        looseV += hard * 1.2
        spin += V3(a.y, -a.x, 0) * 0.004
    }
    /// A tap on the ball: it gives and the loose turns bounce.
    func tap() { looseV += 1.4; spin += V3(rnd(-1, 1), rnd(-1, 1), 0) * 1.5 }

    // MARK: step

    func step(_ dt: Double, gravity: P2 = P2(0, 1)) {
        t += dt
        reeling *= exp(-dt * 3)
        let R = radius
        // the turns that came loose settle back (a spring)
        let wl = TAU * 2.2
        looseV += (-wl * wl * loose - 2 * 0.35 * wl * looseV) * dt; loose += looseV * dt
        // the end of the thread on the ball, in the ball's frame, and where it is now
        let endI = endIndex
        let endLocal = Self.wound[min(Self.wound.count - 1, Int(endI))] * layer(endI)
        // the ball turns so the thread leaves it toward where it goes: the spool, or hanging down when loose
        let toward: V3 = onSpool > 0.5 ? simd_normalize(V3(Self.spool.x - center.x, Self.spool.y - center.y, 0.35 * R)) : simd_normalize(V3(0.75, 0.6, 0.4))
        let v = simd_normalize(q.act(endLocal))
        let ax = simd_cross(v, toward), s = simd_length(ax)
        if s > 1e-4 {
            let ang = asin(min(1, s)) * min(1, dt * (grab == nil ? 5 : 1.5))
            q = simd_quatd(angle: ang, axis: ax / s) * q
        }
        // a spin from a finger, slowing down
        let sl = simd_length(spin)
        if sl > 1e-4 { q = simd_quatd(angle: sl * dt, axis: spin / sl) * q; spin *= exp(-dt * 2.2) }
        q = q.normalized
        // the loose thread: on the spool once some is reeled in, loose again when it's all wound back
        let want = off > 0.003 ? 1.0 : 0.0
        onSpool += (want - onSpool) * min(1, dt * (want > onSpool ? 5 : 1.6))
        // taut while it's reeled in, slack while it's fed out, a little sag when still
        let dOff = off - lastOff; lastOff = off
        let slackWant = dOff > 1e-5 ? 0.0 : dOff < -1e-5 ? 0.22 : 0.08
        slack += (slackWant - slack) * min(1, dt * 4)
        let a = center + project(q.act(endLocal)).p
        let tipFree = a + P2(14, 18)
        let tip = tipFree + (Self.spool - tipFree) * smooth01(onSpool)
        let span = simd_length(tip - a)
        let len = onSpool < 0.02 ? 26.0 : max(26 * (1 - onSpool), span * (1 + slack))
        if rope.isEmpty {
            rope = (0..<Self.K).map { (i: Int) -> P2 in a + (tipFree - a) * (Double(i) / Double(Self.K - 1)) }; was = rope
            // turned from the start so the thread leaves it where it should
            for _ in 0..<60 {
                let v = simd_normalize(q.act(endLocal)), ax = simd_cross(v, toward), s = simd_length(ax)
                if s > 1e-5 { q = simd_quatd(angle: asin(min(1, s)), axis: ax / s) * q }
            }
        }
        // Verlet: gravity, a little air, then the lengths and the ends held
        let g = gravity * 900.0
        for i in 1..<Self.K {
            let v = (rope[i] - was[i]) * 0.985
            was[i] = rope[i]; rope[i] += v + g * (dt * dt)
        }
        let seg = len / Double(Self.K - 1)
        for _ in 0..<14 {
            rope[0] = a
            if onSpool > 0.02 { rope[Self.K - 1] = rope[Self.K - 1] + (tip - rope[Self.K - 1]) * smooth01(onSpool) }
            if let gr = grab { rope[gr.i] = gr.at }
            for i in 0..<(Self.K - 1) {
                let d = rope[i + 1] - rope[i], l = max(1e-6, simd_length(d)), e = (l - seg) / l
                let wa = i == 0 ? 0.0 : 0.5, wb = (i + 1 == Self.K - 1 && onSpool > 0.5) ? 0.0 : 0.5
                let tot = max(1e-6, wa + wb)
                rope[i] += d * (e * wa / tot); rope[i + 1] -= d * (e * wb / tot)
            }
            for i in 1..<Self.K where rope[i].y > 236 { rope[i].y = 236 }   // the bottom of the screen
        }
    }

    // MARK: drawing

    /// The thread's last point on the ball (fractional index into `wound`).
    private var endIndex: Double { max(Double(Self.M) * 0.6, Double(Self.wound.count - 1) * (1 - off)) }
    /// How far out each part of the thread lies: the outer turns over the inner ones, each turn loose by a little.
    @inline(__always) private func layer(_ i: Double) -> Double {
        let r = radius, u = i / Double(Self.M)
        return r * (0.84 + 0.16 * u / Self.turns) * (1 + 0.025 * sin(u * 2.3 + t * 0.6) + loose * 0.06 * sin(u * 5.1 + t * 7))
    }
    @inline(__always) private func project(_ p: V3) -> (p: P2, z: Double) { (P2(p.x, p.y), p.z) }

    /// The ball and its thread: one flat colour, like the marker line it's drawn in (no outline).
    func draw(_ g: GraphicsContext, color: Color) {
        let w = Self.width * scale, n = Int(endIndex)
        var pts: [P2] = []
        pts.reserveCapacity(n + 1)
        for i in 0...n {
            let p = q.act(Self.wound[i] * layer(Double(i)))
            pts.append(center + P2(p.x, p.y))
        }
        let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        if !rope.isEmpty { g.stroke(Strokes.smoothOpen(rope), with: .color(color), style: style) }
        g.stroke(Strokes.smoothOpen(pts), with: .color(color), style: style)
    }

    @inline(__always) private func smooth01(_ u: Double) -> Double { let v = clamp(u, 0, 1); return v * v * (3 - 2 * v) }
}
