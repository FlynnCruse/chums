import SwiftUI

/// Noodle: a soft round tube, one width all along, its colour running from blue at the tail through purple and pink to a
/// yellow-orange head with two cream eyes (lit from the reference, design/characters/coil3d).
///
/// It is a real 3D tube, a noodle: 64 points a fixed distance apart. It has a library of shapes (the zigzag, a tornado
/// spiral, a tall spring, a sleep coil, a clump, a flat spiral, a lollipop, a slinky lying down, a knot), and changes
/// between them along paths baked offline as a rope that keeps its length, never bends tighter than it can and never
/// passes through itself (design/characters/coil3d/bakeall.py → noodle-shapes.bin). A change is a journey over one or
/// more of those paths, played by distance at a steady pace (one ease-in, one ease-out, the corners at the shapes
/// passed through rounded), so it never stalls on the way. On top, waves run along its body all the time as small
/// sideways ripples (in two directions), so it's never still, without ever swinging it round. A soft self-collision
/// keeps its parts apart, and after everything a bend limit keeps every joint rounder than the tube's own radius.
/// Spirals spin; everything sways a little.
///
/// It is drawn as the union of spheres along its curve, back to front, in thin tiles that between them cover exactly
/// that union (each disc's crescent beyond its nearer neighbour's disc; a disc nearer than both neighbours in strips),
/// each tile one fill with one gradient across whose colours are what is really seen on that tile: the frontmost
/// sphere there, its normal lit by a model fitted to the reference, darkened where another part of the tube is near
/// (in 3D) or passes just in front (on screen). So a stretch running toward you reads as one smooth surface, not a
/// stack of discs. The ends are rounded; the eyes sit on the head's end and are hidden by whatever is in front of
/// them. Prototyped against a per-pixel truth in design/characters/coil3d/crescents/.
/// Simulator measurements: NOODLE_DEBUG=1 prints the draw cost, NOODLE_DUMP=1 writes every frame's points.
///   idle: the zigzag, flowing, and every 20 s or so off into another shape for a while and back · listening: up on its
///   stick (the lollipop) · thinking: a flat spiral, turning slowly like a pinwheel · working: the tornado, turning,
///   rippling on each tool call · subagents: the tall spring · speaking: the zigzag, flowing with its voice · done: pops
///   up into the tall spring and spins · needs you: the lollipop, leaning in, knocking · blocked: winds up and ties
///   itself in a knot, straining · dizzy: a clump, spinning · sleep: curled up in a coil, barely moving
///   Every common change of state is one direct change of shape (no passing through others on the way).
///   crown: spins it (the zigzag winds up into the tornado; the flat spiral turns); spun fast it's dizzy · drag: it
///   leans toward your finger and looks at it · tap: a squeeze runs up it · shake: it bunches up and settles
final class NoodleStage: Staged {
    static let shared = NoodleStage()

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 3.6, .dizzy: 3.4]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { false }
    var calm: Bool { t - busyAt > 1.2 }

    typealias V3 = SIMD3<Double>
    typealias P3 = SIMD3<Double>
    static let N = 64
    static let R = NoodleRest.radius
    static let seg = NoodleRest.length / Double(N - 1)
    static let ground = 70.0
    static let cream = Color(red: 0.99, green: 0.915, blue: 0.83)

    // MARK: maths

    @inline(__always) static func unit(_ v: V3) -> V3 { let l = simd_length(v); return l > 1e-12 ? v / l : v }
    @inline(__always) static func rotate(_ v: V3, _ axis: V3, _ a: Double) -> V3 {
        let c = cos(a), s = sin(a)
        let p: V3 = v * c + simd_cross(axis, v) * s
        return p + axis * (simd_dot(axis, v) * (1 - c))
    }
    @inline(__always) static func ease(_ x: Double) -> Double { let v = clamp(x, 0, 1); return v * v * (3 - 2 * v) }

    /// A frame at each point that doesn't twist along the tube (rotation minimising, by double reflection), starting
    /// from `normal` when given (so it carries on smoothly from the last frame).
    static func frames(_ P: [V3], normal: V3?) -> (m1: [V3], m2: [V3]) {
        let n = P.count
        var t = [V3](repeating: .zero, count: n)
        for i in 0..<n { t[i] = unit(P[min(n - 1, i + 1)] - P[max(0, i - 1)]) }
        var m1 = [V3](repeating: .zero, count: n), m2 = m1
        var a: V3 = abs(t[0].z) < 0.9 ? V3(0, 0, 1) : V3(1, 0, 0)
        if let g = normal, simd_length(g - t[0] * simd_dot(g, t[0])) > 0.2 { a = g }
        m1[0] = unit(a - t[0] * simd_dot(a, t[0])); m2[0] = simd_cross(t[0], m1[0])
        for i in 0..<(n - 1) {
            let v1 = P[i + 1] - P[i], c1 = max(1e-12, simd_dot(v1, v1))
            let rL: V3 = m1[i] - v1 * (2 / c1 * simd_dot(v1, m1[i]))
            let tL: V3 = t[i] - v1 * (2 / c1 * simd_dot(v1, t[i]))
            let v2 = t[i + 1] - tL, c2 = simd_dot(v2, v2)
            m1[i + 1] = c2 > 1e-18 ? unit(rL - v2 * (2 / c2 * simd_dot(v2, rL))) : rL
            m2[i + 1] = simd_cross(t[i + 1], m1[i + 1])
        }
        return (m1, m2)
    }

    // MARK: the shape library

    enum Shape: Int, CaseIterable { case zigzag, tornado, spring, sleep, messy, shell, lolly, slinky, knot
        /// What it spins round: 1 the upright, 2 the line of sight (a pinwheel), 0 it doesn't.
        var axis: Int { switch self { case .tornado, .spring, .messy: return 1; case .shell: return 2; default: return 0 } }
    }
    struct Edge { let from: Int; let to: Int; let keys: [[V3]]; let secs: Double }   // secs: the bake's own pace, unused now
    static let library: (shapes: [[V3]], edges: [Edge]) = {
        guard let url = Bundle.main.url(forResource: "noodle-shapes", withExtension: "bin"), let d = try? Data(contentsOf: url), d.count > 16
        else { return ([[V3]](repeating: [V3](repeating: .zero, count: N), count: Shape.allCases.count), []) }
        var o = 4
        func i32() -> Int { let v = d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self) }; o += 4; return Int(v) }
        func f32() -> Double { let v = d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) }; o += 4; return Double(v) }
        func points(_ n: Int) -> [V3] { (0..<n).map { _ in let x = f32(), y = f32(), z = f32(); return V3(x, y, z) } }
        let ns = i32(), n = i32(), ne = i32()
        let shapes = (0..<ns).map { _ in points(n) }
        var edges: [Edge] = []
        for _ in 0..<ne {
            let a = i32(), b = i32(), k = i32(), secs = f32()
            edges.append(Edge(from: a, to: b, keys: (0..<k).map { _ in points(n) }, secs: secs))
        }
        return (shapes, edges)
    }()

    /// One edge of the graph, one way or the other.
    struct Leg { var edge: Int; var forward: Bool
        var from: Shape { let e = NoodleStage.library.edges[edge]; return Shape(rawValue: forward ? e.from : e.to)! }
        var to: Shape { let e = NoodleStage.library.edges[edge]; return Shape(rawValue: forward ? e.to : e.from)! }
        var keys: Int { NoodleStage.library.edges[edge].keys.count }
    }
    /// How far the tube travels (its fastest point's displacement) from each key of an edge to the next, summed: so a
    /// change of shape can be played by distance, at a steady pace, however its keys are spaced.
    static let travel: [[Double]] = library.edges.map { e in
        var acc = [0.0]
        for i in 1..<e.keys.count {
            var d = 0.0
            for j in 0..<N { d = max(d, simd_length(e.keys[i][j] - e.keys[i - 1][j])) }
            acc.append(acc[i - 1] + d)
        }
        return acc
    }
    /// A change of shape under way: a route of legs, played by distance `s` along it (one ease-in at the start, one
    /// ease-out at the end, the corners at the shapes passed through rounded), so it never stalls on the way.
    struct Journey { var legs: [Leg]; var s = 0.0; var v = 0.0; var a = 0.0
        var length: Double { legs.reduce(0) { $0 + NoodleStage.travel[$1.edge].last! } }
        var to: Shape { legs.last!.to }
        /// The pose at distance `d` along leg `i`.
        func pose(leg i: Int, at d: Double) -> [V3] {
            let g = legs[i], T = NoodleStage.travel[g.edge], n = g.keys
            let dd = g.forward ? d : T.last! - d                 // distance in the edge's own direction
            var k = 0
            while k < n - 2 && T[k + 1] < dd { k += 1 }
            let w = clamp((dd - T[k]) / max(1e-9, T[k + 1] - T[k]), 0, 1)
            // a smooth curve through the keys (Catmull-Rom), so the motion has no corner at each key
            let K = NoodleStage.library.edges[g.edge].keys
            let a = K[max(0, k - 1)], b = K[k], c = K[k + 1], e = K[min(n - 1, k + 2)]
            let w2 = w * w, w3 = w2 * w
            let h0 = -0.5 * w3 + w2 - 0.5 * w, h1 = 1.5 * w3 - 2.5 * w2 + 1, h2 = -1.5 * w3 + 2 * w2 + 0.5 * w, h3 = 0.5 * w3 - 0.5 * w2
            return (0..<NoodleStage.N).map { i in
                let x: V3 = a[i] * h0 + b[i] * h1
                return x + c[i] * h2 + e[i] * h3
            }
        }
        /// The pose at `s`: on its leg, or, near a shape passed through, a blend of arriving and leaving (so the
        /// motion rounds the corner instead of stopping on the shape and setting off again).
        func pose() -> [V3] {
            var start = 0.0
            for i in 0..<legs.count {
                let L = NoodleStage.travel[legs[i].edge].last!, end = start + L
                if s <= end || i == legs.count - 1 {
                    let d = clamp(s - start, 0, L)
                    let r = 45.0                                     // how far before and after a corner the blend runs
                    if i + 1 < legs.count && s > end - r {
                        let a = Self.ease((s - (end - r)) / (2 * r))
                        let p1 = pose(leg: i, at: min(d, L)), p2 = pose(leg: i + 1, at: max(0, s - end))
                        return (0..<NoodleStage.N).map { (j: Int) -> V3 in p1[j] * (1 - a) + p2[j] * a }
                    }
                    if i > 0 && s < start + r {
                        let a = Self.ease((s - (start - r)) / (2 * r))
                        let p1 = pose(leg: i - 1, at: NoodleStage.travel[legs[i - 1].edge].last!), p2 = pose(leg: i, at: d)
                        return (0..<NoodleStage.N).map { (j: Int) -> V3 in p1[j] * (1 - a) + p2[j] * a }
                    }
                    return pose(leg: i, at: d)
                }
                start = end
            }
            return pose(leg: legs.count - 1, at: NoodleStage.travel[legs.last!.edge].last!)
        }
        static func ease(_ x: Double) -> Double { NoodleStage.ease(x) }
    }

    /// The quickest way from one shape to another, as legs.
    static func route(_ a: Shape, _ b: Shape) -> [Leg] {
        if a == b { return [] }
        let E = library.edges, n = Shape.allCases.count
        var dist = [Double](repeating: .infinity, count: n), via = [Int](repeating: -1, count: n), done = [Bool](repeating: false, count: n)
        dist[b.rawValue] = 0                                        // from the goal back, so we know the first step
        for _ in 0..<n {
            var u = -1
            for i in 0..<n where !done[i] && dist[i] < .infinity && (u < 0 || dist[i] < dist[u]) { u = i }
            if u < 0 { break }
            done[u] = true
            for (k, e) in E.enumerated() {
                let v = e.from == u ? e.to : e.to == u ? e.from : -1
                if v >= 0 && dist[u] + e.secs < dist[v] { dist[v] = dist[u] + e.secs; via[v] = k }
            }
        }
        var legs: [Leg] = [], u = a.rawValue
        while u != b.rawValue {
            let k = via[u]
            guard k >= 0 else { return legs }
            let g = Leg(edge: k, forward: E[k].from == u)
            legs.append(g); u = g.to.rawValue
        }
        return legs
    }

    // MARK: state

    private var at: Shape = .zigzag
    private var journey: Journey?
    private var world = NoodleStage.library.shapes[0]                // as seen (turned, leaning)
    private var delta = [V3](repeating: .zero, count: NoodleStage.N) // the self-collision's push, smoothed in time
    private var spinY = (a: 0.0, v: 0.0, home: nil as Double?), spinZ = (a: 0.0, v: 0.0, home: nil as Double?)
    private var sway = 0.0
    private var flow = (amp: 0.05, phase1: 0.0, phase2: 0.0, kick: 0.0, kickWant: 0.0, speed: 0.45) // the waves running along it
    private var nod = (a: 0.0, v: 0.0)                             // the head's nod, sprung so it never snaps
    private var breath = (phase: 0.0, amp: 0.018, rate: 0.22), strainAmp = 0.0
    private var lean = (x: 0.0, z: 0.0, vx: 0.0, vz: 0.0)          // tipping toward you (x) and sideways (z)
    private var wobble = (x: 0.0, z: 0.0, vx: 0.0, vz: 0.0)
    private var stretch = (k: 1.0, v: 0.0)
    private var crownIdle = 9.0, crownRate = 0.0, fastFor = 0.0
    private var finger: CGPoint?
    private var shakeFor = 0.0, energy = 0.0
    private var reach = (p: P2.zero, v: P2.zero)              // its head reaching toward your finger, on a spring
    private var jig = (p: P2.zero, v: P2.zero)                // flung about while the watch is shaken
    private var hop = (y: 0.0, v: 0.0)                        // a tap: a hop
    private var happyFor = 0.0, pokes: [Double] = []
    private var knock = 0.0, nextTool = 0.8, minis = 0.0
    private var wander = (shape: nil as Shape?, until: 0.0, next: 9.0, last: Shape.zigzag)
    private var shown = (scale: 1.0, cy: 138.0)
    private var state: ChumsState = .idle
    private var t = 0.0, busyAt = 0.0

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        state = s
        if s == .needs { knock = 0 }
        if s != .idle { wander.shape = nil }
        wander.next = max(wander.next, t + rnd(14, 20))           // not straight after a change of state
        busyAt = t
    }

    /// What it should be shaped as now, how fast it spins, and how much it flows.
    private func wanted(_ r: Rig) -> (shape: Shape, spin: Double, flow: Double, flowSpeed: Double) {
        switch state {
        case .listening: return (.lolly, 0, 0.03, 0.5)
        case .thinking: return (.shell, 0.45, 0.035, 0.4)
        case .working: return (.tornado, 1.5, 0.05, 0.75)
        case .subagents: return (.spring, 0.6, 0.04, 0.5)
        case .speaking: return (.zigzag, 0, 0.04 + voice * 0.03, 0.6)
        case .done: return (.spring, 2.4, 0.05, 0.8)          // pops up tall and spins
        case .needs: return (.lolly, 0, 0.035, 0.55)
        case .blocked: return (.knot, 0, 0.02, 0.3)
        case .dizzy: return (.messy, 1.8, 0.06, 0.7)
        case .sleep: return (.sleep, 0, 0.012, 0.18)
        case .approval: return (.zigzag, 0, 0.03, 0.4)
        default: return (wander.shape ?? .zigzag, wander.shape?.axis == 1 ? 0.5 : wander.shape?.axis == 2 ? 0.35 : 0, 0.04, 0.45)
        }
    }

    /// The shape this frame, as points.
    private func pose() -> [V3] { journey?.pose() ?? Self.library.shapes[at.rawValue] }

    func step(_ r: Rig, _ dt0: Double) {
        let dt = min(dt0, 0.04)
        t += dt
        guard !r.ao else { return }
        let n = Self.N
        crownIdle += dt; crownRate *= exp(-dt * 3)
        voice += (r.voice - voice) * min(1, dt * 2.5)        // the voice, eased (syllables would shake it)
        fastFor = crownRate > 9 && crownIdle < 0.3 ? fastFor + dt : 0
        if fastFor > 1 && state != .dizzy { fastFor = 0; r.setState(.dizzy) }
        shakeFor = max(0, shakeFor - dt); energy *= exp(-dt * 4)
        minis += ((state == .subagents ? 1 : 0) - minis) * min(1, dt * 3)
        nextTool -= dt
        if nextTool <= 0 && (!r.worlds.queue.isEmpty || state == .working), let c = r.worlds.nextEvent(r) {
            nextTool = r.worlds.queue.isEmpty ? rnd(1.4, 2.4) : 0.5
            if c.kind != .stop { flow.kickWant = max(flow.kickWant, 0.035) }
        }
        if state == .needs {
            let was = knock; knock += dt; if knock >= 3.2 { knock = 0 }
            if was < 0.25 && knock >= 0.25 { r.onHaptic?(.strong) }
        }
        // idle: now and then it goes off into another shape for a while, then comes back
        if state == .idle && finger == nil {
            if wander.shape == nil && t > wander.next {
                let pick = [Shape.slinky, .spring, .shell, .lolly].filter { $0 != wander.last }
                let s = pick[Int.random(in: 0..<pick.count)]
                wander = (shape: s, until: t + rnd(6, 8), next: 0, last: s)
            } else if let _ = wander.shape, t > wander.until, journey == nil {
                wander.shape = nil; wander.next = t + rnd(16, 24)
            }
        }

        // the shape: the journey under way, re-routed from the next shape on its way when what's wanted changes;
        // played by distance at a steady pace, easing in at the start and out at the end (never stalling between)
        var want = wanted(r)
        let crowning = crownIdle < 1.6
        if crowning && want.shape.axis == 0 && state != .blocked && state != .sleep { want.shape = .tornado }   // the crown winds it up
        if shakeFor > 0 && state != .blocked { want = (.messy, 1.5, 0.07, 0.8) }
        if journey == nil && at != want.shape { let legs = Self.route(at, want.shape); if !legs.isEmpty { journey = Journey(legs: legs) } }
        if var j = journey {
            if j.to != want.shape {
                // keep the leg under way, then go on from where it ends
                var start = 0.0, i = 0
                while i < j.legs.count - 1 && j.s > start + Self.travel[j.legs[i].edge].last! { start += Self.travel[j.legs[i].edge].last!; i += 1 }
                let kept = Array(j.legs[0...i]), on = kept.last!.to
                j.legs = kept + Self.route(on, want.shape)
            }
            let L = j.length, left = max(0, L - j.s)
            let vmax = 85.0, acc = 150.0                              // pt a second (its fastest point), and a second²
            let vt = min(vmax, sqrt(2 * acc * 0.8 * left))
            // the acceleration itself eases toward what's needed (limited jerk), so starts and stops are soft
            let aWant = clamp((vt - j.v) * 3.5, -acc * 1.4, acc), jerk = 520.0
            j.a += clamp(aWant - j.a, -jerk * dt, jerk * dt)
            j.v = max(0, j.v + j.a * dt)
            if left < 0.5 && j.v < 6 { j.s = L } else { j.s = min(L, j.s + j.v * dt) }
            if j.s >= L - 1e-6 { at = j.to; journey = nil } else { journey = j }
        }

        // spinning: round the upright, or round the line of sight; anything that doesn't spin comes home to face you
        let heading = journey?.to ?? at, from = journey?.legs.first?.from ?? at
        func spinStep(_ s: inout (a: Double, v: Double, home: Double?), _ axis: Int, _ rate: Double) {
            let spinning = heading.axis == axis && from.axis == axis
            if spinning {
                s.home = nil
                if !(crowning && axis == 1) || heading.axis != 1 { s.v += (rate - s.v) * min(1, dt / 0.8) }
            } else {
                if s.home == nil { s.home = (s.a / TAU + clamp(s.v * 0.12, -0.45, 0.45)).rounded() * TAU }
                let w = TAU * 0.7
                s.v += (-w * w * (s.a - s.home!) - 2 * w * s.v) * dt
            }
            s.v = clamp(s.v, -10, 10); s.a += s.v * dt
        }
        spinStep(&spinY, 1, want.spin); spinStep(&spinZ, 2, want.spin)
        sway = 0.3 * sin(t * TAU * 0.09) + 0.05 * sin(t * TAU * 0.23)

        // leaning: toward you to listen or ask, toward your finger, a wobble when shaken
        var lx = 0.0, lz = 0.0
        if state == .listening { lx = 0.08 } else if state == .needs { lx = 0.12 }
        if let f = finger {
            let fx = Double(f.x), fy = Double(f.y)
            lz = clamp((fx - 99) / 140, -0.3, 0.3); lx = clamp((shown.cy - 20 - fy) / 220, -0.1, 0.2)
        }
        let wl = TAU * 1.0
        lean.vx += (-wl * wl * (lean.x - lx) - 2 * wl * lean.vx) * dt; lean.x += lean.vx * dt
        lean.vz += (-wl * wl * (lean.z - lz) - 2 * wl * lean.vz) * dt; lean.z += lean.vz * dt
        let ww = TAU * 1.2
        wobble.vx += (-ww * ww * wobble.x - 2 * 0.6 * ww * wobble.vx) * dt; wobble.x += wobble.vx * dt
        wobble.vz += (-ww * ww * wobble.z - 2 * 0.6 * ww * wobble.vz) * dt; wobble.z += wobble.vz * dt
        var sk = 1.0
        if let f = finger { let fy = Double(f.y); sk = clamp(1 + (fy - (shown.cy - 20)) / 900, 0.92, 1.06) }
        let ws = TAU * 1.2
        stretch.v += (-ws * ws * (stretch.k - sk) - 2 * ws * stretch.v) * dt; stretch.k += stretch.v * dt
        let wantScale = state == .approval ? 0.48 : state == .subagents ? 0.86 : 1, wantCY = state == .approval ? 84.0 : 138
        shown.scale += (wantScale - shown.scale) * min(1, dt * 3); shown.cy += (wantCY - shown.cy) * min(1, dt * 3)

        // the waves along it: two, of different lengths and speeds, so it flows and never repeats exactly
        flow.amp += (want.flow - flow.amp) * min(1, dt * 1.5)
        flow.kickWant *= exp(-dt * 1.8); flow.kick += (flow.kickWant - flow.kick) * min(1, dt * 6)
        flow.speed += (want.flowSpeed - flow.speed) * min(1, dt * 2)
        let speed = flow.speed * (1 + flow.kick * 12)
        flow.phase1 += dt * TAU * speed; flow.phase2 += dt * TAU * speed * 0.73
        // breathing, eased between states (a sudden change in it would swing the tube)
        let sleeping = state == .sleep
        breath.amp += ((sleeping ? 0.012 : 0.018) - breath.amp) * min(1, dt * 1.5)
        breath.rate += ((sleeping ? 0.15 : 0.22) - breath.rate) * min(1, dt * 1.5)
        breath.phase += dt * TAU * breath.rate
        strainAmp += ((state == .blocked && journey == nil ? 0.03 : 0) - strainAmp) * min(1, dt * 2)

        // the shape, with the waves running along it as small sideways ripples (they don't add up along it, so they never
        // swing the body round), breathing as a slight stretch upward, a nod of the head
        let target = pose()
        var P = target
        let F = Self.frames(target, normal: rodNormal)
        rodNormal = F.m1[0]
        let breathe = breath.amp * sin(breath.phase) + strainAmp * sin(t * TAU * 0.9)
        let amp = Self.off("RIPPLE") ? 0 : (flow.amp + flow.kick) * 130   // in pt
        for i in 1..<n {
            let u = Double(i) / Double(n - 1), root = Self.ease(u / 0.12)
            let w1 = sin(u * TAU * 1.8 - flow.phase1), w2 = sin(u * TAU * 2.9 - flow.phase2 + 1.3)
            let off: V3 = F.m1[i] * (w1 * amp) + F.m2[i] * (w2 * amp * 0.6)
            P[i] += off * root
            P[i].y = Self.ground + (P[i].y - Self.ground) * (1 + breathe) * stretch.k
        }
        // the head nods: the last stretch of it turns about where the neck starts; the knock starts from rest
        let knockTurn: Double = min(1, knock / 1.0) * 4 * Double.pi
        let knockNod: Double = 0.3 * max(0, sin(knockTurn)) * Self.ease(knock / 0.15)
        let nodWant: Double = state == .needs ? knockNod : state == .speaking ? voice * 0.15 : 0
        let wn = TAU * 2.5
        nod.v += (-wn * wn * (nod.a - nodWant) - 2 * wn * nod.v) * dt; nod.a += nod.v * dt
        if abs(nod.a) > 1e-4 {
            let k0 = Int(0.8 * Double(n - 1)), piv = P[k0], ax = F.m1[k0]
            for i in (k0 + 1)..<n {
                let w = Self.ease(Double(i - k0) / 4)
                P[i] = piv + Self.rotate(P[i] - piv, ax, nod.a * w)
            }
        }
        // its parts kept apart: a soft push, smoothed along the tube and in time
        let need = Self.off("SEP") ? [V3](repeating: .zero, count: n) : separation(P)
        let kk = min(1, dt * (finger != nil ? 16 : 10))
        for i in 0..<n { delta[i] += (need[i] - delta[i]) * kk; P[i] += delta[i] }
        if Self.timing {
            var worst = 0.0
            for i in 1..<(n - 1) { worst = max(worst, acos(clamp(simd_dot(Self.unit(P[i] - P[i - 1]), Self.unit(P[i + 1] - P[i])), -1, 1))) }
            bendStat = max(bendStat, worst / Self.seg * Self.R)
        }
        if let d = Self.dumpStages {
            var f = [Float](repeating: 0, count: 1 + Self.N * 6); f[0] = Float(t)
            for i in 0..<Self.N { for c in 0..<3 { f[1 + 3 * i + c] = Float(target[i][c]); f[1 + 3 * Self.N + 3 * i + c] = Float(P[i][c]) } }
            d.write(f.withUnsafeBufferPointer { Data(buffer: $0) })
        }
        // seen: spun round its middle (the upright, or the line of sight), swaying, leaning on its foot, on the ground
        var mid = V3.zero
        for p in P { mid += p }
        mid /= Double(n)
        let yaw = spinY.a + sway, cyw = cos(yaw), syw = sin(yaw)
        let roll = spinZ.a, cr = cos(roll), sr = sin(roll)
        let ax = lean.x + wobble.x, az = lean.z + wobble.z
        var W = P
        var lowest = -1e9
        for i in 0..<n {
            var a = P[i] - mid
            a = V3(cyw * a.x + syw * a.z, a.y, -syw * a.x + cyw * a.z)
            a = V3(cr * a.x - sr * a.y, sr * a.x + cr * a.y, a.z)
            a = Self.rotate(a, V3(1, 0, 0), ax)
            a = Self.rotate(a, V3(0, 0, 1), -az)
            W[i] = a + mid
            lowest = max(lowest, W[i].y)
        }
        // on the ground, eased (so a spin or a lean never jolts it up and down)
        if started { groundShift += ((Self.ground - lowest) - groundShift) * min(1, dt * 8) } else { groundShift = Self.ground - lowest; started = true }
        for i in 0..<n { W[i].y += groundShift }
        // your finger: its head reaches for it (and swings a little past when you let go); shaken, it's flung about,
        // its head whipping more than its foot; tapped, it hops
        var toward = P2.zero
        if let f = finger {
            let fw = P2((Double(f.x) - 99) / shown.scale, (Double(f.y) - shown.cy) / shown.scale)
            toward = fw - P2(W[n - 1].x, W[n - 1].y)
            let l = simd_length(toward); if l > 34 { toward *= 34 / l }
        }
        // in parts, with their types: whole, these were more than Xcode 26.6's type checker would take
        let wr: Double = TAU * 1.5, wj: Double = TAU * 2.2
        let reachPull: P2 = (toward - reach.p) * (wr * wr), reachDamping: P2 = reach.v * (2 * 0.5 * wr)
        reach.v += (reachPull - reachDamping) * dt; reach.p += reach.v * dt
        let jigPull: P2 = jig.p * (-wj * wj), jigDamping: P2 = jig.v * (2 * 0.3 * wj)
        jig.v += (jigPull - jigDamping) * dt; jig.p += jig.v * dt
        let jl = simd_length(jig.p); if jl > 26 { jig.p *= 26 / jl }
        hop.v += 950 * dt; hop.y += hop.v * dt; if hop.y > 0 { if hop.v > 120 { flow.kickWant = max(flow.kickWant, 0.04) }; hop.y = 0; hop.v = 0 }
        happyFor = max(0, happyFor - dt)
        for i in 0..<n {
            let u = Double(i) / Double(n - 1), a = clamp((u - 0.35) / 0.65, 0, 1), wR = a * a * (3 - 2 * a), wJ = pow(u, 1.5)
            W[i].x += reach.p.x * wR + jig.p.x * wJ
            W[i].y += reach.p.y * wR + jig.p.y * wJ + hop.y
        }
        world = W

        // 30 frames a second are plenty for its own motion (it's soft and slow, and each frame is a lot of pixels); the
        // full rate only while your finger or the crown moves it, so it keeps up with your hand
        if finger != nil || crownIdle < 1.2 { busyAt = t }
    }
    private var groundShift = 0.0, started = false, voice = 0.0
    private var rodNormal: V3?

    /// How far each point must move so no two parts of the tube come closer than its width: pushes that ease in, the
    /// head's side giving more than the foot's, smoothed along the tube so a push is a bump and never a kink.
    private func separation(_ P: [V3]) -> [V3] {
        let n = Self.N, R = Self.R, excl = Int(ceil(4.5 * R / Self.seg))
        var Q = P
        for _ in 0..<3 {
            var corr = [V3](repeating: .zero, count: n), cnt = [Double](repeating: 0, count: n)
            var any = false
            for i in 0..<n {
                var j = i + excl
                while j < n {
                    let d = Q[j] - Q[i], dist = simd_length(d), rr = 2 * R, lim = rr * 1.3
                    if dist < lim && dist > 1e-9 {
                        let x = clamp((lim - dist) / (lim - rr), 0, 1), pen = x * x * (3 - 2 * x) * (lim - dist)
                        let wi = 0.15 + 0.85 * Double(i) / Double(n - 1), wj = 0.15 + 0.85 * Double(j) / Double(n - 1)
                        let push: V3 = d / dist * pen
                        corr[i] -= push * (wi / (wi + wj)); corr[j] += push * (wj / (wi + wj))
                        cnt[i] += 1; cnt[j] += 1; any = true
                    }
                    j += 1
                }
            }
            if !any { break }
            for i in 0..<n where cnt[i] > 0 { corr[i] /= cnt[i] }
            for _ in 0..<4 {
                let c = corr
                for i in 1..<(n - 1) { corr[i] = c[i - 1] * 0.25 + c[i] * 0.5 + c[i + 1] * 0.25 }
            }
            for i in 0..<n { Q[i] += corr[i] }
        }
        return (0..<n).map { Q[$0] - P[$0] }
    }

    // MARK: input

    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        let e = max(0, sqrt(ax * ax + ay * ay + az * az) - 0.9)
        energy += e * e * 0.05
        // while you shake it, it's flung about with the watch and waves run wild along it
        let jerk = sqrt(ax * ax + ay * ay + az * az)
        if jerk > 0.6 {
            jig.v += P2(ax, ay) * (55 * min(1.5, jerk)); flow.kickWant = max(flow.kickWant, min(0.13, 0.03 + jerk * 0.04)); busyAt = t
        }
        // shaken hard: it bunches up, spinning, dizzy
        if energy > 0.35 && shakeFor <= 0 {
            shakeFor = 2.2; energy = 0; spinY.v += 3
            wobble.vx += rnd(-1, 1) * 1.6; wobble.vz += rnd(-1, 1) * 1.6
            if state != .dizzy && state != .sleep { r.setState(.dizzy) }
        }
    }
    func crown(_ r: Rig, _ delta: Double) {
        if at.axis == 2 { spinZ.v = clamp(spinZ.v + delta * 0.6, -8, 8) } else { spinY.v = clamp(spinY.v + delta * 0.6, -8, 8) }
        crownRate += abs(delta) * 3; crownIdle = 0; busyAt = t
    }
    func touched(_ r: Rig, at pt: CGPoint) { finger = pt; busyAt = t }
    func dragged(_ r: Rig, at pt: CGPoint) { finger = pt; busyAt = t }
    func released(_ r: Rig) { finger = nil }
    /// A tap: it hops, a wave runs up it and its eyes smile; four in a row and it's dizzy.
    func poke(_ r: Rig) {
        pokes = pokes.filter { t - $0 < 3 } + [t]; finger = nil; busyAt = t
        if pokes.count >= 4 && state != .dizzy && state != .sleep { pokes = []; spinY.v += 3; r.setState(.dizzy); return }
        hop.v = min(hop.v, -175); flow.kickWant = max(flow.kickWant, 0.1); happyFor = 0.9
        jig.v += P2(rnd(-1, 1) * 30, 0)
    }
    /// Stroked along: its eyes smile and a slow wave runs up it.
    func pet(_ r: Rig) { happyFor = max(happyFor, 0.6); flow.kickWant = max(flow.kickWant, 0.04); busyAt = t }
    func deny(_ r: Rig) {}
    func hit(_ pt: CGPoint) -> Bool {
        let q = P2(pt.x, pt.y)
        return world.contains { simd_length(project($0).p - q) < Self.R * 1.4 * shown.scale }
    }

    // MARK: drawing

    /// A point as seen: straight on (every part the same size), shrunk and placed as shown.
    @inline(__always) private func project(_ p: V3) -> (p: P2, s: Double) {
        let s = shown.scale
        return (P2(99 + p.x * s, shown.cy + p.y * s), s)
    }

    @inline(__always) static func shs(_ c: [Double], _ x: Double, _ y: Double, _ z: Double) -> Double {
        let a = c[0] + c[1] * x + c[2] * y + c[3] * z, b = c[4] * (x * y) + c[5] * (x * z) + c[6] * (y * z)
        return a + b + c[7] * (x * x - y * y) + c[8] * (3 * z * z - 1)
    }
    static let H = unit(V3(-0.45, -0.62, 0.65))
    static let tint = P3(0.42, 0.22, 0.48)                          // shade goes toward a deep magenta-purple

    /// Its colour at `u` along it where the surface faces N (seen: y down, z toward you): the reference's colours lit by
    /// the light fitted to it, a highlight, and the head's own yellow-orange.
    static func shade(_ u: Double, _ N: V3) -> P3 {
        let A = NoodleRest.albedo, kn = A.count
        func albedo(_ u: Double) -> P3 {
            let ua = min(1, u * NoodleRest.length / 373), f = ua * Double(kn - 1)
            let k0 = min(kn - 2, Int(f)), w = f - Double(k0)
            return A[k0] * (1 - w) + A[k0 + 1] * w
        }
        // the tail: one blue, deepening to its tip (the reference has a purple patch on its curl that reads as a flicker)
        let tail = 0.11
        var alb: P3 = u < tail ? A[0] * (1 - ease(u / tail)) + albedo(tail) * ease(u / tail) : albedo(u)
        let hk = ease((u - 0.86) / 0.14) * 0.85
        alb = alb * (1 - hk) + P3(1.0, 0.70, 0.13) * hk
        let lit = shs(NoodleRest.light, N.x, N.y, N.z), sheen = shs(NoodleRest.sheen, N.x, N.y, N.z)
        let x = max(0, simd_dot(N, H)), x2 = x * x, x4 = x2 * x2, spec = 0.2 * x4 * x4 * x2
        return alb * lit + P3(sheen, sheen, sheen) + P3(1, 0.97, 0.92) * spec
    }
    static func color(_ c: P3) -> Color { Color(red: clamp(c.x, 0, 1), green: clamp(c.y, 0, 1), blue: clamp(c.z, 0, 1)) }

    static let M = 6

    // MARK: measurements (Simulator only): NOODLE_DEBUG prints the draw cost, NOODLE_DUMP writes every frame's points
    private static let timing = ProcessInfo.processInfo.environment["NOODLE_DEBUG"] != nil
    private static let dump: FileHandle? = {
        guard ProcessInfo.processInfo.environment["NOODLE_DUMP"] != nil else { return nil }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("coil-dump.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    private static let dumpStages: FileHandle? = {
        guard ProcessInfo.processInfo.environment["NOODLE_DUMP"] != nil else { return nil }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("coil-stages.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    /// Simulator measurements: NOODLE_OFF=SEP,BEND,RIPPLE turns those parts off.
    private static let offList = ProcessInfo.processInfo.environment["NOODLE_OFF"] ?? ""
    private static func off(_ k: String) -> Bool { offList.contains(k) }
    private var cost = (sum: 0.0, max: 0.0, n: 0)
    private var split = [Double](repeating: 0, count: 4)   // geometry, sampling, sort, painting
    private var bendStat = 0.0
    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        let t0 = Self.timing ? DispatchTime.now().uptimeNanoseconds : 0
        if let d = Self.dump {
            var f = [Float](repeating: 0, count: 1 + Self.N * 3); f[0] = Float(t)
            for i in 0..<Self.N { f[1 + 3 * i] = Float(world[i].x); f[2 + 3 * i] = Float(world[i].y); f[3 + 3 * i] = Float(world[i].z) }
            d.write(f.withUnsafeBufferPointer { Data(buffer: $0) })
        }
        drawBody(r, ctx)
        if Self.timing {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            cost.sum += ms; cost.max = max(cost.max, ms); cost.n += 1
            if cost.n >= 120 { print(String(format: "coil draw: avg %.2f ms  max %.2f ms  (curve+shade table %.2f depth %.2f colour %.2f image %.2f)  tightest bend R·k %.2f", cost.sum / Double(cost.n), cost.max, split[0] / 120, split[1] / 120, split[2] / 120, split[3] / 120, bendStat)); cost = (0, 0, 0); split = [0, 0, 0, 0]; bendStat = 0 }
        }
    }

    /// How it's drawn: flat, its colours along it with no light or shade (the default), or lit like the reference
    /// ("lit", from the `noodleLook` default: a launch argument, -noodleLook lit).
    static let look = UserDefaults.standard.string(forKey: "noodleLook") ?? "flat"
    /// Pixels it draws per screen pixel, each way (-noodleRes 0.625 for fewer).
    static let res = UserDefaults.standard.object(forKey: "noodleRes") as? Double ?? 0.625
    /// Buffers for the tube's picture, kept between frames.
    private var zbuf: [Float] = [], ibuf: [Int32] = [], cbuf: [Float] = [], rgba: [UInt8] = []
    /// The picture at a point on screen (pt): its depth there and how far along the tube (0…1) that surface is, for
    /// hiding the eyes behind another part of the tube in front of them.
    private var depthAt: (P2) -> (z: Double, u: Double) = { _ in (-1e9, -1) }

    /// The tube, shaded pixel by pixel: the union of spheres along its curve, each pixel taking the nearest surface
    /// (a depth buffer), its normal the tube's (the sphere's, less the part along the tube; the ends keep their own),
    /// lit by the model fitted to the reference, shaded where other parts of the tube are near it in 3D, a little
    /// darker the further back it is, its edge antialiased; drawn as one image. Smooth everywhere, however it turns.
    private func drawBody(_ r: Rig, _ ctx: GraphicsContext) {
        let g = r.ao ? ctx.faded(0.5) : ctx
        let n = Self.N, R = Self.R, sc = shown.scale, m = 8
        let tm0 = Self.timing ? Self.now() : 0
        // the points smoothed along the tube first: changes of shape and the pushes that keep it apart leave small
        // wiggles from point to point, which would show as rings and dents in a tube this smooth
        var sm = world
        for _ in 0..<2 {
            let src = sm
            func at(_ i: Int) -> V3 { i < 0 ? src[0] * 2 - src[-i] : i >= n ? src[n - 1] * 2 - src[2 * (n - 1) - i] : src[i] }
            for i in 1..<(n - 1) {
                let a: V3 = at(i - 2) + at(i + 2), b: V3 = (at(i - 1) + at(i + 1)) * 4
                sm[i] = (a + b + src[i] * 6) / 16
            }
        }
        // the curve: a smooth spline through the points, five samples a link
        let sub = 5, cnt = (n - 1) * sub + 1
        var q = [V3](repeating: .zero, count: cnt)
        for i in 0..<cnt {
            let f = Double(i) / Double(sub), j = min(n - 2, Int(f)), w = f - Double(j)
            let p0 = sm[max(0, j - 1)], p1 = sm[j], p2 = sm[j + 1], p3 = sm[min(n - 1, j + 2)]
            let w2 = w * w, w3 = w2 * w
            let a: V3 = p1 * 2, b: V3 = (p2 - p0) * w
            let c1: V3 = p0 * 2 - p1 * 5, c: V3 = (c1 + p2 * 4 - p3) * w2
            let d1: V3 = p1 * 3 - p0, d: V3 = (d1 - p2 * 3 + p3) * w3
            q[i] = (a + b + c + d) * 0.5
        }
        let tang: [V3] = (0..<cnt).map { Self.unit(q[min(cnt - 1, $0 + 4)] - q[max(0, $0 - 4)]) }
        // shade where another part of the tube is near, in 3D: at each point, for directions across it (8, from the
        // side in the picture's plane through facing you to the other side)
        var ao = [Float](repeating: 0, count: n * m), nrmN = [V3](repeating: .zero, count: n), bnN = nrmN
        let farNodes = Int(ceil(3.5 * R / Self.seg))
        for i in 0..<n where Self.look == "lit" {             // (flat has no shade)
            let tg = Self.unit(world[min(n - 1, i + 1)] - world[max(0, i - 1)])
            let lin = sqrt(tg.x * tg.x + tg.y * tg.y)
            let nrm = lin < 0.05 ? V3(0, -1, 0) : V3(tg.y / lin, -tg.x / lin, 0)
            var bn = Self.unit(simd_cross(nrm, tg)); if bn.z < 0 { bn = -bn }
            nrmN[i] = nrm; bnN[i] = bn
            var near: [Int] = []
            for j in 0..<n where abs(i - j) > farNodes && simd_length(world[j] - world[i]) < 4.2 * R { near.append(j) }
            if near.isEmpty { continue }
            for k in 0..<m {
                let s = 1 - 2 * Double(k) / Double(m - 1)
                let N: V3 = nrm * s + bn * sqrt(max(0, 1 - s * s)), surf: V3 = world[i] + N * R
                var keep = 1.0
                for j in near {
                    let D = world[j] - surf, dd = simd_length(D)
                    if dd > 2.8 * R { continue }
                    let nd = simd_dot(D, N) / max(dd, 1e-6)
                    if nd <= 0 { continue }
                    let f = clamp(1 - (dd - R) / (1.8 * R), 0, 1)
                    keep *= 1 - nd * f * f
                }
                ao[i * m + k] = Float(min(0.85, 1 - keep))
            }
        }
        let tm1 = Self.timing ? Self.now() : 0
        // the picture: the tube's bounds on screen, at the screen's own pixels (more when rendering larger)
        let rs = clamp(r.pixelScale * Self.res, 1, 6)   // 1.25 pixels a point on the watch (its 2): the tube is smooth, and
                                                        // it's 40% of the pixels; the iPhone draws it bigger, so more
        var lo = P2(1e9, 1e9), hi = P2(-1e9, -1e9)
        for i in 0..<cnt { let p = project(q[i]).p; lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let pad = R * sc + 1
        let x0 = floor(lo.x - pad), y0 = floor(lo.y - pad)
        let W = max(1, Int(ceil((hi.x + pad - x0) * rs))), H = max(1, Int(ceil((hi.y + pad - y0) * rs)))
        let size = W * H
        if zbuf.count < size { zbuf = [Float](repeating: 0, count: size); ibuf = [Int32](repeating: 0, count: size); cbuf = zbuf; rgba = [UInt8](repeating: 0, count: size * 4) }
        let rp = Float(R * sc * rs), rp2 = rp * rp, re = rp + 0.5, k2w = Float(1 / (sc * rs))
        // how far a sphere's surface stands out toward you, by the squared distance from its centre (a table, not a root
        // per pixel); inside `core` a pixel is fully covered, so only the rim needs its distance
        let zt: [Float] = (0...(Int(rp2) + 1)).map { (max(0, rp2 - Float($0))).squareRoot() * k2w }
        let core = max(0, rp - 0.5), core2 = core * core
        zbuf.withUnsafeMutableBufferPointer { zb in
        ibuf.withUnsafeMutableBufferPointer { ib in
        cbuf.withUnsafeMutableBufferPointer { cb in
            for i in 0..<size { zb[i] = -1e9; ib[i] = -1; cb[i] = 0 }
            // the spheres, every third sample (they overlap so much the surface between them dips < 0.2 pt; the colour
            // and light come from the true place along the tube, so nothing steps)
            var j = 0
            while j < cnt {
                let pj = project(q[j]).p
                let cx = Float((pj.x - x0) * rs), cy = Float((pj.y - y0) * rs), cz = Float(q[j].z), jj = Int32(j)
                let ya = max(0, Int(cy - re)), yb = min(H - 1, Int(cy + re))
                if ya <= yb {
                    for y in ya...yb {
                        let dy = Float(y) + 0.5 - cy, dy2 = dy * dy
                        if dy2 > re * re { continue }
                        let hw = (re * re - dy2).squareRoot()
                        let xa = max(0, Int(cx - hw)), xb = min(W - 1, Int(cx + hw))
                        if xa > xb { continue }
                        let row = y * W
                        zt.withUnsafeBufferPointer { zt in
                            for x in xa...xb {
                                let dx = Float(x) + 0.5 - cx, d2 = dx * dx + dy2, idx = row + x
                                let z: Float
                                if d2 < core2 { cb[idx] = 1; z = cz + zt[Int(d2)] } else {
                                    let cov = min(1, max(0, rp - d2.squareRoot() + 0.5))
                                    if cov > cb[idx] { cb[idx] = cov }
                                    z = d2 < rp2 ? cz + zt[Int(d2)] : cz
                                }
                                if z > zb[idx] { zb[idx] = z; ib[idx] = jj }
                            }
                        }
                    }
                }
                j = j == cnt - 1 ? cnt : min(cnt - 1, j + 3)
            }
        }}}
        let tm2 = Self.timing ? Self.now() : 0
        // the colours: each pixel's surface, lit and shaded
        let one = P3(1, 1, 1), dark: P3 = one - Self.tint
        let invRs = 1 / rs
        let flat = Self.look != "lit"
        let flatCols: [P3] = flat ? (0...64).map { Self.shade(Double($0) / 64, V3(0, 0, 1)) } : []
        var segLen = 0.0
        for i in 1..<cnt { segLen += simd_length(q[i] - q[i - 1]) }
        segLen /= Double(cnt - 1)
        rgba.withUnsafeMutableBufferPointer { px in
        zbuf.withUnsafeBufferPointer { zb in
        ibuf.withUnsafeBufferPointer { ib in
        cbuf.withUnsafeBufferPointer { cb in
            for y in 0..<H {
                for x in 0..<W {
                    let idx = y * W + x, cov = cb[idx], o = idx * 4
                    if cov <= 0 || ib[idx] < 0 { px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0; continue }
                    let j = Int(ib[idx]), c = q[j]
                    // the point on the surface, in the tube's own units
                    let sxp = (Double(x) + 0.5) * invRs + x0, syp = (Double(y) + 0.5) * invRs + y0
                    let wx = (sxp - 99) / sc, wy = (syp - shown.cy) / sc
                    let off = V3(wx - c.x, wy - c.y, Double(zb[idx]) - c.z)
                    // where along the tube this surface really is (between the samples, so colour and light don't step)
                    let alongW = simd_dot(off, tang[j]), fj = clamp(Double(j) + alongW / segLen, 0, Double(cnt - 1))
                    if flat {
                        // flat: the colour along it as it looks facing you, nothing else
                        let fu = fj / Double(cnt - 1) * Double(flatCols.count - 1), f0 = min(flatCols.count - 2, Int(fu)), fw = fu - Double(f0)
                        let c: P3 = flatCols[f0] * (1 - fw) + flatCols[f0 + 1] * fw
                        let a = Double(cov) * 255
                        px[o] = UInt8(clamp(c.x, 0, 1) * a + 0.5)
                        px[o + 1] = UInt8(clamp(c.y, 0, 1) * a + 0.5)
                        px[o + 2] = UInt8(clamp(c.z, 0, 1) * a + 0.5)
                        px[o + 3] = UInt8(a + 0.5)
                        continue
                    }
                    let ja = min(cnt - 2, Int(fj)), wj = fj - Double(ja)
                    let cc: V3 = q[ja] * (1 - wj) + q[ja + 1] * wj, t3 = Self.unit(tang[ja] * (1 - wj) + tang[ja + 1] * wj)
                    var N = (V3(wx, wy, Double(zb[idx])) - cc) / R
                    let along = simd_dot(N, t3)
                    let cap = (j == cnt - 1 && alongW > 0) || (j == 0 && alongW < 0)
                    N = cap ? off / R : N - t3 * along
                    N = Self.unit(N)
                    let u = fj / Double(cnt - 1)
                    var col = Self.shade(u, N)
                    // shade from the parts near it (the table at the points either side, across by where it faces)
                    let fi = u * Double(n - 1), i0 = min(n - 2, Int(fi)), wi = fi - Double(i0)
                    func aoAt(_ i: Int) -> Double {
                        let s = clamp(simd_dot(N, nrmN[i]), -1, 1), fk = (1 - s) * 0.5 * Double(m - 1)
                        let k0 = min(m - 2, Int(fk)), wk = fk - Double(k0)
                        return Double(ao[i * m + k0]) * (1 - wk) + Double(ao[i * m + k0 + 1]) * wk
                    }
                    let sh = aoAt(i0) * (1 - wi) + aoAt(i0 + 1) * wi
                    let zc: Double = clamp(Double(zb[idx]) / 60, -1, 1)
                    let cue: Double = 1 - 0.25 * (0.5 - 0.5 * zc)
                    col = col * (one - dark * sh) * cue
                    let a = Double(cov)
                    px[o] = UInt8(clamp(col.x, 0, 1) * a * 255 + 0.5)
                    px[o + 1] = UInt8(clamp(col.y, 0, 1) * a * 255 + 0.5)
                    px[o + 2] = UInt8(clamp(col.z, 0, 1) * a * 255 + 0.5)
                    px[o + 3] = UInt8(a * 255 + 0.5)
                }
            }
        }}}}
        let tm3 = Self.timing ? Self.now() : 0
        // hand the depth to the eyes, then draw: the small coils behind, the tube, the eyes, the extras
        let zcopy = zbuf, icopy = ibuf, wW = W, hH = H, last = Double(cnt - 1)
        depthAt = { p in
            let x = Int((p.x - x0) * rs), y = Int((p.y - y0) * rs)
            guard x >= 0 && y >= 0 && x < wW && y < hH, icopy[y * wW + x] >= 0 else { return (-1e9, -1) }
            return (Double(zcopy[y * wW + x]), Double(icopy[y * wW + x]) / last)
        }
        drawMinis(g)
        let image: CGImage? = rgba.withUnsafeMutableBytes { raw in
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let cg = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return cg.makeImage()
        }
        if let image {
            g.draw(g.resolve(Image(decorative: image, scale: rs)), in: CGRect(x: x0, y: y0, width: Double(W) / rs, height: Double(H) / rs))
        }
        drawEyes(g, r: r, q: q, tang: tang)
        drawExtras(g, r: r, head: project(q[cnt - 1]).p)
        depthAt = { _ in (-1e9, -1) }
        if Self.timing { let tm4 = Self.now(); split[0] += tm1 - tm0; split[1] += tm2 - tm1; split[2] += tm3 - tm2; split[3] += tm4 - tm3 }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}

    /// The eyes: near the head's end, on the side facing you, foreshortened as it turns away, hidden on its back.
    private func drawEyes(_ g: GraphicsContext, r: Rig, q: [V3], tang: [V3]) {
        let E = q[q.count - 1], tE = tang[tang.count - 1], R = Self.R
        let fd = Self.unit(V3(0, 0, 1) + tE * 0.12 + V3(0, -0.4, 0))
        let right = Self.unit(simd_cross(V3(0, -1, 0), fd)), up = Self.unit(simd_cross(fd, right))
        let p = r.pose(raw: true)
        var gaze = P2(p.eye.gx, p.eye.gy)
        if let f = finger {
            let d = P2(f.x, f.y) - project(E).p, l = max(1, simd_length(d)); gaze = d / l
        }
        let line = StrokeStyle(lineWidth: 1.6, lineCap: .round)
        for side in [-1.0, 1.0] {
            let aside: V3 = right * (side * 0.42), lift: V3 = up * 0.1
            let dir = Self.unit(fd + aside + lift)
            if dir.z < 0.12 { continue }
            let at: V3 = E - tE * (0.55 * R) + dir * R
            let pp = project(at), s = pp.s
            let seen = depthAt(pp.p)                                // another part of the tube in front of it
            if seen.u >= 0 && seen.u < 0.9 && seen.z > at.z + 0.3 * R { continue }
            let e: P2 = pp.p + gaze * (1.4 * s)
            let fz = 0.6 + 0.4 * min(1, dir.z)
            let rx = 3.7 * s * fz, ry = 5.0 * s
            if happyFor > 0 && state != .sleep && state != .dizzy {                      // smiling: ∩
                var l = Path(); l.move(to: CGPoint(x: e.x - 3.6 * s, y: e.y + 1.4 * s)); l.addQuadCurve(to: CGPoint(x: e.x + 3.6 * s, y: e.y + 1.4 * s), control: CGPoint(x: e.x, y: e.y - 4.2 * s))
                g.stroke(l, with: .color(Self.cream), style: StrokeStyle(lineWidth: 1.9, lineCap: .round)); continue
            }
            switch state {
            case .done:
                var st = Path()
                for j in 0..<10 {
                    let a = -Double.pi / 2 + Double(j) * Double.pi / 5, rr = (j % 2 == 0 ? 5.2 : 2.2) * s
                    let c = CGPoint(x: e.x + cos(a) * rr, y: e.y + sin(a) * rr)
                    if j == 0 { st.move(to: c) } else { st.addLine(to: c) }
                }
                st.closeSubpath(); g.fill(st, with: .color(Self.cream))
            case .sleep:
                var l = Path(); l.move(to: CGPoint(x: e.x - 3.4 * s, y: e.y)); l.addQuadCurve(to: CGPoint(x: e.x + 3.4 * s, y: e.y), control: CGPoint(x: e.x, y: e.y + 2.8 * s))
                g.stroke(l, with: .color(Self.cream), style: line)
            case .dizzy:
                var sp = Path()
                for j in 0...30 {
                    let u = Double(j) / 30, a = u * 2 * TAU + t * 6 * side, rr = (0.5 + u * 3.8) * s
                    let c = CGPoint(x: e.x + cos(a) * rr, y: e.y + sin(a) * rr)
                    if j == 0 { sp.move(to: c) } else { sp.addLine(to: c) }
                }
                g.stroke(sp, with: .color(Self.cream), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            default:
                let open = clamp(p.eye.open, 0, 1)
                if open < 0.3 {
                    var l = Path(); l.move(to: CGPoint(x: e.x - rx * 0.8, y: e.y)); l.addLine(to: CGPoint(x: e.x + rx * 0.8, y: e.y))
                    g.stroke(l, with: .color(Self.cream), style: line)
                } else {
                    let big = state == .listening || state == .needs ? 1.12 : 1
                    let hh = ry * big * (state == .working ? 0.65 : 1) * open, w = rx * big
                    g.fill(Path(ellipseIn: CGRect(x: e.x - w - 0.6, y: e.y - hh - 0.6, width: 2 * w + 1.2, height: 2 * hh + 1.2)), with: .color(Self.cream.opacity(0.3)))
                    g.fill(Path(ellipseIn: CGRect(x: e.x - w, y: e.y - hh, width: 2 * w, height: 2 * hh)), with: .color(Self.cream))
                }
            }
        }
    }

    /// The little strokes by its head (done, needs you).
    private func drawExtras(_ g: GraphicsContext, r: Rig, head c: P2) {
        if (state == .done && r.stateT < 1.4) || (state == .needs && knock < 0.6) {
            let k = state == .done ? r.stateT / 1.4 : knock / 0.6
            let base: P2 = c + P2(26, -26) * shown.scale
            let tint = Color(red: 0.62, green: 0.66, blue: 0.78)
            for j in 0..<3 {
                let a = -Double.pi / 2 + Double(j) * 0.62 - 0.2, r0 = 4 + 5 * k
                var l = Path()
                l.move(to: CGPoint(x: base.x + cos(a) * r0, y: base.y + sin(a) * r0))
                l.addLine(to: CGPoint(x: base.x + cos(a) * (r0 + 8), y: base.y + sin(a) * (r0 + 8)))
                g.faded(1 - k * 0.8).stroke(l, with: .color(tint), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
    }

    /// Small coils going round behind it (subagents).
    private func drawMinis(_ g: GraphicsContext) {
        guard minis > 0.02 else { return }
        let cols = [Self.color(P3(0.25, 0.5, 1)), Self.color(P3(0.6, 0.3, 0.95)), Self.color(P3(0.98, 0.3, 0.55)), Self.color(P3(1, 0.7, 0.15))]
        for m in 0..<3 {
            let a = t * 0.7 + Double(m) * TAU / 3
            let ctr: P2 = P2(99, 140) + P2(cos(a) * 82, sin(a) * 58) * minis
            let k = 0.2 * minis
            let zig: [P2] = [P2(18, 70), P2(-30, 40), P2(30, 0), P2(-25, -35), P2(5, -55)].map { ctr + $0 * k }
            g.stroke(Strokes.smoothOpen(zig), with: .linearGradient(Gradient(colors: cols), startPoint: CGPoint(x: zig[0].x, y: zig[0].y), endPoint: CGPoint(x: zig[4].x, y: zig[4].y)),
                     style: StrokeStyle(lineWidth: 26 * k, lineCap: .round, lineJoin: .round))
        }
    }
}
