import SwiftUI

/// Peeps: eyes, on their own, on black. Everything is in how they move.
///   always: they move as a pair, the head following the gaze a little behind; a quick look stretches them along it; the
///   eye on the side they look to is a little bigger; a blink squashes them; they breathe
///   touch: they look at your finger and follow it while it's down · tap: one ripple of the glass runs out and bends
///   them as it passes; they startle · tap an eye: it winces shut, the other widens; poke them too often and they move
///   away, annoyed
///   crown up: bubbles of liquid glass rise from the bottom edge, flow round them and magnify them as they pass; they watch
///   them; tap one and it pops · crown down: a wind from the top pushes them down; they squint and flutter against it,
///   and spring back when it drops
///   shake: they slosh and squeeze; hard, dizzy: spiral eyes circling each other, swaying, under a ring of little glass
///   beads; then woozy, each eye on its own; then they shake it off
///   the screen's edges: pushed hard, they squash against them; left alone a while, they slip out past one and peek back
///   thinking: up and aside, mulling · working: reading, line by line, a blink at each tool call · subagents: three
///   little pairs of eyes circling them · done: a crouch, a hop, a landing · needs you: up close, knocking on the glass ·
///   blocked: they sag · sleep: shut, sinking a little, breathing slowly
/// Character rules: solid eyes, no pupils or shine, lids make every expression.
/// Battery: 60 frames a second only while something moves fast (`calm`), else 30; it draws the two eyes and their glow.
final class PeepsStage: Staged {
    static let shared = PeepsStage()

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 2.2, .dizzy: 4.2]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { false }
    /// Nothing moving fast for a second: 30 frames a second is enough.
    var calm: Bool { t - busyAt > 1.2 }

    private var off = (x: 0.0, y: 0.0, vx: 0.0, vy: 0.0)                // pushed off their place: taps, shakes, a peek, moods
    private var head = (x: 0.0, y: 0.0, vx: 0.0, vy: 0.0)               // following their gaze, a little behind
    private var gazeV = (x: 0.0, y: 0.0), lastGaze = (x: 0.0, y: 0.0)   // how fast the gaze moves
    private var squash = 0.0, squashAxisX = true                         // against an edge
    private var wob = [0.0, 0.0], wobV = [0.0, 0.0]                      // each eye's give when something hits it
    private var flinch = [0.0, 0.0]
    private var finger: CGPoint?
    private var look: CGPoint?, lookFor = 0.0                            // something they watch: your finger, a tap
    private var crownFor = 0.0, bubbleAcc = 0.0                          // the crown: how lately it turned; turns toward the next bubble
    private var wind = 0.0, windTo = 0.0, windPeak = 0.0                 // the wind from the top, 0…1
    private var lid = (s: 0.0, w: 0.0, i: 0.0), lidT = 0.0                // the lids as shown: sleepy, worried, intent
    private struct Bubble { var x, y, r, vx, vy, phase: Double; var pop: Double? = nil }
    private var bubbles: [Bubble] = []
    private struct Drop { var x, y, vx, vy, t: Double }
    private var drops: [Drop] = []
    private var startle = 0.0, press = 0.0, pressBase = 0.0, knock = 0.0
    private var orbit = 0.0, orbitA = 0.0, halo = 0.0, shakeOff = 0.0
    private var pokes: [Double] = [], annoyed = 0.0, annoyedSide = 1.0, lastTouch = CGPoint(x: 99, y: 112)
    private var peek: (side: Double, t: Double)?, idleFor = 0.0
    private var doneT: Double?, dizzyT: Double?
    private var nextTool = 0.6, readT = 0.0
    private var minis = 0.0, minisA = 0.0
    private struct Ring { var x, y, t: Double; var amp = 1.0; var passed = [false, false] }
    private var rings: [Ring] = []
    private var eyes = (l: CGPoint(x: 55, y: 112), r: CGPoint(x: 143, y: 112), w: 36.0, h: 54.0)
    private var push = (x: 0.0, y: 0.0, z: 0.0), trauma = 0.0
    private var t = 0.0, busyAt = 0.0
    private var state: ChumsState = .idle

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        state = s; idleFor = 0; peek = nil
        doneT = s == .done ? 0 : nil
        dizzyT = s == .dizzy ? 0 : nil
        if s == .dizzy { orbit = 1; halo = 1 } else { halo = 0 }
        if s == .needs { knock = 0 }
        readT = 0
    }

    func step(_ r: Rig, _ dt0: Double) {
        let dt = min(dt0, 0.05)
        t += dt
        guard !r.ao else { return }
        stepPair(r, dt)
        stepActing(r, dt)
        stepRings(dt)
        stepBubbles(r, dt)
        let busy = finger != nil || crownFor > 0 || trauma > 0.02 || !rings.isEmpty || dizzyT != nil || (doneT ?? 9) < 1.2
            || abs(off.vx) + abs(off.vy) > 30 || peek != nil || minis > 0.02 || !bubbles.isEmpty || !drops.isEmpty || wind > 0.01
            || state == .listening || state == .speaking
        if busy { busyAt = t }
    }

    private func band(_ v: Double) -> Double { abs(v) < 0.12 ? 0 : v - (v > 0 ? 0.12 : -0.12) }
    private func cross(_ now: Double, _ dt: Double, _ at: Double) -> Bool { now - dt < at && now >= at }

    private func stepPair(_ r: Rig, _ dt: Double) {
        // the crown's wind builds while it turns and dies down after; when a strong one drops, they blink it off
        crownFor = max(0, crownFor - dt)
        windTo *= exp(-dt * 1.3)
        wind += (windTo - wind) * min(1, dt * 6)
        windPeak = max(windPeak, wind)
        if windPeak > 0.45 && wind < 0.12 { windPeak = 0; r.startBlink(true) }
        if wind < 0.01 { windPeak = min(windPeak, wind) }
        // the head follows the gaze, a little behind
        let gx = r.gaze.x, gy = r.gaze.y, hw = TAU * 2.2
        let ivx = (gx - lastGaze.x) / max(dt, 0.001), ivy = (gy - lastGaze.y) / max(dt, 0.001)
        gazeV = (lerp(gazeV.x, ivx, min(1, dt * 30)), lerp(gazeV.y, ivy, min(1, dt * 30)))
        lastGaze = (gx, gy)
        head.vx += (-hw * hw * (head.x - gx * 7) - 2 * 0.55 * hw * head.vx) * dt
        head.vy += (-hw * hw * (head.y - gy * 5) - 2 * 0.55 * hw * head.vy) * dt
        head.x += head.vx * dt; head.y += head.vy * dt

        startle = max(0, startle - dt * 2.5)
        trauma = max(0, trauma - dt * 0.75)
        press = max(0, press - dt * 2.2)
        pressBase += ((state == .needs ? 0.4 : 0) - pressBase) * min(1, dt * 3)
        annoyed = max(0, annoyed - dt)
        lookFor = max(0, lookFor - dt)
        shakeOff = max(0, shakeOff - dt * 2.2)
        orbit = max(0, orbit - dt * 0.42)
        orbitA += dt * TAU * 1.4 * orbit
        for i in 0..<2 {
            flinch[i] = max(0, flinch[i] - dt * 2.2)
            let w = TAU * 4.2
            wobV[i] += (-w * w * wob[i] - 2 * 0.22 * w * wobV[i]) * dt
            wob[i] = clamp(wob[i] + wobV[i] * dt, -0.2, 0.2)
        }

        // where they want to be: their place, or past an edge, or away from your finger, a mood's place, a little downhill
        var rx = clamp(r.W.padX, -1, 1) * 8, ry = 0.0
        let span = Double(eyes.r.x - eyes.l.x) / 2 + eyes.w / 2
        if let p = peek {
            if p.t < 1.6 { rx = p.side * (99 + span + 10) }                     // out
            else if p.t < 4.6 { rx = p.side * (99 + span - eyes.w * 0.95) }     // one eye back in
        }
        switch state {
        case .thinking: rx += sin(t * 0.7) * 4; ry = -4 + cos(t * 0.5) * 2    // mulling, drifting
        case .blocked: ry = 7                                                // sagging
        case .sleep: ry = 12 + sin(t * TAU / 5) * 1.5
        default: break
        }
        if annoyed > 0 { rx = annoyedSide * 34; ry = 8 }
        ry += wind * 26                                                      // the wind pushes them down
        if let d = dizzyT, orbit > 0 { rx += sin(d * 3.1) * 9 * orbit; ry += sin(d * 6.2) * 4 * orbit }   // swaying, a figure of eight
        let w = TAU * (peek == nil ? 1.4 : 1.1), z = 0.45
        off.vx += (-w * w * (off.x - rx) - 2 * z * w * off.vx - band(push.x) * 1500) * dt
        off.vy += (-w * w * (off.y - ry) - 2 * z * w * off.vy - band(push.y) * 1500) * dt
        off.x += off.vx * dt; off.y += off.vy * dt
        // the screen's edges: they squash against them and come back (not while peeking past one)
        let maxX = 99 - span - 2, maxY = 112 - eyes.h * 0.62 - 30
        if peek == nil {
            if abs(off.x) > maxX { let v = abs(off.vx); off.x = off.x > 0 ? maxX : -maxX; off.vx = -off.vx * 0.3; if v > 140 { hitEdge(r, v, x: true) } }
            if abs(off.y) > maxY { let v = abs(off.vy); off.y = off.y > 0 ? maxY : -maxY; off.vy = -off.vy * 0.3; if v > 140 { hitEdge(r, v, x: false) } }
        }
        squash = max(0, squash - dt * 2.6)
    }

    private func hitEdge(_ r: Rig, _ v: Double, x: Bool) {
        squash = min(0.24, v / 1000); squashAxisX = x
        if trauma < 0.15 { r.onHaptic?(v > 500 ? .strong : .click) }
    }

    /// What each state does beyond the rig's lids and gaze.
    private func stepActing(_ r: Rig, _ dt: Double) {
        if let d = doneT { doneT = d + dt }
        if let d = dizzyT {
            dizzyT = d + dt
            if cross(d + dt, dt, 2.1) { halo = 0; r.startBlink() }                 // the spirals stop: woozy
            if cross(d + dt, dt, 3.5) { shakeOff = 1; r.startBlink(true) }         // and they shake it off
        }
        // needs you: up close against the glass, knocking every few seconds, with a tap on the wrist
        if state == .needs {
            let was = knock; knock += dt
            if knock >= 3.2 { knock = 0 }
            if was < 0.2 && knock >= 0.2 {
                press = 1; off.vy -= 60
                rings.append(Ring(x: Double(eyes.l.x + eyes.r.x) / 2, y: Double(eyes.l.y), t: 0, amp: 0.8)); r.onHaptic?(.strong)
            }
        } else { knock = 0 }
        // working: reading, a line at a time; each tool call, a blink and a small nod
        readT = state == .working ? readT + dt : 0
        nextTool -= dt
        if nextTool <= 0 && (!r.worlds.queue.isEmpty || state == .working), let call = r.worlds.nextEvent(r) {
            nextTool = r.worlds.queue.isEmpty ? rnd(1.6, 2.6) : 0.6
            if call.kind != .stop { r.startBlink(); off.vy += 70 }
        }
        // subagents: little eyes circling them
        minis += ((state == .subagents ? 1 : 0) - minis) * min(1, dt * 2.5)
        minisA += dt * 0.9
        // left alone a while: out past an edge, then one eye peeks back in, looks around, and they come back
        idleFor = state == .idle && finger == nil && crownFor <= 0 ? idleFor + dt : 0
        if peek == nil && idleFor > 24 && Double.random(in: 0..<1) < dt * 0.2 { peek = (Bool.random() ? -1 : 1, 0); idleFor = 0 }
        if var p = peek {
            p.t += dt; peek = p.t > 6.4 ? nil : p
            if cross(p.t, dt, 2.3) { r.saccade(-p.side * 0.9, 0.05); r.gaze.fixLeft = 1.3 }
            if cross(p.t, dt, 3.5) { r.startBlink(true) }
            if cross(p.t, dt, 4.1) { r.saccade(-p.side * 0.4, 0.3); r.gaze.fixLeft = 1 }
        }
    }

    private func stepRings(_ dt: Double) {
        for j in rings.indices {
            rings[j].t += dt
            let R = ringRadius(rings[j]), a = 1 - min(1, rings[j].t / 0.9)
            for (i, c) in [eyes.l, eyes.r].enumerated() where rings[j].t > 0 && !rings[j].passed[i] && hypot(Double(c.x) - rings[j].x, Double(c.y) - rings[j].y) < R {
                rings[j].passed[i] = true; wobV[i] += 1.6 * a * rings[j].amp
            }
        }
        rings.removeAll { $0.t >= 0.9 }
    }
    private func ringRadius(_ g: Ring) -> Double { 6 + 140 * outC(clamp(g.t / 0.9, 0, 1)) }

    // MARK: input

    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        push = (ax, ay, az)
        let e = max(0, sqrt(ax * ax + ay * ay + az * az) - 0.9)
        trauma = min(1, trauma + e * e * 0.03)
    }

    /// The crown: turned up, bubbles; turned down, wind.
    func crown(_ r: Rig, _ delta: Double) {
        crownFor = 1.2; idleFor = 0; peek = nil; busyAt = t
        if delta > 0 {
            bubbleAcc += delta
            while bubbleAcc >= 2.2 { bubbleAcc -= 2.2; spawnBubble() }
        } else {
            bubbleAcc = 0
            windTo = min(1, windTo - delta * 0.12)
        }
    }

    // MARK: bubbles

    /// A bubble comes up from below the bottom edge: a few, and big.
    private func spawnBubble() {
        guard bubbles.filter({ $0.pop == nil }).count < 5 else { return }
        let u = Double.random(in: 0..<1), r = 15 + 11 * u * u
        bubbles.append(Bubble(x: rnd(22, 176), y: 242 + r + rnd(0, 8), r: r, vx: 0, vy: -rise(r), phase: rnd(0, TAU)))
    }
    /// How fast a bubble of radius `r` rises: big ones faster.
    private func rise(_ r: Double) -> Double { 26 + r * 2.2 }

    private func stepBubbles(_ r: Rig, _ dt: Double) {
        for i in bubbles.indices where bubbles[i].pop != nil { bubbles[i].pop! += dt }
        bubbles.removeAll { ($0.pop ?? 0) > 0.18 }
        for i in drops.indices { drops[i].t += dt; drops[i].x += drops[i].vx * dt; drops[i].y += drops[i].vy * dt; drops[i].vy += 240 * dt }
        drops.removeAll { $0.t > 0.4 }
        guard !bubbles.isEmpty else { return }
        for i in bubbles.indices where bubbles[i].pop == nil {
            var b = bubbles[i]
            // rising with a sway, the wind holding them back or blowing them down
            b.vx += (sin(t * 1.7 + b.phase) * 14 - b.vx) * min(1, dt * 2)
            b.vy += (-rise(b.r) + wind * (rise(b.r) + 90) - b.vy) * min(1, dt * 2.5)
            b.x += b.vx * dt; b.y += b.vy * dt
            b.x = clamp(b.x, b.r * 0.6, 198 - b.r * 0.6)
            bubbles[i] = b
        }
        // bubbles don't overlap: each pair pushed apart
        for i in bubbles.indices where bubbles[i].pop == nil {
            for j in (i + 1)..<bubbles.count where bubbles[j].pop == nil {
                let dx = bubbles[j].x - bubbles[i].x, dy = bubbles[j].y - bubbles[i].y, d = hypot(dx, dy), m = bubbles[i].r + bubbles[j].r + 1
                guard d < m, d > 0.0001 else { continue }
                let k = (m - d) / d * 0.5
                bubbles[i].x -= dx * k; bubbles[i].y -= dy * k; bubbles[j].x += dx * k; bubbles[j].y += dy * k
            }
        }
        bubbles.removeAll { $0.y < -$0.r - 6 || $0.y > 262 + $0.r }
        // they watch the biggest one near them
        let c = CGPoint(x: Double(eyes.l.x + eyes.r.x) / 2, y: Double(eyes.l.y + eyes.r.y) / 2)
        if let b = bubbles.filter({ $0.pop == nil && $0.y < 236 && $0.y > 20 }).max(by: { $0.r / (hypot($0.x - c.x, $0.y - c.y) + 40) < $1.r / (hypot($1.x - c.x, $1.y - c.y) + 40) }) {
            look = CGPoint(x: b.x, y: b.y); lookFor = max(lookFor, 0.35)
        }
    }

    /// A bubble bursts: it flashes out, and a few drops fly off.
    private func burst(_ i: Int) {
        let b = bubbles[i]
        bubbles[i].pop = 0
        for k in 0..<4 {
            let a = rnd(0, TAU) + Double(k) * TAU / 4
            drops.append(Drop(x: b.x + cos(a) * b.r, y: b.y + sin(a) * b.r, vx: cos(a) * rnd(40, 70), vy: sin(a) * rnd(40, 70) - 20, t: 0))
        }
    }

    func touched(_ r: Rig, at pt: CGPoint) {
        finger = pt; lastTouch = pt; busyAt = t
        look = pt; lookFor = 0.6
        idleFor = 0; peek = nil
        // a bubble under the finger pops
        if let i = bubbles.firstIndex(where: { $0.pop == nil && hypot($0.x - Double(pt.x), $0.y - Double(pt.y)) < $0.r + 8 }) {
            burst(i); r.onHaptic?(.click); return
        }
        // on an eye: it winces shut (the rig taps the wrist when the finger lifts), the other one widens
        for (i, c) in [eyes.l, eyes.r].enumerated() where abs(pt.x - c.x) < eyes.w * 0.8 && abs(pt.y - c.y) < eyes.h * 0.62 {
            flinch[i] = 1; wob[i] = -0.14; wobV[i] = 0
            return
        }
        // anywhere else: a ripple of the glass runs out and bends them as it passes; they startle, away from it
        rings.append(Ring(x: pt.x, y: pt.y, t: 0))
        startle = 1
        let cx = Double(eyes.l.x + eyes.r.x) / 2, cy = Double(eyes.l.y + eyes.r.y) / 2
        let dx = cx - Double(pt.x), dy = cy - Double(pt.y), d = max(20, hypot(dx, dy))
        off.vx += dx / d * 4000 / (d + 60); off.vy += dy / d * 4000 / (d + 60)
        r.onHaptic?(.click)
    }
    /// They follow your finger while it's down.
    func dragged(_ r: Rig, at pt: CGPoint) { finger = pt; look = pt; lookFor = 0.6; busyAt = t }
    func released(_ r: Rig) { finger = nil; lookFor = min(lookFor, 0.35) }
    /// Poked: four times in three seconds and they move off to the other side, annoyed, for a few seconds.
    func poke(_ r: Rig) {
        pokes = pokes.filter { t - $0 < 3 } + [t]
        if pokes.count >= 4 { pokes = []; annoyed = 3.2; annoyedSide = lastTouch.x < 99 ? 1 : -1; r.saccade(-annoyedSide * 0.7, 0) }
    }
    func pet(_ r: Rig) {}
    func deny(_ r: Rig) {}

    func hit(_ pt: CGPoint) -> Bool {
        let lx = Double(eyes.l.x), rx = Double(eyes.r.x), ly = Double(eyes.l.y), ry = Double(eyes.r.y)
        let hw = abs(rx - lx) / 2 + eyes.w * 0.6 + 8, hh = eyes.h * 0.6 + 10
        return abs(Double(pt.x) - (lx + rx) / 2) < hw && abs(Double(pt.y) - (ly + ry) / 2) < hh
    }

    // MARK: drawing

    /// One eye this frame: where, its pose, and what moves it, in the order it's applied.
    private struct Eye {
        var p: CGPoint, pose: EyePose, side: Double
        var lens: (dx: Double, dy: Double, angle: Double, s: Double)          // a ripple passing through it
        var stretch: (angle: Double, s: Double)                               // a quick look
        var rot: Double, sx: Double, sy: Double
    }
    private struct Frame { var eye: [Eye]; var style: Characters.EyeStyle; var w: Double, h: Double }

    private func frame(_ r: Rig) -> Frame {
        let p = r.pose(raw: true)
        let pr = max(press, pressBase)
        let s = p.scale * 1.32 * (1 + 0.16 * pr)
        let w = 27 * s, h = 41 * s, sep = 33 * s

        // done: a crouch, a hop, a landing, a smaller hop, a settle
        var hopY = 0.0, hopS = 0.0                                          // hopS: + stretched tall, − squashed
        if let d = doneT {
            if d < 0.14 { hopS = -0.13 * sin(Double.pi * d / 0.28) }
            else if d < 0.52 { let u = (d - 0.14) / 0.38; hopY = -22 * sin(Double.pi * u); hopS = 0.09 * cos(Double.pi * u) }
            else if d < 0.68 { hopS = -0.11 * sin(Double.pi * (d - 0.52) / 0.16) }
            else if d < 0.92 { let u = (d - 0.68) / 0.24; hopY = -8 * sin(Double.pi * u); hopS = 0.04 * cos(Double.pi * u) }
            else if d < 1.04 { hopS = -0.05 * sin(Double.pi * (d - 0.92) / 0.12) }
        }
        let dz = dizzyT ?? 9
        let wooze = dz < 2.1 ? 0 : clamp((dz - 2.1) / 0.3, 0, 1) * clamp((3.7 - dz) / 0.3, 0, 1)
        let c = CGPoint(x: p.cx + off.x + head.x + sin(t * TAU * 8) * 5 * shakeOff, y: p.cy + off.y + head.y + hopY)
        let rot = p.tilt + (dizzyT != nil ? sin(dz * 3.1) * 0.2 * orbit : 0) + sin(t * 1.6) * 0.12 * wooze
        let ca = cos(rot), sa = sin(rot), R = 6 * orbit
        var pos = [CGPoint(x: c.x - sep * ca + cos(orbitA) * R, y: c.y - sep * sa + sin(orbitA) * R),
                   CGPoint(x: c.x + sep * ca - cos(orbitA) * R, y: c.y + sep * sa - sin(orbitA) * R)]
        pos[0].y += sin(t * 2.1) * 5 * wooze; pos[1].y += sin(t * 2.1 + 2.2) * 5 * wooze          // woozy: out of step
        eyes = (pos[0], pos[1], w, h)

        var e = p.eye
        // your finger, or a tap: they look at it
        if let lk = look, lookFor > 0 {
            let dx = Double(lk.x - c.x), dy = Double(lk.y - c.y), dd = max(1, hypot(dx, dy)), k = min(1, lookFor / 0.3), reach = min(1, dd / 50)
            e.gx = lerp(e.gx, dx / dd * reach * 0.95, k); e.gy = lerp(e.gy, dy / dd * reach * 0.85, k)
        }
        // working: reading a line left to right, then back to the start of the next, a few lines down, again
        if state == .working && readT > 0.6 {
            let line = 1.25, u = (readT - 0.6).truncatingRemainder(dividingBy: line) / line, n = Int((readT - 0.6) / line) % 4
            let x = u < 0.82 ? lerp(-0.55, 0.55, u / 0.82) : lerp(0.55, -0.55, (u - 0.82) / 0.18)
            e.gx = lerp(e.gx, x, 0.85); e.gy = lerp(e.gy, 0.15 + Double(n) * 0.12, 0.85)
        }
        e.wide = max(e.wide, startle, pr * 0.5)
        if trauma > 0.6 && state != .dizzy { e.intent = 1 }                 // shaken hard: squeezed, before the dizzy
        if annoyed > 0 { e.worried = max(e.worried, 0.8); e.intent = max(e.intent, 0.4) }
        e.sleepy = max(e.sleepy, 0.55 * wooze, 0.38 * wind)                 // squinting against the wind, looking up into it
        e.intent = max(e.intent, 0.9 * wind)
        // the lids, decisive as an animator would key them: each one off or clearly on, never a sliver (a sliver of lid
        // reads as a flat on the eye), and a change takes a fifth of a second
        let fdt = min(0.05, max(0, t - lidT)), kl = min(1, fdt * 14)
        lidT = t
        func snap(_ v: Double, _ off: Double, _ least: Double) -> Double { v < off ? 0 : max(v, least) }
        lid.s += (snap(e.sleepy, 0.25, 0.42) - lid.s) * kl
        lid.w += (snap(e.worried, 0.2, 0.4) - lid.w) * kl
        lid.i += (snap(e.intent, 0.45, 0.65) - lid.i) * kl
        e.sleepy = lid.s; e.worried = lid.w; e.intent = lid.i
        if wind > 0.02 { e.gy = lerp(e.gy, -0.55, wind * 0.7); e.gx *= 1 - wind * 0.5 }

        let flutter = wind * wind
        let breath = state == .sleep ? 0.028 * sin(t * TAU / 5) : 0.012 * sin(t * TAU / 3.6)
        let blinkS = 0.1 * (1 - clamp(e.open, 0, 1))                        // a blink squashes them
        let gSpeed = hypot(gazeV.x, gazeV.y), stretch = (angle: atan2(gazeV.y * 0.8, gazeV.x), s: min(0.14, gSpeed * 0.01))
        let bx = squashAxisX ? 1 - squash : 1 + squash * 0.6, by = squashAxisX ? 1 + squash * 0.6 : 1 - squash
        var out: [Eye] = []
        for i in 0..<2 {
            let side = i == 0 ? -1.0 : 1.0
            var ei = e
            if wooze > 0 {                                                  // woozy: each eye wandering its own way
                ei.gx = lerp(e.gx, sin(t * (i == 0 ? 1.3 : 1.1) + Double(i) * 2) * 0.7, wooze)
                ei.gy = lerp(e.gy, cos(t * (i == 0 ? 1.7 : 1.5) + Double(i)) * 0.45, wooze)
            }
            ei.open = min(ei.open, clamp(1 - flinch[i] / 0.55, 0, 1))      // shut tight, then opening
            ei.wince = ei.wince || flinch[i] > 0.45
            ei.wide = max(ei.wide, flinch[1 - i] * 0.8)
            let persp = 1 + 0.06 * ei.gx * side                             // the eye on the side they look to, a bit bigger
            let sx = bx * (1 + wob[i]) * persp * (1 + blinkS) * (1 - hopS * 0.6) * (1 + 0.05 * wind)
            let sy = by * (1 - wob[i]) * persp * (1 + breath) * (1 + hopS) * (1 - 0.1 * wind + 0.025 * flutter * sin(t * TAU * 13 + Double(i) * 1.7))
            out.append(Eye(p: pos[i], pose: ei, side: side, lens: lens(pos[i], (w + h) / 4), stretch: stretch, rot: rot, sx: sx, sy: sy))
        }
        let style = Characters.EyeStyle(y: 0, gap: 0, w: w, h: h, n: lerp(3, 2.2, p.c), color: p.amber > 0.5 ? Pal.amber : Pal.white,
                                        rx: 9 * s, ry: 7 * s, stroke: false, pulse: p.pulse)
        return Frame(eye: out, style: style, w: w, h: h)
    }

    /// What a ripple does to an eye at `p` (about `re` in radius): the ripple is a ridge in the glass running out from the
    /// tap; at its crest, what's under it spreads out along the way it runs. The eye is moved and stretched by where the
    /// ridge puts its near and far edges, so it bends smoothly however the ridge crosses it.
    private func lens(_ p: CGPoint, _ re: Double) -> (dx: Double, dy: Double, angle: Double, s: Double) {
        var dx = 0.0, dy = 0.0, angle = 0.0, s = 1.0
        for g in rings where g.t > 0 {
            let k = g.t / 0.9, a = 0.3 * pow(1 - k, 1.5) * g.amp, R = ringRadius(g), W = 12 + 10 * k
            let vx = Double(p.x) - g.x, vy = Double(p.y) - g.y, d = max(0.001, hypot(vx, vy))
            func disp(_ x: Double) -> Double { let u = x - R; return a * u * exp(-(u / W) * (u / W)) }
            let d0 = d - re, d1 = d + re, m0 = disp(d0), m1 = disp(d1)
            let mean = (m0 + m1) / 2, sr = ((d1 + m1) - (d0 + m0)) / (d1 - d0)
            dx += vx / d * mean; dy += vy / d * mean
            if abs(sr - 1) > abs(s - 1) { s = sr; angle = atan2(vy, vx) }
        }
        return (dx, dy, angle, s)
    }

    /// A context placed on eye `i`: moved, stretched and turned as this frame says, ready to draw at its center.
    private func place(_ ctx: GraphicsContext, _ f: Frame, _ i: Int) -> GraphicsContext {
        let e = f.eye[i]
        var g = ctx
        g.translateBy(x: e.p.x + e.lens.dx, y: e.p.y + e.lens.dy)
        if abs(e.lens.s - 1) > 0.002 { g.rotate(by: .radians(e.lens.angle)); g.scaleBy(x: e.lens.s, y: 1); g.rotate(by: .radians(-e.lens.angle)) }
        if e.stretch.s > 0.004 { g.rotate(by: .radians(e.stretch.angle)); g.scaleBy(x: 1 + e.stretch.s, y: 1 - e.stretch.s * 0.5); g.rotate(by: .radians(-e.stretch.angle)) }
        g.rotate(by: .radians(e.rot)); g.scaleBy(x: e.sx, y: e.sy)
        g.translateBy(x: e.pose.gx * f.style.rx + e.pose.tremorX * 0.5, y: e.pose.gy * f.style.ry + e.pose.tremorY * 0.5)
        return g
    }

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        let f = frame(r)
        if r.ao { for i in 0..<2 { Characters.drawEye(place(ctx.faded(0.5), f, i), f.style, f.eye[i].pose, side: f.eye[i].side) }; return }
        drawEyes(ctx, f)
        // the crown's bubbles: liquid glass, passing over them as lenses; a popped one flashes out
        var lenses = 0
        for b in bubbles {
            if let k = b.pop.map({ $0 / 0.18 }) {
                let rr = b.r * (1 + 0.5 * k)
                ctx.stroke(Path(ellipseIn: CGRect(x: b.x - rr, y: b.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(.white.opacity(0.5 * (1 - k))), lineWidth: 1)
                continue
            }
            let wv = 0.035 * sin(t * 6.5 + b.phase), sx = 1 + wv, sy = (1 - wv) * (1 + min(0.08, abs(b.vy) / 1500))
            if lenses < 4, f.eye.contains(where: { abs(b.x - Double($0.p.x)) < b.r + f.w * 0.75 && abs(b.y - Double($0.p.y)) < b.r + f.h * 0.7 }) {
                lenses += 1
                magnify(ctx, f, x: b.x, y: b.y, r: b.r, sx: sx, sy: sy, mag: 1.25)
            }
            glassRim(ctx, x: b.x, y: b.y, r: b.r, sx: sx, sy: sy)
        }
        for d in drops { ctx.faded(1 - d.t / 0.4).fillCircle(d.x, d.y, 1.1, Color(white: 0.85)) }
        // the ripple's crest, faint: what shows is how it bends them
        for g in rings where g.t > 0 {
            let k = g.t / 0.9, a = pow(1 - k, 2) * g.amp, rr = ringRadius(g)
            ctx.stroke(Path(ellipseIn: CGRect(x: g.x - rr, y: g.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(.white.opacity(0.16 * a)), lineWidth: 1)
        }
        // subagents: three little pairs of eyes circling them, the far side smaller and dimmer
        if minis > 0.02 {
            let c = CGPoint(x: Double(f.eye[0].p.x + f.eye[1].p.x) / 2, y: Double(f.eye[0].p.y + f.eye[1].p.y) / 2)
            for k in 0..<3 {
                let a = minisA + Double(k) * TAU / 3, depth = sin(a), x = c.x + cos(a) * 76 * minis, y = c.y + depth * 44 * minis
                let size = (7 + 2 * depth) * minis
                var g = ctx.faded(minis * (0.55 + 0.45 * (depth + 1) / 2)); g.translateBy(x: x, y: y)
                let st = Characters.EyeStyle(y: 0, gap: size * 0.62, w: size * 0.75, h: size * 1.1, n: 2.6, color: Pal.white, rx: 1, ry: 1, stroke: false, pulse: 0)
                Characters.drawEyePair(g, st, .neutral(gx: -cos(a) * 0.6, gy: -depth * 0.4))
            }
        }
        // dizzy: a ring of little glass beads circling over them
        if halo > 0, let d = dizzyT {
            let k = clamp(d / 0.3, 0, 1)
            let cx = Double(f.eye[0].p.x + f.eye[1].p.x) / 2, cy = max(34, Double(min(f.eye[0].p.y, f.eye[1].p.y)) - f.h * 0.55 - 10)
            for i in 0..<5 {
                let a = t * TAU * 1.1 + Double(i) * TAU / 5, depth = sin(a), x = cx + cos(a) * 28 * k, y = cy + depth * 6, rad = 3 + 1 * depth
                bead(ctx.faded(k * (0.55 + 0.45 * (depth + 1) / 2)), x: x, y: y, r: rad)
            }
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}

    /// Their glow (light from them, not shine on them), then the eyes.
    private func drawEyes(_ ctx: GraphicsContext, _ f: Frame) {
        let tint = f.style.color == Pal.amber ? Pal.amber : Color(hex: 0xD6E6FF), R = f.h * 0.9
        for i in 0..<2 {
            place(ctx, f, i).fill(Path(ellipseIn: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)),
                                  with: .radialGradient(Gradient(colors: [tint.opacity(0.16), tint.opacity(0.04), .clear]), center: .zero, startRadius: 0, endRadius: R))
        }
        for i in 0..<2 { Characters.drawEye(place(ctx, f, i), f.style, f.eye[i].pose, side: f.eye[i].side) }
    }

    /// Glass that magnifies what's under it: the eyes redrawn, scaled about its center, inside it.
    private func magnify(_ ctx: GraphicsContext, _ f: Frame, x: Double, y: Double, r: Double, sx: Double, sy: Double, mag: Double) {
        var c = ctx
        let shape = Path(ellipseIn: CGRect(x: x - r * sx, y: y - r * sy, width: 2 * r * sx, height: 2 * r * sy))
        c.clip(to: shape)
        c.fill(shape, with: .color(.black))
        c.translateBy(x: x, y: y); c.scaleBy(x: mag, y: mag); c.translateBy(x: -x, y: -y)
        drawEyes(c, f)
    }

    /// A bubble's glass: clear in the middle, a little shade inside its edge, a bright edge with a faint split of colour
    /// (glass bending light), a soft highlight high on the left and a small glint low on the right.
    private func glassRim(_ ctx: GraphicsContext, x: Double, y: Double, r: Double, sx: Double, sy: Double) {
        var c = ctx
        c.translateBy(x: x, y: y); c.scaleBy(x: sx, y: sy)
        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        c.fill(circle, with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.025), location: 0), .init(color: .white.opacity(0.035), location: 0.62),
                                                             .init(color: .black.opacity(0.3), location: 0.88), .init(color: .white.opacity(0.42), location: 1)]),
                                             center: .zero, startRadius: 0, endRadius: r))
        c.stroke(circle, with: .color(.white.opacity(0.28)), lineWidth: 0.7)
        if r > 6 {
            c.stroke(Path(ellipseIn: CGRect(x: -r - 0.5, y: -r - 0.6, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0x8FE9FF).opacity(0.18)), lineWidth: 0.6)
            c.stroke(Path(ellipseIn: CGRect(x: -r + 0.5, y: -r + 0.6, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0xFFA3D9).opacity(0.12)), lineWidth: 0.6)
        }
        var arc = Path(); arc.addArc(center: .zero, radius: r * 0.68, startAngle: .degrees(198), endAngle: .degrees(252), clockwise: false)
        c.stroke(arc, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: max(1, r * 0.12), lineCap: .round))
        if r > 5 { c.fillCircle(cos(0.8) * r * 0.6, sin(0.8) * r * 0.6, max(0.6, r * 0.07), .white.opacity(0.35)) }
    }

    /// A little bead of glass: a bright rim, a highlight high on the left.
    private func bead(_ ctx: GraphicsContext, x: Double, y: Double, r: Double) {
        let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        ctx.fill(circle, with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.06), location: 0), .init(color: .white.opacity(0.1), location: 0.7),
                                                               .init(color: .white.opacity(0.5), location: 1)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        ctx.fillCircle(x - r * 0.38, y - r * 0.38, max(0.6, r * 0.22), .white.opacity(0.75))
    }
}
