import SwiftUI

/// Stretch on the watch: the same player as design/noodle/player.part, frame for frame.
/// Each state is a pool of segments: a calm rest loop and several beats that start and end on the same pose, chained at
/// random (never the same beat twice in a row). noodle.json says, frame by frame, where its hair top, face and the glass
/// contact are on screen, so the screen plays along: the approval card rides on its hair, tool calls drop on its head and
/// get bonked away, the glass fogs and ripples where it knocks.
final class StretchStage: Staged {
    static let shared = StretchStage()

    // MARK: clip data (ChumsWatch/Noodle/noodle.json, from design/noodle/renders/clips.json)

    struct Clip: Decodable {
        let n: Int
        let loop: Bool?
        let role: String?
        let state: String?
        let events: [String: Frames]?
        let frames: [[Double]]?
        struct Frames: Decodable {
            let list: [Int]
            init(from d: Decoder) throws {
                let c = try d.singleValueContainer()
                if let i = try? c.decode(Int.self) { list = [i] } else { list = try c.decode([Int].self) }
            }
        }
    }
    private struct Meta: Decodable { let fps: Double; let beat_chance: [String: Double]; let clips: [String: Clip] }
    private let meta: Meta? = {
        guard let url = Bundle.main.url(forResource: "noodle", withExtension: "json", subdirectory: "Noodle"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }()
    private var CL: [String: Clip] { meta?.clips ?? [:] }
    private var fps: Double { meta?.fps ?? 24 }

    private func of(_ state: String, _ role: String) -> [String] { CL.keys.filter { CL[$0]?.state == state && CL[$0]?.role == role }.sorted() }
    private func count(_ name: String) -> Int { CL[name]?.n ?? 1 }
    private func isLoop(_ name: String) -> Bool { CL[name]?.loop == true }

    // MARK: player state

    struct Card { var phase = "fall"; var x = 99.0, y = 38.0, rot = 0.0, vx = 0.0, vy = 0.0, vr = 0.0; var text = ""; var kind = "read" }
    enum FXKind { case glass, confetti, bonk, z }
    struct FX { var k: FXKind; var x: Double, y: Double; var t = 0.0; var vx = 0.0, vy = 0.0, r = 0.0, vr = 0.0; var c = Color.white; var amp = 1.0 }

    /// How long one clip takes to dissolve into the next when the state changes (eased): long enough to read as one
    /// movement rather than a cut.
    private static let dissolve = 0.3
    /// The dissolve itself stays short (two poses overlaid read as a ghost); the camera's move carries on after it.
    private var fadeLength: Double { Self.dissolve }
    private var clip = "idle_rest", f = 0.0
    private var queue: [String] = []
    private var fade: (image: CGImage?, t: Double)?
    /// Match moves. The clips of each state are framed their own way (its face higher or lower, nearer or farther), so a
    /// cut from one state to another would jump. Instead the two shots are lined up on the face, and the shot moves:
    /// cutting in closer, the outgoing frame pushes in to the new framing as it dissolves away; cutting out wider, the
    /// incoming clip starts pushed in to the old framing and eases out to its own. Always a push in, never a pull out,
    /// so the bottom edge of the frames (where its body is cut off) never comes into view.
    /// A placement maps a frame's face `from` to `to`, scaled `k` about it.
    private struct Place { var from: CGPoint; var to: CGPoint; var k: Double
        var xf: CGAffineTransform {
            CGAffineTransform(translationX: -from.x, y: -from.y).concatenating(CGAffineTransform(scaleX: k, y: k)).concatenating(CGAffineTransform(translationX: to.x, y: to.y))
        }
        func toward(_ b: Place, _ e: Double) -> Place {
            Place(from: from, to: CGPoint(x: lerp(Double(to.x), Double(b.to.x), e), y: lerp(Double(to.y), Double(b.to.y), e)), k: lerp(k, b.k, e))
        }
    }
    private static let glide = 0.6
    private var glideIn: (start: Place, t: Double)?                 // the incoming clip, easing out to its own framing
    private var fadeMove: (start: Place, end: Place)?               // the outgoing frame, pushing in as it dissolves
    private func ease(_ u: Double) -> Double { let v = clamp(u, 0, 1); return v * v * (3 - 2 * v) }
    /// The current clip's placement right now (identity when it's in its own framing).
    private var placeNow: CGAffineTransform {
        guard let g = glideIn else { return .identity }
        let id = Place(from: g.start.from, to: g.start.from, k: 1)
        return g.start.toward(id, ease(g.t / Self.glide)).xf
    }
    private func faceOf(_ name: String, _ i: Int) -> (face: CGPoint, size: Double)? {
        guard let fr = CL[name]?.frames, !fr.isEmpty else { return nil }
        let a = fr[max(0, min(fr.count - 1, i))]
        guard a.count >= 4 else { return nil }
        return (CGPoint(x: a[2], y: a[3]), max(10, hypot(a[2] - a[0], a[3] - a[1])))
    }
    /// Keeps a placement from lifting the frame's bottom edge (its cut-off body) into view.
    private func grounded(_ p: Place) -> Place {
        var q = p
        let bottom = Double(q.to.y) + (242 - Double(q.from.y)) * q.k
        if bottom < 246 { q.to.y += 246 - bottom }
        return q
    }
    private var bags: [String: [String]] = [:], last: String?
    private var work = "work_read"
    private var tool: Card?, card: Card?
    private var fx: [FX] = []
    private var fog = 0.0, zT = 0.0, flex = 0.0, held = false
    /// The gel: Noodle sloshes with the watch. A damped spring the watch's own acceleration drives, standing on the
    /// screen's bottom edge like a puppet on a stick: sideways it leans and its hair whips, up and down it squashes
    /// and stretches, toward you it presses into the glass and, hard enough, knocks it (the liquid-glass ring).
    private var gel = (x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0), push = (x: 0.0, y: 0.0, z: 0.0)
    /// How hard it's being shaken, 0…1: every move of the watch adds the square of how far it goes over 0.9 g (a gentle
    /// sway adds almost nothing, a hard shake fills it in a quarter of a second), and it drains in about a second.
    /// The camera answers it (it punches in, shakes by its square, so only hard shakes really shake, and rolls), and so
    /// does the gel: it wobbles, squashing and stretching fast, and a wave runs up its body from the base.
    private var trauma = 0.0
    private var cam = (z: 1.0, vz: 0.0)
    private var rawFace = (x: 96.0, y: 120.0)                      // the face in the frame, before the gel and the camera
    /// The crown stretches it: everything below its eyes grows taller (and thinner, keeping its volume) or squashes,
    /// the head riding on top undistorted; let go, it springs back and wobbles like jelly.
    private var neck = (k: 1.0, v: 0.0, to: 1.0), crownIdle = 9.0
    private var seam: Double { rawFace.y + 20 }                     // just below its eyes: above it moves, below it stretches
    private var view = CGAffineTransform.identity                  // this frame's, for the glass rings' lenses
    private var shown: CGImage?                                   // the frame on screen, kept while the next decodes
    private var stateName = "idle"
    private var demoCallT = 2.5                                    // demo mode: a made-up tool call every few seconds

    let ownsApproval = true
    let holds: [ChumsState: Double] = [.done: 4.4, .dizzy: 4.8]
    func captionTop(_ r: Rig) -> Bool { r.state == .needs }
    func ownsCaption(_ r: Rig) -> Bool { false }

    private func name(_ s: ChumsState) -> String { s.rawValue }
    private func restFor(_ s: String) -> String { s == "working" ? work : (of(s, "rest").first ?? "idle_rest") }
    private var clipNow: String { held ? "approval_hold" : clip }
    private func frameNo(_ r: Rig) -> Int {
        if held { return Int((clamp(r.hold, 0, 1) * Double(count("approval_hold") - 1)).rounded()) }
        let c = count(clip)
        return isLoop(clip) ? Int(f) % c : min(c - 1, Int(f))
    }

    /// Where things are on screen this frame: hair top, face, roll, how hard it presses the glass.
    private struct Anchors { var hx = 120.0, hy = 40.0, fx = 96.0, fy = 120.0, roll = 0.0, press = 0.0, rise = 0.0 }
    private func anchors(_ r: Rig) -> Anchors {
        guard let fr = CL[clipNow]?.frames, frameNo(r) < fr.count, fr[frameNo(r)].count >= 7 else { return Anchors() }
        let a = fr[frameNo(r)]
        rawFace = (a[2], a[3])
        let T = placeNow.concatenating(viewTransform(r.t)), h = CGPoint(x: a[0], y: neckY(a[1])).applying(T), f = CGPoint(x: a[2], y: neckY(a[3])).applying(T)
        return Anchors(hx: h.x, hy: h.y, fx: f.x, fy: f.y, roll: a[4] - gel.x * 0.5, press: a[5], rise: a[6])
    }

    private func play(_ r: Rig, _ n: String, from: Double = 0, then: [String] = [], dissolve: Bool = true) {
        guard CL[n] != nil else { return }
        let was = dissolve ? faceOf(clipNow, frameNo(r)) : nil, wasPlace = placeNow
        if dissolve { fade = (shown, 0); fadeMove = nil }
        clip = n; f = from; queue = then; held = false
        // line the two shots up on the face (see Place)
        if dissolve, let o = was, let nw = faceOf(n, Int(from)) {
            let oFace = o.face.applying(wasPlace), oSize = o.size * hypot(Double(wasPlace.a), Double(wasPlace.b))
            let off = hypot(Double(oFace.x - nw.face.x), Double(oFace.y - nw.face.y)), ratio = nw.size / oSize
            glideIn = nil
            if off > 3 || abs(ratio - 1) > 0.04 {
                if ratio >= 1 {                                           // closer: the old frame pushes in to the new framing
                    let start = Place(from: o.face, to: oFace, k: oSize / o.size)
                    fadeMove = (start, grounded(Place(from: o.face, to: nw.face, k: nw.size / o.size)))
                } else {                                                  // wider: the new clip starts pushed in, eases out
                    glideIn = (grounded(Place(from: nw.face, to: oFace, k: oSize / nw.size)), 0)
                }
            }
        }
        if n == "approval_in" { card = Card(phase: "fall", x: 99, y: 38, text: r.approvalTitle) }
        if n == "bump", let e = r.worlds.nextEvent(r) {
            let kind = e.kind == .read ? "read" : e.kind == .edit ? "edit" : e.kind == .agent ? "search" : "run"
            tool = Card(phase: "fall", text: e.text, kind: kind)
        }
        StretchFrames.shared.preload(n)
    }

    /// The next segment of the state's pool: its rest loop again, or a beat (never the same one twice in a row).
    /// It's picked half a second before the current one ends, so its first frames are decoded by the cut.
    private var upcoming: String?
    private func pickNext() -> String {
        let beats = of(stateName, "beat")
        if !beats.isEmpty && Double.random(in: 0..<1) < (meta?.beat_chance[stateName] ?? 0.4) {
            var bag = bags[stateName] ?? []
            if bag.isEmpty {
                bag = beats.shuffled()
                if bag.count > 1 && bag.last == last { bag.insert(bag.removeLast(), at: 0) }
            }
            last = bag.removeLast(); bags[stateName] = bag
            return last!
        }
        return restFor(stateName)
    }
    private func nextSegment(_ r: Rig) {
        let n = upcoming ?? pickNext(); upcoming = nil
        play(r, n, dissolve: false)
    }

    private func next(_ r: Rig) {
        if !queue.isEmpty { let q = queue.removeFirst(); return play(r, q, then: queue, dissolve: false) }
        let role = CL[clip]?.role ?? ""
        // segments of the current state end on its rest pose; anything else (a reaction, another state's clip) dissolves in
        let seamless = (CL[clip]?.state == stateName && ["rest", "beat", "enter"].contains(role)) || (clip == "bump" && stateName == "working")
        if seamless { return nextSegment(r) }
        play(r, restFor(stateName), dissolve: true)
    }

    private func event(_ r: Rig, _ n: String, _ kind: String) {
        let a = anchors(r)
        switch kind {
        case "contact": fx.append(FX(k: .glass, x: a.fx, y: a.fy + 6)); flexAt = nil; flex = 1; r.onHaptic?(.strong)
        case "apex":
            let cols = [Color(hex: 0xFFB020), Color(hex: 0xFF5FAE), Color(hex: 0xF4F5F6), Color(hex: 0xFF7A3D), Color(hex: 0x7FE0B0)]
            for i in 0..<22 {
                let ang = -Double.pi / 2 + rnd(-1.2, 1.2), sp = rnd(70, 180)
                fx.append(FX(k: .confetti, x: a.hx, y: a.hy + 10, vx: cos(ang) * sp, vy: sin(ang) * sp, r: rnd(0, TAU), vr: rnd(-6, 6), c: cols[i % 5]))
            }
        case "bonk": fx.append(FX(k: .bonk, x: a.hx - 8, y: a.hy)); r.onHaptic?(.strong)
        case "land" where n == "bump": if tool != nil { tool!.phase = "ride"; r.onHaptic?(.click) }
        case "launch" where n == "bump": if tool != nil { tool!.phase = "fly"; tool!.vx = 170; tool!.vy = -150; tool!.vr = 5; tool!.rot = 0 }
        case "land" where n == "approval_in": if card != nil { card!.phase = "ride"; r.onHaptic?(.strong) }
        case "launch" where n == "approval_allow": if card != nil { card!.phase = "fly"; card!.vx = 40; card!.vy = -420; card!.vr = 3.2 }
        case "drop" where n == "approval_deny": if card != nil { card!.phase = "drop"; card!.vx = -30; card!.vy = 20; card!.vr = -2.4 }
        default: break
        }
    }

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        if s == prev && prev != nil {
            if s == .dizzy && clip == "dizzy" && f >= Double(count("dizzy") - 1) { play(r, "dizzy") }   // shaken again
            return
        }
        stateName = name(s); upcoming = nil
        for k in of(stateName, "rest") + of(stateName, "enter") { StretchFrames.shared.preload(k) }
        if tool != nil && tool!.phase != "fly" { tool!.phase = "fly"; tool!.vx = 60; tool!.vy = -200; tool!.vr = 3; tool!.rot = 0 }
        if prev == .approval && s == .done && variant { return play(r, "approval_allow", then: ["done_in"]) }
        if prev == .approval && s != .approval && card?.phase == "ride" { card!.phase = "drop"; card!.vx = -30; card!.vy = 20; card!.vr = -2.4 }
        let enter = of(stateName, "enter")
        if prev == .sleep && s != .sleep {
            let fr = CL["popup"]?.frames ?? []
            let from = fr.firstIndex { $0.count > 6 && $0[6] >= -2.75 } ?? 0
            return play(r, "popup", from: Double(from), then: enter)
        }
        if s == .idle && ["react", "once"].contains(CL[clip]?.role ?? "") && clip != "dizzy" { queue = []; return }   // finish the reaction, then idle
        if s == .working { work = "work_read" }
        if s == .dizzy { return play(r, "dizzy") }
        if let e = enter.first { return play(r, e) }
        play(r, restFor(stateName))
    }

    func poke(_ r: Rig) { play(r, "poke") }
    func crown(_ r: Rig, _ delta: Double) {
        let was = neck.to
        neck.to = clamp(neck.to + delta * 0.05, 0.72, 1.55)
        crownIdle = 0
        if (was < 1.5 && neck.to >= 1.5) || (was > 0.75 && neck.to <= 0.75) { r.onHaptic?(.strong) }   // as far as it goes
    }
    private func stepNeck(_ r: Rig, _ dt: Double) {
        crownIdle += dt
        // a moment after the crown stops, it lets go: back to its own height, overshooting a little and wobbling
        if crownIdle > 0.6 && neck.to != 1 { if abs(neck.to - 1) > 0.15 { r.onHaptic?(.click) }; neck.to = 1 }
        let held = crownIdle <= 0.6, w = TAU * (held ? 3.0 : 2.3), z = held ? 0.9 : 0.27
        neck.v += (-w * w * (neck.k - neck.to) - 2 * z * w * neck.v) * dt
        neck.k = clamp(neck.k + neck.v * dt, 0.62, 1.7)
    }
    /// Where a point of the frame goes when it's stretched: above the seam it moves up or down with the head, below
    /// it it's stretched toward the bottom edge.
    private func neckY(_ y: Double) -> Double {
        let B = 242.0, S = seam, k = neck.k
        return y < S ? y - (k - 1) * (B - S) : B - k * (B - y)
    }
    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        push = (ax, ay, az)
        let e = max(0, sqrt(ax * ax + ay * ay + az * az) - 0.9)
        trauma = min(1, trauma + e * e * 0.03)
    }

    /// Where the frame is drawn: the gel's lean and squash, then the camera.
    private func viewTransform(_ t: Double) -> CGAffineTransform { gelTransform(t).concatenating(cameraTransform(t)) }

    /// The camera, about Noodle's face: zoomed in by the shake, shaken by its square, rolled, and never so far that the
    /// bottom of its body (cut at the frame's edge) comes into view.
    private func cameraTransform(_ t: Double) -> CGAffineTransform {
        let s = trauma * trauma
        func noise(_ a: Double, _ b: Double, _ c: Double) -> Double { sin(t * a) * 0.55 + sin(t * b + 1.3) * 0.3 + sin(t * c + 2.1) * 0.15 }
        let z = max(1, cam.z), rot = 6 * DEG * s * noise(53.1, 89.7, 131.3)
        var tx = 15 * s * noise(61.7, 97.3, 143.1), ty = 15 * s * noise(71.9, 109.1, 157.7)
        let C = rawFace
        let turn = CGAffineTransform(translationX: -C.x, y: -C.y).concatenating(CGAffineTransform(scaleX: z, y: z))
            .concatenating(CGAffineTransform(rotationAngle: rot)).concatenating(CGAffineTransform(translationX: C.x, y: C.y))
        // the stalk's bottom (x 40…158 on the bottom edge) stays below the screen; it can't slide in from the sides either
        let lowest = [40.0, 99, 158].map { CGPoint(x: $0, y: 242).applying(turn).y }.min()!
        ty = max(ty, 242 - lowest)
        tx = clamp(tx, -(z - 1) * 99 - 18, (z - 1) * 99 + 18)
        return turn.concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// The gel's lean, squash and push toward the glass this frame, anchored at the middle of the bottom edge.
    private func gelTransform(_ t: Double) -> CGAffineTransform {
        // shaken, it jiggles on top of the slosh: squash and stretch, and a lean, both fast
        let s = trauma * trauma
        let lean = clamp(gel.x, -34, 34) / 190 + 0.1 * s * sin(t * TAU * 5.1 + 1)
        let sy = (1 - clamp(gel.y, -28, 28) / 140) * (1 + 0.13 * s * sin(t * TAU * 6.3)), sx = 1 / sqrt(sy)
        let A = (x: 99.0, y: 242.0)
        // x' = A.x + sx·(x − A.x) − lean·(y − A.y) + slide,  y' = A.y + sy·(y − A.y)
        let body = CGAffineTransform(a: sx, b: 0, c: -lean, d: sy, tx: A.x - sx * A.x + lean * A.y + gel.x * 0.18, ty: A.y - sy * A.y)
        // pressed toward you it grows a little around its face
        let grow = 1 + clamp(gel.z, 0, 0.08), C = rawFace
        return body.concatenating(CGAffineTransform(translationX: C.x, y: C.y).scaledBy(x: grow, y: grow).translatedBy(x: -C.x, y: -C.y))
    }

    private func stepGel(_ r: Rig, _ dt: Double) {
        // a dead band so walking with your keys doesn't keep it wobbling; above it the watch's moves drive the gel
        func band(_ v: Double) -> Double { abs(v) < 0.12 ? 0 : v - (v > 0 ? 0.12 : -0.12) }
        let w = TAU * 1.6, wy = TAU * 2.1, wz = TAU * 3.0, z = 0.16
        gel.vx += (-w * w * gel.x - 2 * z * w * gel.vx - band(push.x) * 2000) * dt
        gel.vy += (-wy * wy * gel.y - 2 * z * wy * gel.vy - band(push.y) * 2000) * dt
        gel.vz += (-wz * wz * gel.z - 2 * 0.3 * wz * gel.vz - band(push.z) * 8) * dt
        gel.x += gel.vx * dt; gel.y += gel.vy * dt; gel.z += gel.vz * dt
        // the case: it can lean only so far before its hair hits the side
        if abs(gel.x) > 34 { gel.x = gel.x > 0 ? 34 : -34; gel.vx = -gel.vx * 0.35 }
        if abs(gel.y) > 28 { gel.y = gel.y > 0 ? 28 : -28; gel.vy = -gel.vy * 0.35 }
        // toward you it presses up to the glass and bounces back (a shake makes no rings and no taps: only it moves)
        if gel.z > 0.08 { gel.z = 0.08; gel.vz = -gel.vz * 0.3 }
        if gel.z < -0.06 { gel.z = -0.06; gel.vz = -gel.vz * 0.3 }
        stepCamera(dt)
    }

    private func stepCamera(_ dt: Double) {
        trauma = max(0, trauma - dt * 0.75)
        // the zoom follows the shake in, on a spring
        cam.vz += ((1 + 0.32 * trauma - cam.z) * 140 - cam.vz * 15) * dt; cam.z += cam.vz * dt
    }
    /// Your finger on the glass: the same liquid-glass ring as its knock, running out from where you touched.
    func touched(_ r: Rig, at pt: CGPoint) {
        guard !r.ao else { return }
        fx.append(FX(k: .glass, x: Double(pt.x), y: Double(pt.y))); flexAt = (Double(pt.x), Double(pt.y)); flex = 0.6
        r.onHaptic?(.click)
    }
    private var flexAt: (Double, Double)?
    func pet(_ r: Rig) { if clip != "pet" { play(r, "pet") } }
    func deny(_ r: Rig) { play(r, "approval_deny") }

    func hit(_ pt: CGPoint) -> Bool {
        let a = lastAnchors
        let dx = (Double(pt.x) - a.fx) / 56, dy = (Double(pt.y) - (a.fy - 24)) / 64
        return dx * dx + dy * dy < 1
    }
    private var lastAnchors = Anchors()

    func step(_ r: Rig, _ dt: Double) {
        if r.ao { return }                          // dimmed: it holds its frame (no decoding while you can barely see it)
        if let fd = fade { fade = fd.t + dt > fadeLength ? nil : (fd.image, fd.t + dt) }
        if fade == nil { fadeMove = nil }
        if let g = glideIn { glideIn = g.t + dt > Self.glide ? nil : (g.start, g.t + dt) }
        flex = max(0, flex - dt * 9)
        stepGel(r, dt)
        stepNeck(r, dt)
        // holding the card: the hold sequence follows your finger instead of time
        let holding = r.state == .approval && r.hold > 0.02 && CL[clip]?.state == "approval" && ["rest", "beat"].contains(CL[clip]?.role ?? "")
        if holding != held { fade = (shown, 0); fadeMove = nil; held = holding }
        if !held {
            let before = f
            f += dt * fps
            if let m = CL[clip], upcoming == nil, queue.isEmpty, f > Double(m.n) - 12,
               m.state == stateName && ["rest", "beat", "enter"].contains(m.role ?? "") {
                let n = pickNext(); upcoming = n; StretchFrames.shared.preload(n)
            }
            if let m = CL[clip] {
                for (kind, at) in m.events ?? [:] { for fr in at.list where before < Double(fr) && f >= Double(fr) { event(r, clip, kind) } }
                if f >= Double(m.n) {
                    if clip == "bump", let t = tool { work = ["read": "work_read", "search": "work_search", "edit": "work_edit", "run": "work_run"][t.kind] ?? "work_read" }
                    if clip == "approval_deny" { card = nil }
                    if clip == "dizzy" && r.state == .dizzy && queue.isEmpty { f = Double(m.n - 1) }    // it stays shaken off until the state moves on
                    else { next(r) }
                }
            }
        }
        // the work: a tool call from the session drops on its head
        if r.state == .working && clip.hasPrefix("work_") {
            demoCallT -= dt
            if !r.worlds.queue.isEmpty || (r.worlds.demo && demoCallT <= 0) { demoCallT = rnd(3.5, 6.5); play(r, "bump", dissolve: true) }
        }
        // effects
        let a = anchors(r); lastAnchors = a
        fog += ((a.press > 0.9 ? 1 : 0) - fog) * min(1, dt * (a.press > 0.9 ? 3 : 0.7))
        if CL[clip]?.state == "sleep" && ["rest", "beat"].contains(CL[clip]?.role ?? "") { zT -= dt; if zT <= 0 { zT = 1.5; fx.append(FX(k: .z, x: a.hx + 14, y: a.hy + 6)) } }
        for i in fx.indices {
            fx[i].t += dt
            if fx[i].k == .confetti { fx[i].x += fx[i].vx * dt; fx[i].y += fx[i].vy * dt; fx[i].vy += 260 * dt; fx[i].r += fx[i].vr * dt }
        }
        fx.removeAll { $0.t >= ($0.k == .z ? 2.6 : $0.k == .confetti ? 1.8 : $0.k == .glass ? 1.1 : 1.0) }
        for c in [\StretchStage.tool, \StretchStage.card] {
            guard var k = self[keyPath: c], k.phase == "fly" || k.phase == "drop" else { continue }
            k.x += k.vx * dt; k.y += k.vy * dt; k.vy += (k.phase == "drop" ? 900 : 380) * dt; k.rot += k.vr * dt
            self[keyPath: c] = k
        }
        if let t = tool, t.y < 20 || t.y > 300 || t.x > 290 { tool = nil }
        if let c = card, (c.phase == "fly" || c.phase == "drop") && (c.y < -80 || c.y > 340) { card = nil }
        if let c = card, c.phase != "fly" && c.phase != "drop" && r.state != .approval && !["approval_allow", "approval_deny"].contains(clip) { card = nil }
    }

    // MARK: drawing

    func draw(_ r: Rig, _ ctx0: GraphicsContext) {
        if !r.ao, let fr = StretchFrames.shared.frame(clipNow, frameNo(r)) { shown = fr }
        var ctx = ctx0
        if r.ao { ctx.opacity *= 0.5 }                                     // dimmed: its colors at half brightness
        // the glass flexes a hair toward you on a knock
        if flex > 0 {
            let s = 1 + 0.03 * flex, c = flexAt ?? (lastAnchors.fx, lastAnchors.fy)
            ctx.translateBy(x: c.0, y: c.1); ctx.scaleBy(x: s, y: s); ctx.translateBy(x: -c.0, y: -c.1)
        }
        view = viewTransform(r.t); ctx.concatenate(view)
        var now = ctx; now.concatenate(placeNow)
        if let fd = fade, let old = fd.image {
            var o = ctx
            if let m = fadeMove { o.concatenate(m.start.toward(m.end, ease(fd.t / fadeLength)).xf) }
            frame(o, old, r.t)
            if let cur = shown { now.opacity *= ease(fd.t / fadeLength); frame(now, cur, r.t) }
        } else if let cur = shown { frame(now, cur, r.t) }
    }

    /// One frame of Noodle. Shaken, a wave runs up its body: thin horizontal strips, each pushed sideways along a slow
    /// S-bend that travels upward, nothing at the base and most at the top of its hair.
    private func frame(_ ctx: GraphicsContext, _ im: CGImage, _ t: Double) {
        let rect = CGRect(x: 0, y: 0, width: 198, height: 242), image = Image(decorative: im, scale: 2)
        let A = 14 * trauma * trauma, k = neck.k, stretched = abs(k - 1) > 0.004
        guard A > 0.4 || stretched else { ctx.draw(image, in: rect); return }
        // thin bands of the frame, each moved (stretched below the seam, and the shake's wave) to where it goes
        let band = stretched ? 4.0 : 5.0, S = seam, cx = rawFace.x
        let thin = 1 / sqrt(k)                                       // the body keeps its volume: taller is thinner
        for i in 0..<Int((242 / band).rounded(.up)) {
            let y0 = Double(i) * band, y = y0 + band / 2, up = (242 - y) / 242
            let dx = A * up * sin(t * TAU * 4.5 - (242 - y) * TAU / 320)
            let below = y >= S, ky = below ? k : 1
            // thinner below the seam, easing in over the 30 pt under it so the neck has no step
            let sx = 1 + (thin - 1) * clamp((y - S) / 30, 0, 1) * (below ? 1 : 0)
            let top = neckY(y0), height = max(0.01, neckY(y0 + band) - top)
            var c = ctx
            c.clip(to: Path(CGRect(x: -40, y: top, width: 278, height: height + 0.6)))
            c.translateBy(x: cx + dx, y: top); c.scaleBy(x: sx, y: ky); c.translateBy(x: -cx, y: -y0)
            c.draw(image, in: rect)
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {
        let a = lastAnchors
        // the glass fogs where its face presses, and ripples like liquid glass where it knocks
        if fog > 0.02 {
            let g = Gradient(stops: [.init(color: Color(white: 0.93, opacity: 0.16 * fog), location: 0),
                                     .init(color: Color(white: 0.93, opacity: 0.07 * fog), location: 0.55),
                                     .init(color: Color(white: 0.93, opacity: 0), location: 1)])
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 198, height: 242)),
                     with: .radialGradient(g, center: CGPoint(x: a.fx, y: a.fy + 8), startRadius: 4, endRadius: 78))
        }
        for q in fx where q.k == .glass { glass(ctx, q) }
        for q in fx {
            switch q.k {
            case .confetti:
                var c = ctx; c.opacity = clamp(1.8 - q.t, 0, 1); c.translateBy(x: q.x, y: q.y); c.rotate(by: .radians(q.r))
                c.fill(Path(CGRect(x: -3, y: -1.5, width: 6, height: 3)), with: .color(q.c))
            case .bonk:
                var p = Path()
                for i in 0..<6 {
                    let th = -Double.pi / 2 + (Double(i) - 2.5) * 0.45, r0 = 8 + q.t * 10, r1 = 16 + q.t * 14
                    p.move(to: CGPoint(x: q.x + cos(th) * r0, y: q.y + sin(th) * r0)); p.addLine(to: CGPoint(x: q.x + cos(th) * r1, y: q.y + sin(th) * r1))
                }
                ctx.stroke(p, with: .color(.white.opacity(1 - q.t)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            case .z:
                ctx.faded(clamp(1 - q.t / 2.6, 0, 1)).draw(Text("z").font(.system(size: 10 + q.t * 4, weight: .semibold)).foregroundColor(Pal.gray),
                                                         at: CGPoint(x: q.x + q.t * 9, y: q.y - q.t * 16), anchor: .bottomLeading)
            case .glass: break
            }
        }
        // a tool call drops on its head and gets bonked off
        if var t = tool {
            let txt = ctx.resolve(Text(t.text).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundColor(t.kind == "run" ? Pal.amber : Pal.white))
            let w = txt.measure(in: CGSize(width: 180, height: 20)).width + 16, h = 20.0
            if t.phase == "fall" { let land = Double(CL["bump"]?.events?["land"]?.list.first ?? 6), k = clamp(f / land, 0, 1); t.x = a.hx; t.y = lerp(36, a.hy + 4, k * k); t.rot = 0 }
            if t.phase == "ride" { t.x = a.hx; t.y = a.hy + 4; t.rot = a.roll * DEG * 0.5 }
            tool = t
            cardBody(ctx, t, w, h) { c in
                c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 7), with: .color(Pal.card))
                c.stroke(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 7), with: .color(Color(hex: 0x2C3035)), lineWidth: 1)
                c.draw(txt, at: CGPoint(x: 8, y: 10), anchor: .leading)
            }
        }
        // the approval card rides on its hair; holding pushes it up; allow launches it, deny drops it
        if var c = card {
            let w = 152.0, h = 60.0
            if c.phase == "fall" { let land = Double(CL["approval_in"]?.events?["land"]?.list.first ?? 8), k = clamp(f / land, 0, 1); c.x = clamp(a.hx, 82, 116); c.y = lerp(38, a.hy + 6, k * k); c.rot = 0 }
            if c.phase == "ride" { c.x = clamp(a.hx, 82, 116); c.y = a.hy + 6; c.rot = a.roll * DEG * 0.6 }
            card = c
            let title = r.approvalTitle.isEmpty ? c.text : r.approvalTitle
            cardBody(ctx, c, w, h) { g in
                g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 13), with: .color(Pal.card))
                g.stroke(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 13), with: .color(Color(hex: 0x2C3035)), lineWidth: 1)
                g.draw(Text(title).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(Pal.white),
                       in: CGRect(x: 12, y: 10, width: w - 24, height: 18))
                g.draw(Text(r.hold > 0 ? "keep holding" : "hold to allow").font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(r.hold > 0 ? Pal.amber : Pal.gray), at: CGPoint(x: 12, y: 36), anchor: .leading)
                g.fill(Path(roundedRect: CGRect(x: 12, y: 47, width: w - 24, height: 3), cornerRadius: 1.5), with: .color(Color(hex: 0x26292D)))
                if r.hold > 0 { g.fill(Path(roundedRect: CGRect(x: 12, y: 47, width: (w - 24) * r.hold, height: 3), cornerRadius: 1.5), with: .color(Pal.amber)) }
            }
            if r.state == .approval {
                ctx.fillCircle(36, 210, 13, Color(hex: 0x1A1C1F))
                ctx.strokeLine(31.5, 205.5, 40.5, 214.5, Pal.gray, 1.8); ctx.strokeLine(40.5, 205.5, 31.5, 214.5, Pal.gray, 1.8)
            }
        }
    }

    /// Cards come in and leave from under the status row, as if from behind the bezel.
    private func cardBody(_ ctx0: GraphicsContext, _ c: Card, _ w: Double, _ h: Double, _ draw: (GraphicsContext) -> Void) {
        var ctx = ctx0
        ctx.clip(to: Path(CGRect(x: 0, y: 38, width: 198, height: 204)))
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: .radians(c.rot)); ctx.translateBy(x: -w / 2, y: -h)
        draw(ctx)
    }

    /// A knock on the glass: a ring of liquid glass runs out from the contact and refracts the frame under it. Each
    /// thin band of the ring redraws Noodle's frame magnified or shrunk around the contact (a lens ridge: magnified on
    /// the inner slope, compressed on the outer), with a highlight and a shade so it reads as glass even over black.
    private func glass(_ ctx: GraphicsContext, _ q: FX) {
        let k = q.t / 1.1
        guard k < 1, let im = shown else { return }
        let R = 16 + 150 * outC(k), wid = 16 + 26 * k, A = 0.16 * pow(1 - k, 1.5) * q.amp
        let image = Image(decorative: im, scale: 2), rect = CGRect(x: 0, y: 0, width: 198, height: 242)
        func ring(_ r0: Double, _ r1: Double) -> Path {
            var p = Path(); p.addEllipse(in: CGRect(x: q.x - r1, y: q.y - r1, width: 2 * r1, height: 2 * r1))
            if r0 > 0 { p.addEllipse(in: CGRect(x: q.x - r0, y: q.y - r0, width: 2 * r0, height: 2 * r0)) }
            return p
        }
        func lens(_ r0: Double, _ r1: Double, _ s: Double) {
            var c = ctx
            c.clip(to: ring(r0, r1), style: FillStyle(eoFill: true))
            c.translateBy(x: q.x, y: q.y); c.scaleBy(x: s, y: s); c.translateBy(x: -q.x, y: -q.y)
            c.concatenate(view)                                                    // the frame where the gel and camera have it
            c.draw(image, in: rect)
        }
        if k < 0.3 { lens(0, max(4, R - wid / 2), 1 + 0.05 * (1 - k / 0.3)) }      // the contact bulges toward you
        let bands = 12                                                             // 18 in the Lab; fewer on the watch
        for i in 0..<bands {
            let u0 = Double(i) / Double(bands), u1 = Double(i + 1) / Double(bands), um = (u0 + u1) / 2
            lens(max(0, R - wid / 2 + wid * u0), R - wid / 2 + wid * u1, 1 + A * cos(Double.pi * um))
        }
        let a = (1 - k) * (1 - k), r0 = max(0, R - wid / 2), r1 = R + wid / 2
        let g = Gradient(stops: [.init(color: .white.opacity(0), location: r0 / r1),
                                 .init(color: .white.opacity(0.16 * a), location: (r0 + 0.32 * (r1 - r0)) / r1),
                                 .init(color: .white.opacity(0), location: (r0 + 0.5 * (r1 - r0)) / r1),
                                 .init(color: .black.opacity(0.22 * a), location: (r0 + 0.7 * (r1 - r0)) / r1),
                                 .init(color: .black.opacity(0), location: 1)])
        ctx.fill(ring(r0, r1), with: .radialGradient(g, center: CGPoint(x: q.x, y: q.y), startRadius: 0, endRadius: r1), style: FillStyle(eoFill: true))
    }
}
