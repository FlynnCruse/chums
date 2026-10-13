import SwiftUI

/// Tangle: a ball of yarn drawn in one thick pale-blue marker line, with a face on a crowd of its wires (the messy
/// scribble-lines sheet). The line is one pen stroke: it starts as a tight knot wound round and round under the face,
/// then goes round a ring drawing loops, and ends tucked back into the ball. Its mood is a handful of numbers (how big
/// the loops are, how far they swing out, orbits, spikes, flat, how alive) and each state is a target for them. Slow
/// waves run along the line all the time, so the loops slide past each other, swell and shrink and the whole mass shifts
/// and breathes; every point is a particle on a spring to where all that puts it, with tension along the line, so it
/// never cuts from one look to the next and the loops lag, overshoot and settle. Every loop is a little different, like
/// a hand's scribble, and the line never turns tighter than its own width. One flat colour, like the sheet.
/// It's yarn, and it behaves like yarn:
///   crown, one way: a thread pulls off it as you turn, the ball rolling on it as it comes off; the thread falls and
///   runs along the bottom of the screen, and reels back in (the ball rolling back) when you stop · the other way: it
///   winds itself tight, squinting with the effort, a click at each notch, and boings loose when you let go
///   shake: it wobbles like jelly and its loops fly loose and tangle; after, it knots itself back with a tug and shakes it
///   off; shaken hard, dizzy: spiral eyes, the ball circling and rocking, then it shakes that off too
///   touch: the threads near your finger stretch toward it and twang when you let go, the ball leans to you and gives
///   under the finger, the eyes follow it · tap: a twang, surprise, then a giggle; tapped too often, annoyed · stroke it
///   (pet): eyes closed, it purrs · hold a finger off it: an arm reaches out for it and follows it
///   the face: bigger than the sheet's and drawn on a rim of the yarn's own colour, so it reads even over a gap between
///   wires; it pops to each new expression and lags a little behind the body; it never goes away
///   idle: the calm ball alive with slow loops, eyes looking about; now and then it closes its eyes content · listening:
///   rounder, floating over its shadow, eyes closed and smiling, bobbing with your voice · thinking: eyes up, a small o,
///   a slow sway · working: a loop in three swings out into an orbit, eyes reading, a loop flicks out at each tool call ·
///   subagents: small yarn balls going round it · speaking: its mouth opens with its voice · done: orbits, the open smile,
///   sparkles · needs you: worried, the ball sags, a knock · blocked: wound tight and spiky, trembling · dizzy: above ·
///   sleep: sags flat into a puddle, breathing
final class TangleStage: Staged {
    static let shared = TangleStage()

    let ownsApproval = false
    let holds: [ChumsState: Double] = [.done: 2.6, .dizzy: 3.4]
    func captionTop(_ r: Rig) -> Bool { false }
    func ownsCaption(_ r: Rig) -> Bool { false }
    /// It never stops moving, but slowly enough in the calm states to draw at 30 frames a second.
    var calm: Bool { t - busyAt > 0.6 }

    // the sheet's colours, its scale, its marker
    static let blue = Color(red: 155 / 255, green: 194 / 255, blue: 229 / 255)
    static let ink = Color(red: 0.01, green: 0.01, blue: 0.015)
    /// The face: white on the yarn.
    static let faceInk = Color.white
    /// pt per pixel of the sheet (its cells are 341 px): everything here is in the sheet's pixels.
    static let K = 0.49
    /// The marker's width.
    static let W = 15.5
    /// Points in the ball (the first `kN` of them the knot under the face), points in the end of the line.
    static let N = 380, A = 60, kN = 76
    /// The tightest a loop may be made: a radius of 0.9 of the marker's width.
    static let minRadius = 0.9 * W
    /// A kink: the line turning more than this between two points half a stroke apart.
    static let kink = 60 * Double.pi / 180
    /// The arm's shoulder never turns tighter than this.
    static let shoulder = 2.4 * W
    /// The drawn line's points: half a stroke apart.
    static let step = 0.5 * W
    /// The face: bigger than the sheet's, each mark on a rim of the yarn's colour this wide.
    static let faceScale = 1.2, rim = 11.0
    /// The thread the crown pulls off: at most this long, never turning tighter than `strandBend`.
    static let maxStrand = 430.0, strandBend = 2.2 * W

    // MARK: mood

    fileprivate enum Y: Int, CaseIterable {
        case R, turns, ring, rounds, rl, rlv, ecc, lean, orbit, swirl, spike, loose, mess, flat, sag, arm, aimx, aimy
        case curlAng, faceX, faceY, life, tempo
    }
    private static let base: [Double] = {
        var m = [Double](repeating: 0, count: Y.allCases.count)
        let d: [Y: Double] = [.R: 122, .turns: 14, .ring: 0.36, .rounds: 1.2, .rl: 0.5, .rlv: 0.2, .ecc: 0.3, .lean: 0.2,
                              .mess: 0.25, .aimx: -1.7, .aimy: -0.4, .curlAng: -0.5, .life: 1.05, .tempo: 1.75]
        for (k, v) in d { m[k.rawValue] = v }
        return m
    }()
    private static func mood(_ d: [Y: Double]) -> [Double] { var m = base; for (k, v) in d { m[k.rawValue] = v }; return m }
    /// Each state's shape and how alive it is, fitted to its cell on the sheet. (Every state winds the same number of
    /// loops: changing it would wind the line round, its ends fastest.)
    private func target(_ s: ChumsState) -> [Double] {
        switch s {
        case .idle, .speaking: return Self.base
        case .listening: return Self.mood([.R: 128, .rl: 0.5, .ring: 0.42, .faceX: -0.18, .life: 0.8, .tempo: 1.5])
        case .thinking: return Self.mood([.lean: 0.6, .rl: 0.5, .ring: 0.38, .life: 0.75, .tempo: 0.8])
        case .working: return Self.mood([.orbit: 0.45, .life: 1.05, .tempo: 2.6])
        case .subagents: return Self.mood([.R: 108, .life: 0.8, .tempo: 1.5])
        case .done: return Self.mood([.orbit: 1, .R: 116, .life: 1.25, .tempo: 2.6])
        case .needs: return Self.mood([.sag: 1, .rl: 0.48, .ring: 0.36, .life: 0.8, .tempo: 1.1])
        case .approval: return Self.mood([.R: 118, .rl: 0.5, .ring: 0.38, .life: 0.7])
        case .blocked: return Self.mood([.spike: 1, .rl: 0.42, .ring: 0.32, .R: 116, .life: 0.6, .tempo: 3])
        case .dizzy: return Self.mood([.swirl: 0.35, .loose: 0.5, .R: 118, .rl: 0.46, .ring: 0.44, .life: 1.2, .tempo: 2.2])
        case .sleep: return Self.mood([.flat: 1, .R: 124, .rl: 0.5, .ring: 0.4, .life: 0.4, .tempo: 0.45])
        }
    }
    /// How it moves in each state: a slow turn (rad/s), a float, a breath, a tremble, how much its line wanders.
    private struct Motion { var drift = 0.06, bob = 0.0, breathe = 0.015, tremble = 0.0, wobble = 1.0 }
    private func motion(_ s: ChumsState) -> Motion {
        switch s {
        case .idle, .speaking: return Motion()
        case .subagents: return Motion(drift: 0.1)
        case .listening: return Motion(drift: 0.1, bob: 4)
        case .thinking: return Motion(drift: 0.04, wobble: 0.7)
        case .working: return Motion(drift: 0.5, wobble: 1.2)
        case .done: return Motion(drift: 0.4, wobble: 1.3)
        case .needs: return Motion(drift: 0.08)
        case .approval: return Motion(drift: 0.08, bob: 2)
        case .blocked: return Motion(drift: 0.15, tremble: 1.1, wobble: 0.8)
        case .dizzy: return Motion(drift: 0.12, breathe: 0, wobble: 1.3)
        case .sleep: return Motion(drift: 0.02, breathe: 0.035, wobble: 0.5)
        }
    }

    // MARK: faces (the sheet's marks, every part blends into the next)

    private struct Look {
        var pose = "00"
        var eL = "", eR = "", eL2 = "", eR2 = "", bL = "", bR = "", m = "", cL = "", cR = "", sw = "", tg = ""
        var look = 1.0, aim = P2.zero                      // how much the eyes follow the gaze; a fixed look (px)
        var spirals = false                                // dizzy: spiral eyes
        var key: String { pose + eL + eR + eL2 + m + tg + (spirals ? "@" : "") }
    }
    private static func dots(_ pose: String, mouth: String = "", scale: Double = 0.8) -> Look {
        Look(pose: pose, eL: "21.eL@\(pose).eL*1.2", eR: "21.eR@\(pose).eR*1.2", m: mouth.isEmpty ? "21.m@\(pose).m*\(scale)" : mouth)
    }
    private func look(_ s: ChumsState) -> Look {
        switch s {
        case .idle, .subagents, .speaking: return Self.dots("00", mouth: "00.m")
        case .listening: return Look(pose: "11", eL: "11.eL", eR: "11.eR", m: "11.m")
        case .thinking: var l = Self.dots("00", scale: 0.65); l.look = 0; l.aim = P2(5, -7); return l
        case .working: return Self.dots("00", scale: 0.6)
        case .done: return Self.whee
        case .needs: return Look(pose: "02", eL: "02.eL", eR: "02.eR", bL: "02.bL", bR: "02.bR", m: "02.m", look: 0.5)
        case .approval: var l = Self.dots("00", scale: 0.65); l.look = 0; l.aim = P2(0, 6); return l
        case .blocked: return Self.cross
        case .dizzy: return Self.dizzy
        case .sleep: return Self.sleepy
        }
    }
    private static let content = Look(pose: "00", eL: "00.eL", eR: "00.eR", m: "00.m", look: 0)
    private static let delight = Look(pose: "01", eL: "00.eL@01.eL*0.85", eR: "00.eR@01.eR*0.85", m: "01.m", tg: "01.tg", look: 0)
    private static let whee = Look(pose: "01", eL: "01.eL", eR: "01.eR", m: "01.m", tg: "01.tg")
    private static let surprise = Look(pose: "00", eL: "01.eL@00.eL", eR: "01.eR@00.eR", m: "21.m@00.m*1.7", look: 0.3)
    private static let curious = Look(pose: "00", eL: "01.eL@00.eL*0.85", eR: "01.eR@00.eR*0.85", m: "21.m@00.m*1.1")
    private static let frazzled = Look(pose: "12", eL: "12.eL", eR: "12.eR", m: "12.m", cL: "12.cL", cR: "12.cR", sw: "12.sw", look: 0.4)
    private static let reaching = Look(pose: "21", eL: "21.eL", eR: "21.eR", m: "21.m")
    private static let cross = Look(pose: "10", eL: "10.eLa", eR: "10.eRa", eL2: "10.eLb", eR2: "10.eRb", m: "10.m", look: 0)
    private static let strain = Look(pose: "10", eL: "10.eLa", eR: "10.eRa", eL2: "10.eLb", eR2: "10.eRb", m: "12.m@10.m*0.7", look: 0)
    private static let dizzy = Look(pose: "12", m: "12.m", look: 0, spirals: true)
    private static let sleepy = Look(pose: "20", eL: "20.eL", eR: "20.eR", m: "21.m@20.m*0.7", look: 0)

    /// A face part: its outline (64 points) blends from one shape into the next on a spring, or shrinks away and back.
    private struct Part {
        var from: [P2], to: [P2], b = 1.0, bv = 0.0, name = "", none = true
        var shape: [P2] { b >= 1 ? to : Strokes.mix(from, to, b) }
        var shown: Bool { !(none && b > 0.98) }
        mutating func set(_ n: String, _ g: [P2]) {
            guard n != name else { return }
            let cur = shape
            if n.isEmpty {
                let c = TangleStage.centroid(cur); from = cur; to = [P2](repeating: c, count: cur.count); none = true
            } else {
                from = none && b > 0.98 ? [P2](repeating: TangleStage.centroid(g), count: g.count) : cur
                to = g; none = false
            }
            name = n; b = 0; bv = 0
        }
    }
    private static func centroid(_ p: [P2]) -> P2 { p.reduce(P2.zero, +) / Double(max(1, p.count)) }
    private static let empty = [P2](repeating: .zero, count: ScribbleArt.N)
    // eL eR eL2 eR2 bL bR m cL cR sw tg
    private var parts: [Part] = (0..<11).map { _ in Part(from: TangleStage.empty, to: TangleStage.empty) }
    private var shown = Look(), shownKey = "", gazeK = 1.0, aim = P2.zero, spiralK = 0.0
    private var pop = (k: 0.0, v: 0.0)                                    // the face pops to each new expression
    private var faceOff = P2.zero, faceOffV = P2.zero                     // and lags a little behind the body
    /// A mark, moved so its face's middle (between the eyes) is at 0.
    private static func faceGlyph(_ name: String, _ pose: String) -> [P2] {
        let o = ScribbleArt.faceOrigin(pose)
        return ScribbleArt.glyph(name).map { $0 - o }
    }

    // MARK: the line

    /// Its body: a ball of yarn, one thread wound round, the crown its spool (Yarn).
    private let yarn = Yarn()

    private var pos = [P2](repeating: .zero, count: TangleStage.N + TangleStage.A)
    private var vel = [P2](repeating: .zero, count: TangleStage.N + TangleStage.A)
    private var tgt = [P2](repeating: .zero, count: TangleStage.N + TangleStage.A)
    private var shoulderKind = -1, aimA = 0.0, aimL = 1.6                // which of the four ways the shoulder took
    private var drawn: [P2] = []                                          // the line as drawn (smoothed)
    private var mood = TangleStage.base, moodV = [Double](repeating: 0, count: Y.allCases.count)
    private var started = false
    /// The waves along the line: their phase (runs at the mood's tempo), and a bigger swell now and then.
    private var ph = 0.0, gustT = 9.0, nextGust = 3.0

    // MARK: state

    private var state: ChumsState = .idle
    private var t = 0.0, busyAt = 0.0, stateT = 0.0
    private var cur = Motion()
    private var spin = 0.0, crownIdle = 9.0, crownAcc = 0.0
    /// The crown: the thread pulled off (its length, px), how fast it reels back, which side it fell; how tightly wound.
    private var strand = 0.0, strandV = 0.0, strandSide = 1.0, lastStrand = 0.0, tugT = 9.0
    private var wound = 0.0, woundV = 0.0
    /// The drawing's own turn: rolling on the thread, a thinking sway. The face never turns with it.
    private var roll = 0.0, sway = 0.0, rot = 0.0
    /// The whole body: where it sits, a jelly wobble (an offset that stretches it along itself), a lean.
    private var center = P2(99, 128), cv = P2.zero, fingerOff = P2.zero, dragV = P2.zero
    private var jelly = P2.zero, jellyV = P2.zero, tilt = 0.0, tiltV = 0.0, circle = 0.0
    private var squash = (k: 0.0, v: 0.0), hop = (y: 0.0, v: 0.0), bump = 0.0
    /// Shaken: how tangled its loops are (they come loose and scramble), and the knotting back and shaking off after.
    private var tangle = 0.0, tanglePeak = 0.0, lastShake = -9.0, scramble = 0.0, shakeOff = 0.0
    private var finger: CGPoint?, lastTouch: CGPoint?, reach = 0.0, pluck = 0.0
    private var knock = 0.0, nextTool = 0.8, toolFlash = 0.0
    private var startle = 0.0, boingT = 0.0, crossT = 0.0, petT = 0.0, pokes: [Double] = []
    private var fidget = 0.0, nextFidget = 9.0
    private var minis = 0.0, sparkle = 0.0, shadowK = 0.0
    /// Small at the top for an approval: eased there and back.
    private var scale = 1.0, scaleV = 0.0

    // MARK: Staged

    func onState(_ r: Rig, _ s: ChumsState, prev: ChumsState?, variant: Bool) {
        let was = state
        state = s; stateT = 0
        switch s {
        case .done: hop.v = -220; squash.v -= 2; kick(radial: 60)                 // it bursts open
        case .needs: knock = 0
        case .listening: squash.v += 2
        case .blocked: squash.v -= 3; kick(radial: -60)                            // it winds up tight
        case .dizzy: tangle = max(tangle, 0.85); tanglePeak = 0                    // knocked loose (it re-knots at the end)
        default: break
        }
        if was == .dizzy && s != .dizzy { shakeOff = 0.7; woundV += 2.4 }          // it shakes the daze off, knots back up
        fidget = 0; nextFidget = rnd(8, 14)
        busyAt = t
    }

    func step(_ r: Rig, _ dt0: Double) {
        let dt = min(dt0, 1.0 / 30)
        t += dt; stateT += dt
        guard !r.ao else {
            // dimmed: drawn about once a second, so nothing in flight; it rests in its shape, the loops still
            startle = 0; boingT = 0; crossT = 0; petT = 0; toolFlash = 0; finger = nil; reach = 0; pluck = 0
            hop = (0, 0); squash = (0, 0); bump = 0; jelly = .zero; jellyV = .zero; tilt = 0; tiltV = 0
            tangle = 0; tanglePeak = 0; shakeOff = 0; strand = 0; strandV = 0; lastStrand = 0; wound = 0; woundV = 0
            roll = 0; sway = 0; rot = 0; faceOff = .zero; faceOffV = .zero; pop = (0, 0)
            if started { generate(); pos = tgt; for i in vel.indices { vel[i] = .zero } }
            return
        }
        var m = motion(state)
        if petT > 0 { m.drift = 0.03; m.wobble = 0.6; m.tremble = 0.3 }        // stroked, it purrs
        let e = min(1, dt * 3)
        cur.drift += (m.drift - cur.drift) * e; cur.bob += (m.bob - cur.bob) * e; cur.breathe += (m.breathe - cur.breathe) * e
        cur.tremble += (m.tremble - cur.tremble) * e; cur.wobble += (m.wobble - cur.wobble) * e
        crownIdle += dt; petT = max(0, petT - dt); startle = max(0, startle - dt); boingT = max(0, boingT - dt)
        crossT = max(0, crossT - dt); toolFlash = max(0, toolFlash - dt); bump = max(0, bump - dt * 3)
        shakeOff = max(0, shakeOff - dt); tugT += dt
        // the crown let go: the thread reels back in (slow, then quicker), the wound ball boings loose and settles
        if crownIdle > 0.45 {
            if strand > 0 { strandV = min(strandV + 420 * dt, 240); strand = max(0, strand - strandV * dt) } else { strandV = 0 }
            if wound > 0.6 && woundV == 0 { boingT = 0.9 }
            let wk = TAU * 1.4
            woundV += (-wk * wk * wound - 2 * 0.3 * wk * woundV) * dt
            wound += woundV * dt
            if abs(wound) < 0.002 && abs(woundV) < 0.01 { wound = 0; woundV = 0 }
        } else { strandV = 0 }
        // the ball rolls on the thread as it comes off and goes back on
        let R0 = max(60, mood[Y.R.rawValue])
        roll += (strand - lastStrand) / (R0 * 0.85) * strandSide; lastStrand = strand
        if strand == 0 && crownIdle > 1 {
            let home = (roll / TAU).rounded() * TAU                          // and comes back upright
            roll += (home - roll) * min(1, dt * 1.5)
        }
        sway += ((state == .thinking ? 0.16 * sin(t * 0.9) : 0) - sway) * min(1, dt * 2.5)   // thinking: a slow sway
        rot = roll + sway
        spin += cur.drift * dt
        // shaken: tangled while it's shaken, then it knots itself back up (a tug) and shakes it off
        if t - lastShake > 0.25 { tangle = max(0, tangle - dt * (state == .dizzy ? 0.12 : 0.55)) }
        if tanglePeak > 0.45 && tangle < 0.3 && state != .dizzy { tanglePeak = 0; woundV += 2.6; shakeOff = 0.7 }
        scramble += dt * 3.2 * tangle
        // the mood: each number on its own spring to the state's target (a little overshoot)
        var goal = target(state)
        if tangle > 0 {
            goal[Y.loose.rawValue] = max(goal[Y.loose.rawValue], tangle * 0.9); goal[Y.mess.rawValue] += 0.5 * tangle
            goal[Y.life.rawValue] += 0.5 * tangle
        }
        if crossT > 0 { goal[Y.spike.rawValue] = 0.7; goal[Y.rl.rawValue] = 0.46; goal[Y.tempo.rawValue] = 2.6 }
        if startle > 0 && state == .sleep { goal[Y.flat.rawValue] = 0.45; goal[Y.life.rawValue] = 0.9 }
        if petT > 0 { goal[Y.life.rawValue] *= 0.6; goal[Y.tempo.rawValue] *= 0.5 }
        if state == .listening || state == .speaking { goal[Y.life.rawValue] += r.voice * 0.4 }
        if strand > 0 { goal[Y.R.rawValue] *= 1 - 0.1 * min(1, strand / Self.maxStrand) }   // the thread comes out of it
        if let f = finger, reach > 0.02 {
            // an arm out for the finger: aimed at it, in the ball's own units
            let d = (P2(f.x, f.y) - center) / Self.K / max(0.4, scale)
            let R = mood[Y.R.rawValue], l = max(1, simd_length(d))
            var a = d / l * clamp(l / R, 1.45, 2.1)
            // the hand stays on the screen, below the clock
            let k = R * Self.K * max(0.4, scale)
            let onScreen = P2(clamp(center.x + a.x * k, 16, 182), clamp(center.y + a.y * k, 64, 222))
            a = (onScreen - center) / k
            // the aim swings round the ball (its angle and its reach eased), never cutting across the middle
            if reach < 0.05 { aimA = atan2(a.y, a.x); aimL = simd_length(a) }
            aimA += remainder(atan2(a.y, a.x) - aimA, TAU) * min(1, dt * 5)
            aimL += (simd_length(a) - aimL) * min(1, dt * 5)
            goal[Y.arm.rawValue] = reach
            let la = aimA - rot - tilt                                         // in the turned drawing's own frame
            goal[Y.aimx.rawValue] = cos(la) * aimL; goal[Y.aimy.rawValue] = sin(la) * aimL
        }
        let wm = TAU * 1.25
        for i in 0..<mood.count {
            // the arm's aim moves quickly; the number of loops slowly
            let aimFast = i == Y.aimx.rawValue || i == Y.aimy.rawValue ? 3 : i == Y.turns.rawValue ? 0.3 : 1.0
            let w = wm * aimFast
            moodV[i] += (w * w * (goal[i] - mood[i]) - 2 * 0.72 * w * moodV[i]) * dt
            mood[i] += moodV[i] * dt
        }
        // the waves along the line; now and then (when it's calm) a bigger swell runs through it
        ph += max(0.1, mood[Y.tempo.rawValue] + 2 * max(0, wound)) * dt
        gustT += dt
        if [.idle, .thinking, .subagents, .speaking, .approval, .needs, .listening].contains(state) {
            nextGust -= dt
            if nextGust <= 0 { gustT = 0; nextGust = rnd(3.5, 6.5) }
        }
        // a finger: held off the ball, the arm reaches for it; on it (or near), its threads are pulled toward it
        let Rp = mood[Y.R.rawValue] * Self.K * scale
        var fd = 1e9
        if let f = finger { fd = simd_length(P2(f.x, f.y) - center) }
        if finger != nil && fd > Rp * 1.05 { reach = min(1, reach + dt * 3) } else { reach = max(0, reach - dt * 2) }
        pluck += ((finger != nil && fd < Rp * 1.35 && reach < 0.5 ? 1 : 0) - pluck) * min(1, dt * 10)
        // the body: squash, hop, jelly, lean, where it sits (a finger pulls it a little toward itself)
        let ws = TAU * 2.6, sqT = pluck * -0.07
        squash.v += (-ws * ws * (squash.k - sqT) - 2 * 0.3 * ws * squash.v) * dt; squash.k = clamp(squash.k + squash.v * dt, -0.25, 0.25)
        hop.v += 1000 * dt; hop.y += hop.v * dt
        if hop.y > 0 { if hop.v > 100 { squash.v -= hop.v / 160 }; hop.y = 0; hop.v = 0 }
        let wj = TAU * 3.1
        let ja: P2 = jelly * (-wj * wj) - jellyV * (2 * 0.13 * wj)
        jellyV += ja * dt; jelly += jellyV * dt
        if simd_length(jelly) > 34 { jelly = jelly / simd_length(jelly) * 34 }
        var tiltT = 0.0
        if let f = finger { tiltT += clamp((Double(f.x) - center.x) / 70, -1, 1) * 0.13 }          // it leans to you
        let dz = state == .dizzy ? clamp(1.3 - stateT / 3.4, 0.25, 1) : 0
        tiltT += dz * 0.17 * sin(t * 4.1)                                                          // dizzy: it rocks
        if shakeOff > 0 { tiltT += 0.16 * sin(shakeOff * 26) * shakeOff / 0.7 }                    // and shakes it off
        let wt = TAU * 2.2
        tiltV += (-wt * wt * (tilt - tiltT) - 2 * 0.5 * wt * tiltV) * dt; tilt += tiltV * dt
        circle += ((state == .dizzy ? dz : 0) - circle) * min(1, dt * 3)
        var home = P2(99, state == .approval ? 74 : state == .listening ? 136 : state == .sleep ? 146 : 128)
        home += P2(cos(t * 3.6), sin(t * 3.6)) * (7 * circle)                                     // dizzy: it circles
        let fo: P2 = finger.map { P2(clamp(($0.x - 99) * 0.18, -16, 16), clamp(($0.y - 128) * 0.15, -14, 14)) } ?? .zero
        fingerOff += (fo - fingerOff) * min(1, dt * 6); home += fingerOff
        let wc = TAU * 2
        let pull: P2 = (home - center) * (wc * wc), damp: P2 = cv * (wc * 1.1)
        cv += (pull - damp) * dt; center += cv * dt
        dragV += (cv - dragV) * min(1, dt * 7)
        // the face lags behind the body (a little), and pops to each new expression
        let fw = TAU * 2.4
        let fT: P2 = cv * -0.06 + jellyV * -0.012
        let fa: P2 = (fT - faceOff) * (fw * fw) - faceOffV * (2 * 0.42 * fw)
        faceOffV += fa * dt; faceOff += faceOffV * dt
        let pw = TAU * 3.2
        pop.v += (-pw * pw * pop.k - 2 * 0.3 * pw * pop.v) * dt; pop.k += pop.v * dt
        // the work: each tool call, a loop flicks out, a little hop, the eyes glance up
        nextTool -= dt
        if nextTool <= 0 && (!r.worlds.queue.isEmpty || state == .working), let c = r.worlds.nextEvent(r) {
            nextTool = r.worlds.queue.isEmpty ? rnd(1.4, 2.4) : 0.5
            if c.kind != .stop { flick(); hop.v = min(hop.v, -90); toolFlash = 0.6 }
        }
        if state == .needs {
            let was = knock; knock += dt; if knock >= 3.2 { knock = 0 }
            if was < 0.2 && knock >= 0.2 { bump = 1; squash.v += 2.4; r.onHaptic?(.strong); kick(radial: 90) }
        }
        if state == .idle && finger == nil && crownIdle > 3 {
            nextFidget -= dt
            if nextFidget <= 0 { fidget = 2.4; nextFidget = rnd(10, 18) }
        }
        fidget = max(0, fidget - dt)
        let wsc = TAU * 2.2, sgoal = state == .approval ? 0.5 : 1.0
        scaleV += (wsc * wsc * (sgoal - scale) - 2 * 0.75 * wsc * scaleV) * dt; scale += scaleV * dt
        minis += ((state == .subagents ? 1 : 0) - minis) * min(1, dt * 3)
        sparkle += ((state == .done ? 1 : 0) - sparkle) * min(1, dt * 5)
        shadowK += ((state == .listening ? 1 : 0) - shadowK) * min(1, dt * 7)
        // the ball of yarn: where it sits and how big (wound tight, a little smaller), then its own physics
        yarn.center = center + P2(jelly.x * 0.3, hop.y + jelly.y * 0.3)
        yarn.scale = scale * (1 - 0.12 * wound) * (1 + 0.04 * bump)
        yarn.step(dt, gravity: P2(clamp(r.W.padX, -0.6, 0.6), 1))
        if yarn.busy { busyAt = t }
        stepLook(r, dt)
        // fast moves draw at 60 frames a second; the slow life of the calm states at 30
        let fast = finger != nil || strand > 0.5 || abs(wound) > 0.005 || abs(woundV) > 0.02 || tangle > 0.01 || shakeOff > 0
            || simd_length(jelly) > 0.4 || simd_length(jellyV) > 4 || abs(tiltV) > 0.03 || hop.v != 0 || abs(squash.v) > 0.3
            || simd_length(cv) > 4 || startle > 0 || boingT > 0 || crossT > 0 || abs(scaleV) > 0.02 || abs(pop.v) > 0.05
            || parts.contains { abs($0.bv) > 0.05 } || [.working, .done, .dizzy, .blocked, .speaking, .listening].contains(state)
        if fast { busyAt = t }
    }

    @inline(__always) private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = clamp((x - a) / (b - a), 0, 1); return k * k * (3 - 2 * k)
    }

    /// Where the mood puts every point of the line (in the sheet's pixels, round the ball's middle).
    private func generate() {
        let m = mood
        func g(_ y: Y) -> Double { m[y.rawValue] }
        // wound tight by the crown: smaller, tighter loops; boinged loose after: bigger ones
        let wd = wound
        let R = g(.R) * (1 - 0.12 * max(0, wd) - 0.05 * min(0, wd))
        let orbit = clamp(g(.orbit), 0, 1.2), swirl = clamp(g(.swirl), 0, 1.2), turns = max(1, g(.turns))
        let ring = g(.ring) * (1 - 0.15 * min(1, orbit)) * (1 - 0.35 * max(0, wd) - 0.4 * min(0, wd))
        let rlW = 1 - 0.22 * max(0, wd) - 0.3 * min(0, wd)
        let loose = g(.loose), spike = g(.spike) * (1 - clamp(loose, 0, 1)), mess = g(.mess) * cur.wobble   // shaken loose, the bristles relax
        let L = max(0, g(.life)), p = ph
        let gust = gustT < 1.8 ? sin(Double.pi * gustT / 1.8) : 0
        let fc = P2(g(.faceX), g(.faceY)), knotW = 1 - clamp(swirl, 0, 1)
        let turn = spin
        let N = Self.N
        // the whole mass shifts a little, side to side and up and down
        let shift = P2(cos(p * 0.45), sin(p * 0.37 + 1)) * (0.05 * L)
        let irr = 1.0 + 1.1 * tangle                                           // tangled: every loop more its own
        let squashY = 1 - 0.4 * clamp(g(.flat), 0, 1.2)
        let irrT = irr * (1 - 0.7 * min(1, orbit))                           // orbits: their loops' own turn kept steady
        let scr = scramble
        // the whole line in one: past the ball's last point it carries straight on, tucking its end back in
        for i in 0..<(N + Self.A) {
            let s = Double(i) / Double(N - 1), sc = s - 0.5
            let tuck = smooth(1, 1.16, s)
            // every loop its own: smooth noise along the line, about one value per loop, drifting slowly
            let lp = turns * s + 0.05 * p + scr
            let nR = Self.vn(lp * 0.9, 1), nE = Self.vn(lp * 0.8, 2), nT = Self.vn(lp * 0.5, 3)
            let nX = Self.vn(lp * 0.3, 4), nY = Self.vn(lp * 0.3, 5), nS = Self.vn(lp * 0.4, 6), nC = Self.vn(s * 2.4 + 0.03 * p + scr * 0.5, 7)
            // the hand goes round a ring, drawing loops as it goes; the ring bunches up and spreads as waves go round it,
            // and the loops crowd round some of it and wander off elsewhere
            let cang = TAU * g(.rounds) * sc + 0.6 + turn * 0.5 + L * 0.4 * Self.vn(s * 1.8 + p * 0.25, 11) + irr * 0.35 * nC
            let cr = ring * (1 + 0.25 * Self.vn(s * 4.4 + p * 0.1, 12) + L * 0.2 * Self.vn(s * 1.4 - p * 0.16, 13)) * (1 - 0.5 * tuck)
            var cx = cos(cang) * cr + shift.x * sin(TAU * 0.5 * s + 0.6) + irr * 0.13 * nX
            var cy = sin(cang) * cr + shift.y * cos(TAU * 0.5 * s) + irr * 0.13 * nY
            // orbits: about one loop in three flies out into a big ellipse round the ball (each grows into it over a loop)
            let kk = turns * sc, ow = orbit * smooth(-0.1, 0.9, sin(TAU * kk / 3 + 0.4))
            // the loops slide along the line, and swell and shrink as a wave runs through them
            let th = TAU * turns * sc + turn + L * 1.3 * Self.vn(s * 1.1 - p * 0.2, 14) + irrT * 0.9 * nS    // uneven spacing
            let swell = L * (0.16 * Self.vn(s * 2.8 - p * 0.35, 15) + 0.08 * Self.vn(s * 5.8 + p * 0.22, 16)) + gust * 0.22 * sin(TAU * s - p * 2)
            var rr = g(.rl) * rlW * (1 + g(.rlv) * (Self.vn(s * 6.2 + p * 0.1, 17) + 0.5 * Self.vn(s * 12.6 - p * 0.06, 18)) + swell)
            rr = rr * (1 - ow) + ow * (0.95 + 0.12 * sin(TAU * 3.3 * s + 1) + 0.6 * swell)
            rr *= (1 + irr * 0.32 * nR) * (1 - 0.45 * tuck)                   // sizes differ
            if loose > 0.001 {
                let q = sin(TAU * 2.5 * s + 0.5 + scr * 0.3)
                rr += loose * 0.3 * exp(-q * q * 2.5)                         // some loops swing wide
            }
            var e = g(.ecc) * (1 - ow) + ow * 0.48 + L * 0.12 * Self.vn(s * 3.2 + p * 0.28, 19)
            e = clamp(e + irr * 0.22 * nE, 0, 0.72)                           // roundness differs
            var psi = cang + g(.lean) + L * 0.25 * Self.vn(s * 1.6 + p * 0.16, 20) + irrT * 0.5 * nT  // so does tilt
            if ow > 0.001 {
                // its own tilt, a little off the others' (a bounded offset: never a jump round the loop)
                psi += ow * (0.45 * sin(1.2 * kk + 0.3 * sin(p * 0.4)) + 0.35)
            }
            // the knot: the start of the line winds round and round under the face, its loops drifting: the same line,
            // its loops smaller and centred on the face (so it flows on into the rest, never a fold where they meet)
            let kw = (1 - smooth(0.15, 0.24, s)) * knotW
            if kw > 0.001 {
                let u = s / 0.24
                let wk = P2(cos(TAU * 0.6 * u + p * 0.5) + 0.6 * Self.vn(u * 1.5, 9), sin(TAU * 0.5 * u + p * 0.6 + 1) + 0.6 * Self.vn(u * 1.5, 10)) * 0.08
                let rk = (0.21 + 0.05 * sin(TAU * 2.3 * u - p * 0.8) + 0.03 * L * sin(p * 1.3 + u * 5)) * (1 + 0.22 * Self.vn(u * 3.8 + 0.04 * p, 8))
                let ek = 0.22 + 0.1 * sin(TAU * 0.9 * u + p * 0.4), psik = psi + 0.5 * sin(TAU * 0.7 * u + p * 0.3)
                cx += (fc.x + wk.x - cx) * kw; cy += (fc.y + wk.y - cy) * kw
                rr += (rk - rr) * kw; e += (ek - e) * kw; psi += (psik - psi) * kw
            }
            // never tighter than the marker: each loop at least so big, its ends at least so round (b² / a ≥ minRadius,
            // allowing for the flattening a puddle gets later)
            rr = max(rr, 1.15 * Self.minRadius / (R * squashY * squashY))
            e = min(e, max(0, 1 - sqrt(Self.minRadius / (squashY * squashY * rr * R))))
            let a = th - psi
            if spike > 0.001 {
                // bristles: where a loop swings out, every few points the line pokes out and back (a short hairpin)
                let ca = max(0, cos(a)), outer = ca * ca
                let k = Double(i % 12) - 5.5, comb = exp(-k * k / 7.2)       // rounded teeth, tips just inside the limit
                rr += spike * 0.22 * outer * comb * (1 - smooth(0.6, 1, 1 - smooth(0.15, 0.24, s)))   // not on the knot
            }
            let lx = cos(a) * rr, ly = sin(a) * rr * (1 - e)
            let cp = cos(psi), sp = sin(psi)
            var q = P2(cx + lx * cp - ly * sp, cy + lx * sp + ly * cp)
            if swirl > 0.001 {
                // dizzy: the ball twisted like a whirlpool, its middle turned further than its edge
                let tw = swirl * 1.4 * (1 - smooth(0, 1.1, simd_length(q))), ct = cos(tw), st = sin(tw)
                q = P2(q.x * ct - q.y * st, q.x * st + q.y * ct)
            }
            q *= R
            if q.x.isFinite && q.y.isFinite { tgt[i] = q }                    // (never a bad number into the line)
        }
        let A = Self.A
        // the thread the crown pulled off: from the line's end, the way it was going, out and down, then along the
        // bottom of the screen back under the ball; never turning tighter than `strandBend`, a slow wave running down it
        if strand > 1 {
            let ws = smooth(0, 30, strand)
            let cr = cos(rot + tilt), sr = sin(rot + tilt)
            let P0 = tgt[N - 1], d0: P2 = tgt[N - 1] - tgt[N - 2]
            var q = P2(P0.x * cr - P0.y * sr, P0.x * sr + P0.y * cr)
            if lastStrandStart { strandSide = q.x >= 0 ? 1 : -1; lastStrandStart = false }
            var hd = atan2(d0.x * sr + d0.y * cr, d0.x * cr - d0.y * sr)
            let side = strandSide
            let flow = side > 0 ? 0.55 : Double.pi - 0.55
            let floorY = (226 - center.y) / (Self.K * max(0.4, scale)), wallX = 190 / max(0.4, scale)
            // (its length counts from the ball's edge: the line's end is somewhere inside the ball)
            let ds = (strand + R * 0.85) / Double(A), maxTurn = ds / Self.strandBend
            var out = [P2](repeating: .zero, count: A)
            for j in 0..<A {
                let u = Double(j) / Double(A - 1)
                // out and down, falling more the further it goes; a wave runs down it (stronger toward its end)
                var ht = flow + (Double.pi / 2 - flow) * 0.5 * u
                let onFloor = smooth(floorY - 70, floorY - 25, q.y)
                let floorH = side > 0 ? Double.pi + 0.08 : -0.08                // along the bottom, back under the ball
                ht = ht + remainder(floorH - ht, TAU) * onFloor
                let nearWall = smooth(wallX - 60, wallX - 15, abs(q.x)) * (1 - onFloor)
                ht = ht + remainder(Double.pi / 2 - ht, TAU) * nearWall      // at the side: straight down
                let wave = (0.5 - 0.3 * onFloor) * smooth(0, 0.2, u) * sin(TAU * Double(j) * ds / 120 - t * 3.2 - (tugT < 0.6 ? 2 : 0))
                ht += wave
                hd += clamp(remainder(ht - hd, TAU), -maxTurn, maxTurn)
                q += P2(cos(hd), sin(hd)) * ds
                out[j] = P2(q.x * cr + q.y * sr, -q.x * sr + q.y * cr)
            }
            blendEnd(out, ws, from: P0)
        } else { lastStrandStart = true }
        // an arm reaching out with a hand (a loop the line runs round, then a finger). It leaves the line by the
        // shortest way that never turns tighter than `shoulder` (arcs and a straight)
        let wa = clamp(g(.arm), 0, 1)
        if wa > 0.001 {
            let T = P2(g(.aimx), g(.aimy)) * R
            let tl = max(1, simd_length(T)), dd = T / tl, nn = P2(-dd.y, dd.x)
            let rp = R * 0.17
            let Ew: P2 = T - dd * (R * 0.3)                                   // the wrist
            let nh = 22                                                       // 16 round the palm, 6 the finger
            let open = TAU * smooth(0.35, 1, wa)                              // the palm curls round as the arm grows
            let exit: P2 = dd * cos(open) + nn * sin(open)
            let wrist2: P2 = Ew + dd * (rp * sin(open)) + nn * (rp * (1 - cos(open)))
            var hand = [P2](repeating: .zero, count: nh)
            for k in 0..<nh {
                if k < 16 {
                    let th = open * Double(k + 1) / 16
                    hand[k] = Ew + dd * (rp * sin(th)) + nn * (rp * (1 - cos(th)))
                } else {
                    hand[k] = wrist2 + exit * (R * 0.075 * Double(k - 15))
                }
            }
            // from the line's end, its way, to the wrist, pointing at the target
            let P0: P2 = tgt[N - 1], d0: P2 = tgt[N - 1] - tgt[N - 2]
            let way = Self.dubins(P0, atan2(d0.y, d0.x), Ew, atan2(dd.y, dd.x), Self.shoulder, count: A - nh, keep: &shoulderKind)
            blendEnd(way + hand, wa, from: P0)
        }
        // mess: a slow smooth wander along the line; sag: it hangs heavy; flat: a puddle, wide and low
        let flat = clamp(g(.flat), 0, 1.2), sag = clamp(g(.sag), 0, 1.2)
        let sx = 1 + 0.26 * flat, sy = 1 - 0.4 * flat
        let mk = mess * R * 0.06
        for i in 0..<tgt.count {
            let xi = Double(i)
            let w = P2(sin(xi * 0.21 + t * 0.8) + 0.5 * sin(xi * 0.067 + 1.3), cos(xi * 0.17 + t * 0.6) + 0.5 * cos(xi * 0.053))
            var q = tgt[i] + (i < N ? w * mk : w * (mk * 0.3))
            if sag > 0.001 && i < N {
                let yy = max(0, q.y / R + 0.2)
                q = P2(q.x * (1 - sag * 0.1 * yy), q.y + sag * R * 0.22 * yy * yy)
            }
            tgt[i] = i < N ? P2(q.x * sx, q.y * sy) : q
        }
    }
    private var lastStrandStart = true

    /// The end of the line becomes `other` by `w`: by blending how each turns and steps along its length (never their
    /// places), walked out from the line's end, so the mix is never tighter than either.
    private func blendEnd(_ other: [P2], _ w: Double, from P0: P2) {
        let N = Self.N, A = Self.A
        var cont = [P2](repeating: .zero, count: A)
        for j in 0..<A { cont[j] = tgt[N + j] }
        var hc = atan2(cont[0].y - P0.y, cont[0].x - P0.x), ha = atan2(other[0].y - P0.y, other[0].x - P0.x)
        ha = hc + remainder(ha - hc, TAU)
        var q = P0, prevC = P0, prevA = P0
        for j in 0..<A {
            let sc: P2 = cont[j] - prevC, sa: P2 = other[j] - prevA
            let lc = simd_length(sc), la = simd_length(sa)
            if j > 0 {
                if lc > 1e-6 { hc += remainder(atan2(sc.y, sc.x) - hc, TAU) }
                if la > 1e-6 { ha += remainder(atan2(sa.y, sa.x) - ha, TAU) }
            }
            let hh = hc + (ha - hc) * w, l = lc + (la - lc) * w
            q += P2(cos(hh), sin(hh)) * l
            prevC = cont[j]; prevA = other[j]
            tgt[N + j] = q
        }
    }

    /// A push out from the middle (in, when negative) for the whole line (a burst, a knock).
    private func kick(radial: Double) {
        for i in pos.indices {
            // the whole line swells (or draws in) together: a push in proportion to where each point is, so it can
            // stretch the line but never fold it
            vel[i] += pos[i] * (radial / 80)
        }
    }
    /// One loop flicks out (a tool call).
    private func flick() {
        let c = Int.random(in: (Self.kN + 20)..<(Self.N - 30))
        for i in max(0, c - 18)..<min(Self.N, c + 18) {
            let k = 1 - abs(Double(i - c)) / 18
            vel[i] += pos[i] * (5 * k * k)                                    // that stretch of line swells out
        }
    }
    /// The threads near `p` (screen points) twang: a quick shiver across them that runs off along the line.
    private func twang(at p: CGPoint, strength: Double) {
        let w0 = (P2(p.x, p.y) - center) / (Self.K * max(0.4, scale)), c = cos(-(rot + tilt)), s = sin(-(rot + tilt))
        let fl = P2(w0.x * c - w0.y * s, w0.x * s + w0.y * c)
        let n = pos.count
        for i in 1..<(n - 1) {
            let l = simd_length(pos[i] - fl)
            guard l < 110 else { continue }
            let k = 1 - l / 110, d: P2 = pos[i + 1] - pos[i - 1], dl = max(1e-6, simd_length(d))
            let nrm = P2(-d.y, d.x) / dl
            vel[i] += nrm * (strength * k * k * sin(Double(i) * 0.9))
        }
    }

    private func stepLook(_ r: Rig, _ dt: Double) {
        var l = look(state)
        if state == .done && stateT > 2.2 { l = Self.delight }
        if fidget > 0 || petT > 0 { l = Self.content }
        if pluck > 0.5 && petT <= 0 { l = Self.curious }
        if reach > 0.5 { l = Self.reaching }
        if yarn.moving > 0.25 && yarn.off > 0.01 { l = Self.whee }                 // reeled in or fed out
        if wound > 0.22 { l = Self.strain }
        if boingT > 0 { l = Self.delight }
        if tangle > 0.3 && state != .sleep && state != .dizzy { l = Self.frazzled }
        if shakeOff > 0 { l = Self.content }
        if state == .dizzy { l = Self.dizzy }
        if startle > 0 {
            if state == .sleep { l = startle > 0.5 ? Self.surprise : Self.sleepy }
            else if state != .dizzy { l = startle > 0.45 ? Self.surprise : Self.delight }
        }
        if crossT > 0 { l = Self.cross }
        if state == .working && toolFlash > 0 { l.aim = P2(0, -6); l.look = 0 }
        if l.key != shownKey && faceStarted { pop.v += 2.2 }                 // a new expression: the face pops
        shownKey = l.key
        shown = l
        let names = [l.eL, l.eR, l.eL2, l.eR2, l.bL, l.bR, l.m, l.cL, l.cR, l.sw, l.tg]
        for i in 0..<11 {
            if names[i] != parts[i].name {
                parts[i].set(names[i], names[i].isEmpty ? [] : Self.faceGlyph(names[i], l.pose))
                if !faceStarted { parts[i].b = 1; parts[i].from = parts[i].to }
            }
            let w = TAU * 4.2
            parts[i].bv += (-w * w * (parts[i].b - 1) - 2 * 0.68 * w * parts[i].bv) * dt
            parts[i].b += parts[i].bv * dt
        }
        faceStarted = true
        let e = min(1, dt * 10)
        gazeK += (l.look - gazeK) * e; aim += (l.aim - aim) * e
        spiralK += ((l.spirals ? 1 : 0) - spiralK) * min(1, dt * 8)
    }
    private var faceStarted = false

    // MARK: input

    func motion(_ r: Rig, _ ax: Double, _ ay: Double, _ az: Double) {
        let g = sqrt(ax * ax + ay * ay + az * az)
        if g > 0.3 { yarn.jolt(P2(-ax, -ay) * 900, hard: max(0, g - 1.1)) }       // the thread swings, its turns come loose
        let lat = sqrt(ax * ax + ay * ay)
        let c = cos(-(rot + tilt)), s = sin(-(rot + tilt))
        if lat > 0.3 {
            // the body is thrown against the move and wobbles like jelly
            let dir = P2(-ax, -ay) / lat
            jellyV += dir * ((min(2.5, lat) - 0.3) * 30)
            if g <= 1.25 {
                // a small move: the outer loops lag behind it, the knot barely
                let k = (lat - 0.3) * 30
                let a = P2(dir.x * c - dir.y * s, dir.x * s + dir.y * c) * k
                for i in pos.indices { let out = min(1.2, simd_length(pos[i]) / 110); vel[i] += a * (out * out) }
            }
            busyAt = t
        }
        if g > 1.25 {
            // shaken: its loops fly loose and tangle
            tangle = min(1, tangle + (g - 1.1) * 0.05); tanglePeak = max(tanglePeak, tangle); lastShake = t
            let push0 = P2(-ax, -ay) * (g * 16)
            let push = P2(push0.x * c - push0.y * s, push0.x * s + push0.y * c)
            for i in pos.indices {
                let x = Double(i)
                let jit = P2(sin(x * 0.13 + t * 9), cos(x * 0.11 + t * 7)) * (g * 14)
                let out = min(1.3, simd_length(pos[i]) / 110)                 // the knot's small loops barely jostled
                vel[i] += push + jit * (out * out)
            }
            busyAt = t
        }
    }
    func crown(_ r: Rig, _ delta: Double) {
        crownIdle = 0; busyAt = t
        // the crown is its spool: one way reels the thread in off the ball, the other feeds it back; once it's all wound,
        // turning on winds it tighter (it squints with the effort and boings loose when you let go)
        if delta > 0 && yarn.off <= 0 { wound = min(1, wound + delta * 0.05); woundV = 0 }
        else if delta < 0 && wound > 0.02 { wound = max(0, wound + delta * 0.05); woundV = 0 }
        else if yarn.crown(delta) { r.onHaptic?(.click); tugT = 0; squash.v += delta > 0 ? -0.4 : 0.3 }
    }
    func touched(_ r: Rig, at pt: CGPoint) { finger = pt; lastTouch = pt; busyAt = t; onThread = yarn.touch(P2(pt.x, pt.y)) }
    private var onThread = false
    func dragged(_ r: Rig, at pt: CGPoint) {
        // on the thread: it's pulled along; on the ball: it rolls the way your finger goes
        if let f = finger { yarn.drag(from: P2(f.x, f.y), to: P2(pt.x, pt.y)); if !onThread { jellyV += P2(pt.x - f.x, pt.y - f.y) * 0.3 } }
        finger = pt; busyAt = t
    }
    func released(_ r: Rig) {
        yarn.release(); onThread = false
        if let f = finger, pluck > 0.3 {
            // let go: the threads it had pulled snap back with a twang, the ball wobbles back
            twang(at: f, strength: 150 * pluck)
            let d = P2(f.x, f.y) - center, l = max(1, simd_length(d))
            jellyV += d / l * -40 * pluck
        }
        finger = nil
    }
    func poke(_ r: Rig) {
        pokes = pokes.filter { t - $0 < 3 } + [t]
        yarn.tap()
        if let p = lastTouch {
            twang(at: p, strength: 170)
            let d = P2(p.x, p.y) - center, l = max(1, simd_length(d))
            jellyV += d / l * -55
        }
        squash.v -= 3
        switch state {
        case .blocked: crossT = max(crossT, 1.2)                         // crosser
        case .dizzy: break                                               // it's too dizzy to mind
        case .sleep: startle = 1.1; hop.v = -90                          // woken with a start, then back to sleep
        default:
            if pokes.count >= 4 { pokes = []; crossT = 2.2; startle = 0 }
            else if crossT <= 0 { startle = 0.9; hop.v = -130; squash.v -= 0.4 }
        }
        busyAt = t
    }
    func pet(_ r: Rig) { petT = 0.45; busyAt = t }
    func deny(_ r: Rig) { crossT = 1.2 }
    func hit(_ pt: CGPoint) -> Bool { simd_length(P2(pt.x, pt.y) - yarn.center) < yarn.radius + 14 }

    // MARK: drawing

    func draw(_ r: Rig, _ ctx: GraphicsContext) {
        // dimmed: drawn as one layer at half strength (piece by piece, the overlaps would show through lighter)
        if r.ao { var c = ctx; c.opacity = 0.5; c.drawLayer { l in self.paint(r, l) } } else { paint(r, ctx) }
    }

    private func paint(_ r: Rig, _ ctx: GraphicsContext) {
        let p = r.pose(raw: true)
        let g0 = ctx
        let sc = scale
        let L = mood[Y.life.rawValue]
        let bob = cur.bob * sin(t * TAU * 0.45) - (state == .listening ? r.voice * 5 : 0)
        let breathe = cur.breathe * sin(t * TAU / 3.6)
        let morph = 0.03 * L * sin(ph * 0.9)                               // it shifts its shape: wider, then taller
        let tremble = cur.tremble * sin(t * 113) * (0.6 + 0.4 * sin(t * 7))
        let stretch = P2(clamp(abs(dragV.x) * 0.0006, 0, 0.1), clamp(abs(dragV.y) * 0.0006, 0, 0.1))
        let pulse = 1 + 0.05 * bump
        // the floating pose's shadow stays on the ground
        if shadowK > 0.05 {
            var s = g0.faded(shadowK); s.translateBy(x: center.x, y: center.y); s.scaleBy(x: Self.K * sc * (1 - bob * 0.012), y: Self.K * sc)
            for d in ScribbleArt.deco("11") where d.kind == 3 { s.fill(Strokes.smoothClosed(d.pts), with: .color(Self.blue)) }
        }
        var b = g0
        b.translateBy(x: center.x + tremble + jelly.x * 0.3, y: center.y + hop.y + bob + jelly.y * 0.3)
        b.rotate(by: .radians(tilt))
        // jelly: stretched along the way it was thrown, narrower across
        let jl = simd_length(jelly)
        if jl > 0.05 {
            let ja = atan2(jelly.y, jelly.x), jk = min(0.14, jl / 160)
            b.rotate(by: .radians(ja)); b.scaleBy(x: 1 + jk, y: 1 - 0.6 * jk); b.rotate(by: .radians(-ja))
        }
        b.scaleBy(x: Self.K * sc * pulse * (1 + stretch.x - stretch.y * 0.5 - squash.k * 0.5 - breathe * 0.5 + morph),
                  y: Self.K * sc * pulse * (1 + stretch.y - stretch.x * 0.5 + squash.k + breathe - morph))
        yarn.draw(g0, color: Self.blue)
        drawDeco(b, r: r)
        // the face on the ball's front (smaller as the ball gets smaller, never too small to read)
        var f = g0
        f.translateBy(x: yarn.center.x + faceOff.x, y: yarn.center.y + bob + faceOff.y - yarn.radius * 0.05)
        f.scaleBy(x: Self.K * sc * yarn.faceK, y: Self.K * sc * yarn.faceK)
        drawFace(f, r: r, pose: p)
        // subagents: small balls of yarn going round it
        if minis > 0.02 {
            for k in 0..<3 {
                let a = t * 0.75 + Double(k) * TAU / 3, c = P2(cos(a) * 84, sin(a) * 74) * minis
                var m = g0.faded(minis); m.translateBy(x: center.x + c.x, y: center.y + c.y)
                let rot = t * (1.2 + 0.3 * Double(k)) + Double(k)
                m.scaleBy(x: Self.K * 0.24, y: Self.K * 0.24)
                var ball = m; ball.rotate(by: .radians(rot))
                ball.stroke(Self.mini, with: .color(Self.blue), style: StrokeStyle(lineWidth: Self.W * 1.6, lineCap: .round, lineJoin: .round))
                for side in [-1.0, 1.0] { m.fill(Path(ellipseIn: CGRect(x: side * 22 - 9, y: -16, width: 18, height: 26)), with: .color(Self.faceInk)) }
            }
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext) {}

    /// The line, in one flat colour: smoothed so it never turns tighter than `minRadius`, the knot under the face with a
    /// wider pass of itself underneath, so the face always sits on wire, never on a gap.
    private func drawLine(_ g: GraphicsContext) {
        // evenly spaced along the line, half a stroke apart, then relaxed wherever it turns too tight
        var len = 0.0, lenK = 0.0
        for i in 1..<pos.count { len += simd_length(pos[i] - pos[i - 1]); if i == Self.kN { lenK = len } }
        guard len.isFinite && len > 1 else { return }
        let n = max(64, min(1400, Int(len / Self.step)))
        drawn = Strokes.resample(pos, n)
        Self.relax(&drawn)
        let line = StrokeStyle(lineWidth: Self.W, lineCap: .round, lineJoin: .round)
        let knotW = 1 - clamp(mood[Y.swirl.rawValue], 0, 1)
        if knotW > 0.05 {
            var under = Path(); Self.addRun(&under, drawn, 0, Int(Double(n - 1) * lenK / max(1, len)))
            g.stroke(under, with: .color(Self.blue), style: StrokeStyle(lineWidth: Self.W * (1 + 0.6 * knotW), lineCap: .round, lineJoin: .round))
        }
        var all = Path(); Self.addRun(&all, drawn, 0, drawn.count - 1)
        g.stroke(all, with: .color(Self.blue), style: line)
    }

    /// The line is made smooth where it's made (loops never smaller or sharper-ended than `minRadius`, each loop always
    /// turning on ahead of the hand that draws it); this only rounds off a kink the springs might fold in a fast move.
    /// (Easing every tight spot toward its neighbours would shrink a small loop tighter, so loops are left alone.)
    static func relax(_ p: inout [P2]) {
        let n = p.count
        guard n > 4 else { return }
        for _ in 0..<20 {
            var changed = false
            for i in 1..<(n - 1) {
                let a = p[i] - p[i - 1], b = p[i + 1] - p[i]
                let la = simd_length(a), lb = simd_length(b)
                let th = la > 1e-6 && lb > 1e-6 ? acos(clamp(simd_dot(a, b) / (la * lb), -1, 1)) : Double.pi
                if th > kink {
                    for j in max(1, i - 1)...min(n - 2, i + 1) {
                        let mid: P2 = (p[j - 1] + p[j + 1]) * 0.5
                        p[j] += (mid - p[j]) * (j == i ? 0.5 : 0.25)
                    }
                    changed = true
                }
            }
            if !changed { break }
        }
    }

    /// The shortest way from `p0` heading `h0` to `p1` heading `h1` that never turns tighter than `rho` (an arc, a
    /// straight, an arc: the four Dubins ways, the shortest kept), as `count` points evenly along it, the first a step on.
    static func dubins(_ p0: P2, _ h0: Double, _ p1: P2, _ h1: Double, _ rho: Double, count: Int, keep: inout Int) -> [P2] {
        func rot90(_ v: P2) -> P2 { P2(-v.y, v.x) }
        let u0 = P2(cos(h0), sin(h0)), u1 = P2(cos(h1), sin(h1))
        typealias Way = (len: Double, c0: P2, s0: Double, a0: Double, q0: P2, q1: P2, c1: P2, s1: Double, a1: Double)
        var best: Way? = nil, bestKind = -1, kept: Way? = nil
        for (kind, (s0, s1)) in [(1.0, 1.0), (-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0)].enumerated() {   // +1 turns toward +90°
            let c0: P2 = p0 + rot90(u0) * (rho * s0), c1: P2 = p1 + rot90(u1) * (rho * s1)
            let v: P2 = c1 - c0, d = simd_length(v)
            var u: P2
            if s0 == s1 {
                guard d > 1e-6 else { continue }
                u = v / d
            } else {
                guard d > 2 * rho else { continue }
                let beta = atan2(v.y, v.x), phi = beta + s0 * asin(2 * rho / d)
                u = P2(cos(phi), sin(phi))
            }
            let q0: P2 = c0 - rot90(u) * (rho * s0), q1: P2 = c1 - rot90(u) * (rho * s1)
            let straight = simd_dot(q1 - q0, u)
            guard straight >= -1e-6 else { continue }
            func sweep(_ from: P2, _ to: P2, _ sgn: Double) -> Double {
                let a = atan2(from.y, from.x), b = atan2(to.y, to.x)
                var x = (b - a) * sgn; x = x.truncatingRemainder(dividingBy: TAU); if x < 0 { x += TAU }; return x
            }
            let a0 = sweep(u0, u, s0), a1 = sweep(u, u1, s1)
            let len = rho * (a0 + a1) + straight
            let way: Way = (len, c0, s0, a0, q0, q1, c1, s1, a1)
            if kind == keep { kept = way }
            if best == nil || len < best!.len { best = way; bestKind = kind }
        }
        // keep last frame's way unless another is clearly shorter (switching would make the arm jump)
        if let k = kept, let b = best, k.len < b.len * 1.15 { best = k } else { keep = bestKind }
        guard let b = best else { return (1...count).map { (j: Int) -> P2 in p0 + (p1 - p0) * (Double(j) / Double(count)) } }
        let l0 = rho * b.a0, ls = simd_length(b.q1 - b.q0)
        return (1...count).map { k in
            let x = b.len * Double(k) / Double(count)
            if x <= l0 {
                let start: P2 = p0 - b.c0, ang = b.s0 * x / rho
                return b.c0 + P2(start.x * cos(ang) - start.y * sin(ang), start.x * sin(ang) + start.y * cos(ang))
            } else if x <= l0 + ls {
                return b.q0 + (b.q1 - b.q0) * ((x - l0) / max(1e-9, ls))
            } else {
                let start: P2 = b.q1 - b.c1, ang = b.s1 * (x - l0 - ls) / rho
                return b.c1 + P2(start.x * cos(ang) - start.y * sin(ang), start.x * sin(ang) + start.y * cos(ang))
            }
        }
    }

    /// Smooth value noise, −1…1, one random value at each whole `x` (the same every time for a seed), eased between.
    @inline(__always) static func vn(_ x: Double, _ seed: Double) -> Double {
        let i = floor(x), f = x - i, e = f * f * f * (f * (f * 6 - 15) + 10)
        let a = Strokes.hash(i, seed), b = Strokes.hash(i + 1, seed)
        return (a + (b - a) * e) * 2 - 1
    }

    /// A run of the line's points as a smooth subpath (a curve through the midpoints).
    private static func addRun(_ path: inout Path, _ p: [P2], _ a: Int, _ b: Int) {
        guard b > a else { return }
        path.move(to: CGPoint(x: p[a].x, y: p[a].y))
        if b - a == 1 { path.addLine(to: CGPoint(x: p[b].x, y: p[b].y)); return }
        for i in (a + 1)..<b {
            let m = (p[i] + p[i + 1]) * 0.5
            path.addQuadCurve(to: CGPoint(x: m.x, y: m.y), control: CGPoint(x: p[i].x, y: p[i].y))
        }
        path.addLine(to: CGPoint(x: p[b].x, y: p[b].y))
    }
    /// The small balls: a short line wound round.
    private static let mini: Path = {
        var p: [P2] = []
        for i in 0..<90 {
            let s = Double(i) / 89, th: Double = TAU * 5 * s, c: P2 = P2(cos(TAU * 1.2 * s), sin(TAU * 1.2 * s)) * 30
            let reach: Double = 52 + 10 * sin(TAU * 3 * s)
            p.append(c + P2(cos(th), sin(th) * 0.8) * reach)
        }
        var path = Path(); addRun(&path, p, 0, p.count - 1)
        return path
    }()

    /// The sheet's sparkles twinkle round it when it's done, its sweat when it's frazzled.
    private func drawDeco(_ g: GraphicsContext, r: Rig) {
        if sparkle > 0.02 {
            for (i, d) in ScribbleArt.deco("01").enumerated() where d.kind == 1 {
                let c = Self.centroid(d.pts), ph = t * 5 + Double(i) * 1.7
                let grow: Double = state == .done ? outQ(min(1, stateT / 0.5)) : 1
                let k: Double = (0.7 + 0.3 * sin(ph)) * sparkle * grow, home: P2 = c * (0.9 + 0.1 * sparkle)
                let pts: [P2] = d.pts.map { (q: P2) -> P2 in home + (q - c) * k }
                g.faded(sparkle * (0.75 + 0.25 * sin(ph))).fill(Strokes.smoothClosed(pts), with: .color(Self.blue))
            }
        }
        let sweat = shown.sw.isEmpty ? 0.0 : 1.0
        if sweat > 0 {
            for (i, d) in ScribbleArt.deco("12").enumerated() where d.kind == 2 {
                let off = P2(0, (t * 0.9 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1) * 6)
                g.fill(Strokes.smoothClosed(d.pts.map { $0 + off }), with: .color(Self.blue))
            }
        }
    }

    /// The dizzy eyes: a spiral, two and a half turns out from the middle.
    private static let spiral: Path = {
        var pts: [P2] = []
        for i in 0...60 {
            let u = Double(i) / 60, a = u * 1.6 * TAU
            pts.append(P2(cos(a), sin(a)) * (3 + 17 * u))
        }
        var path = Path(); addRun(&path, pts, 0, pts.count - 1)
        return path
    }()

    /// The face: dark marks (a light tongue) on the yarn, each on a rim of the yarn's own colour so it reads even over a
    /// gap between wires; it follows the finger and the gaze, blinks, pops to each new expression and lags the body.
    private func drawFace(_ g0: GraphicsContext, r: Rig, pose p: Pose) {
        var e = p.eye
        if let f = finger {
            let d = P2(f.x, f.y) - center, l = max(1, simd_length(d))
            e.gx = d.x / l * min(1, l / 30); e.gy = d.y / l * min(1, l / 30)
        }
        if state == .working { e.gx = sin(t * 2.4) * 0.9; e.gy = 0.35 }
        let gaze = P2(clamp(e.gx, -1, 1) * 7, clamp(e.gy, -1, 1) * 5.5) * gazeK + aim
        let open = r.ao ? 1 : clamp(e.open, 0, 1)
        var g = g0
        g.translateBy(x: gaze.x * 0.4, y: gaze.y * 0.4)
        let k = Self.faceScale * (1 + 0.12 * pop.k)
        g.scaleBy(x: k, y: k)
        var marks = Path(), tongue: Path? = nil
        for i in 0..<11 where parts[i].shown {
            var pts = parts[i].shape
            if i == 6 && state == .speaking && parts[6].name == "00.m" && fidget <= 0 && petT <= 0 {
                pts = Strokes.mix(pts, Self.faceGlyph("01.m@00.m*0.85", "00"), clamp(r.voice * 1.5, 0, 1))
            }
            if i < 4 {                                               // eyes: the gaze, and a blink for open ones
                let c = Self.centroid(pts)
                let n = parts[i].name
                let isOpen = n.hasPrefix("21.e") || n.hasPrefix("01.e") || n.hasPrefix("02.e") || n.hasPrefix("12.e")
                pts = pts.map { q in P2(q.x + gaze.x * 0.6, isOpen ? c.y + (q.y - c.y) * max(0.12, open) + gaze.y * 0.6 : q.y + gaze.y * 0.6) }
            }
            if i == 10 { tongue = Strokes.smoothClosed(pts) } else { marks.addPath(Strokes.smoothClosed(pts)) }
        }
        // dizzy: spiral eyes where its eyes are, turning
        var spirals = Path()
        if spiralK > 0.02 {
            for (side, name) in [(1.0, "12.eL"), (-1.0, "12.eR")] {
                let c = ScribbleArt.anchor(name) - ScribbleArt.faceOrigin("12")
                let a = t * 5 * side
                let tr = CGAffineTransform(rotationAngle: a).scaledBy(x: spiralK, y: spiralK)
                    .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
                spirals.addPath(Self.spiral.applying(tr))
            }
        }
        g.fill(marks, with: .color(Self.faceInk))
        if let tg = tongue { g.fill(tg, with: .color(Self.blue)) }
        if spiralK > 0.02 {
            g.stroke(spirals, with: .color(Self.faceInk), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Tangle's face marks and its decorations, traced from its character sheet (refs/scribble-reference.png), in pixels
/// of the sheet (cells 341 px), each pose's round its own middle, y down; little-endian Int16 eighths of a pixel, base64.
/// Poses by their place on the sheet: 00 calm · 01 excited · 02 worried · 10 angry · 11 floating · 12 frazzled ·
/// 20 puddle · 21 reaching · 22 swirl. Decorations: 1 sparkles, 2 sweat, 3 the floating shadow, 4 motion strokes. Face
/// marks are 64 points, leftmost first, clockwise, so any two blend; "21.eL@00.eL*0.8" is 21's left eye moved onto 00's
/// and scaled.
enum ScribbleArt {
    static let N = 64
    private static func values(_ s: String) -> [Double] {
        guard let d = Data(base64Encoded: s) else { return [] }
        let b = [UInt8](d)
        return stride(from: 0, to: b.count - 1, by: 2).map { (i: Int) -> Double in
            let bits: UInt16 = UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
            return Double(Int16(bitPattern: bits)) / 8
        }
    }
    private static let decos: [String: [(kind: Int, pts: [P2])]] = decoRaw.mapValues { raw in
        let v = values(raw.1), h = raw.0
        var vi = 0, out: [(kind: Int, pts: [P2])] = []
        for k in 0..<h[0] {
            let kind = h[1 + 2 * k], n = h[2 + 2 * k]
            out.append((kind, (0..<n).map { j in P2(v[vi + 2 * j], v[vi + 2 * j + 1]) })); vi += 2 * n
        }
        return out
    }
    static func deco(_ pose: String) -> [(kind: Int, pts: [P2])] { decos[pose] ?? [] }
    private static let marks: [String: [P2]] = faceRaw.mapValues { s in
        let v = values(s); return stride(from: 0, to: v.count - 1, by: 2).map { P2(v[$0], v[$0 + 1]) }
    }
    /// The middle of a mark's box (where another mark goes when it takes its place).
    static func anchor(_ n: String) -> P2 {
        if let g = marks[n] {
            var lo = P2(1e9, 1e9), hi = P2(-1e9, -1e9)
            for q in g { lo = simd_min(lo, q); hi = simd_max(hi, q) }
            return (lo + hi) * 0.5
        }
        if n.hasSuffix(".eL") || n.hasSuffix(".eR") { return .zero }
        let p = String(n.prefix(2))                                     // a pose without that mark: under its eyes
        return (anchor(p + ".eL") + anchor(p + ".eR")) * 0.5 + P2(0, 26)
    }
    /// The eyes' places in each pose.
    static let anchors: [String: (String, String)] = [
        "00": ("00.eL", "00.eR"), "01": ("01.eL", "01.eR"), "02": ("02.eL", "02.eR"), "10": ("10.eLa", "10.eRa"),
        "11": ("11.eL", "11.eR"), "12": ("12.eL", "12.eR"), "20": ("20.eL", "20.eR"), "21": ("21.eL", "21.eR"),
    ]
    /// A face's middle: between its eyes.
    static func faceOrigin(_ pose: String) -> P2 {
        guard let a = anchors[pose] else { return .zero }
        return (anchor(a.0) + anchor(a.1)) * 0.5
    }
    /// A mark by name: "00.m", or "21.eL@00.eL" (moved onto another's place), with "*0.8" to scale it there.
    static func glyph(_ name: String) -> [P2] {
        var n = Substring(name), k = 1.0
        if let s = n.firstIndex(of: "*") { k = Double(n[n.index(after: s)...]) ?? 1; n = n[..<s] }
        guard let at = n.firstIndex(of: "@") else { return marks[String(n)] ?? marks["00.m"]! }
        let src = marks[String(n[..<at])] ?? marks["00.m"]!, to = anchor(String(n[n.index(after: at)...]))
        let from = anchor(String(n[..<at]))
        return src.map { to + ($0 - from) * k }
    }
    private static let decoRaw: [String: ([Int], String)] = [
        "01": ([12, 1, 58, 1, 16, 1, 38, 1, 17, 1, 24, 1, 28, 1, 20, 1, 15, 1, 11, 1, 29, 1, 27, 1, 46], "wAPb+7wD5Pu7A/H7uAP++7QDC/yxAxf8qwMj/KUDL/ydAzn8lANC/IoDSvx/A1D8dANV/G0DW/xsA2L8cANo/HgDbfyEA3D8jwN1/JkDffyiA4b8qgOQ/LEDm/y3A6f8uwOz/L4DwPzCA838xgPW/M0D2fzUA9f82APR/NsDx/zdA7r84QOu/OUDofzqA5X88QOJ/PgDf/wBBHX8CwRt/BUEZ/weBGH8IwRa/CIEVPwbBE/8EQRK/AYEQ/z8Azz88gMy/OsDKPzkAx384AMR/NwDBPzZA/b71QPp+9ID3vvNA9j7xgPX+7ACBPyoAgz8pAIV/KQCIPynAin8rQIx/LUCNfy9AjX8xgIy/M0CKvzSAiH80wIX/NACDvzKAgX8wwIB/LkCAPxw+4L8avuJ/Gj7kvxr+538cPun/Hf7sfyB+7v8i/vF/JT7z/yd+9j8p/vh/LH76/y7+/X8xfv+/M/7B/3Z+xD95PsZ/e77H/35+yH9Avwg/Qj8G/0J/BP9B/wJ/QL8/vz7+/P88vvp/On73vzf+9T81fvK/Mv7wPzC+7f8uPuu/K37pfyj+5v8mPuS/I37ifyD+4P8efuA/FcEK/1NBC79RAQ0/T4EPP08BEb9PQRQ/UIEWf1JBGD9UgRj/VwEYv1lBF/9bARX/XEETv1yBEP9cAQ6/WoEMv1iBC39pwNE/Z8DRv2aA079lQNZ/Y4DZP2HA2z9hANz/YcDev2QA4H9mAOI/ZsDkv2eA5z9pAOf/asDnv2vA5f9sQON/bUDg/2+A3v9xANy/cYDav3AA2T9twNf/bADV/2sA039X/tk/VT7Z/1M+2z9Sftz/Uz7e/1S+4H9XfuG/Wn7i/12+5D9g/uU/Y/7mP2d+5z9qvug/bj7o/3E+6b9zvul/dX7n/3Y+5j91vuQ/c/7if3G+4L9u/t9/a77eP2h+3P9lPtv/Yf7av16+2f9bftl/ccDywG/A9ABuwPYAbwD4QHCA+kBywPxAdcD+QHjA/8B7wMEAvsDBgIFBAQCDQT+ARIE9gESBO0BDQTkAQUE3QH6A9YB7gPRAeADzgHTA8oBiPvqAYD78gF8+/sBfPsGAn/7DwKH+xUCkPsYApr7FgKj+xECqfsJAqv7AAKp+/YBpPvtAZz76AGS++cBKPxIAiH8TwIf/FcCIfxfAij8ZAIw/GQCN/xgAjz8WQI8/FECOPxKAjD8RgKo+58CofumApz7sAKX+7sCj/vDAoT7ygJ++9ECf/vYAoX73QKO++ECl/vnAp378AKh+/sCpvsEA6z7BwOz+wUDuPv+Arz79ALA++kCx/vhAtD72gLW+9MC1vvLAtH7xQLJ+8ECwPu9Arv7tAK2+6kCsPuhAtgDswLTA7oC0wPCAtgDywLgA9YC6QPgAvMD6gL9A/QCCAT9AhQEBQMfBA0DKgQSAzUEFAM+BBEDRgQLA0gEAwNHBPsCQQTxAjgE5wIuBN4CJATVAhgEzgINBMYCAgS/AvcDtwLsA7IC4gOwAmD84QJb/OgCWPzyAlT8/wJR/AwDS/wYA0T8IgM7/CwDMvw1Ayj8PQMi/EQDI/xLAyr8UAM0/FUDQPxcA0n8ZANP/G4DVPx5A1j8hgNb/JMDX/ygA2P8qgNp/LADcfywA3f8rAN5/KMDevyYA3v8igN9/H0DgPxxA4b8ZQON/FsDlvxTA6D8SwOo/EQDqfw9A6X8NwOc/DIDkfwsA4f8IwN//BoDefwPA3T8AgNv/PYCa/zqAmf84gI="),
        "11": ([1, 3, 196], "O/+zBC3/tAQf/7QEEv+1BAT/tgT2/rYE6P63BNr+twTM/rgEvv65BLH+uwSj/rsElf68BIf+vQR5/r4Ea/7ABF7+wQRQ/sIEQ/7DBDX+xQQo/sYEGv7HBAz+yAT+/ckE8f3MBOP9zgTV/dAEyP3SBLv91QSu/dcEof3aBJP93QSH/eEEe/3mBHL97QRs/fQEav38BGz9BAVy/QsFev0RBYX9FgWR/RoFnv0fBav9IgW4/SUFxf0nBdP9KQXh/SsF7/0tBf39LwUL/jAFGf4yBSf+MwU1/jUFQ/42BVD+NwVe/jcFbP44BXn+OgWH/jsFlf48BaP+PQWx/j4Fv/4/Bc3+QAXb/kAF6P5ABfb+QQUD/0EFEP9CBR3/QwUr/0QFOP9EBUb/RQVT/0UFYf9HBW7/RwV8/0gFiv9IBZn/RwWn/0cFtf9HBcP/RwXR/0cF3/9HBez/RwX6/0cFCABHBRYARwUlAEcFMwBGBUAARwVOAEcFXABGBWoARgV4AEYFhgBGBZQARQWiAEUFsABFBb4ARQXMAEQF2gBDBegAQgX2AEIFBAFBBRIBQAUgAT8FLgE/BTwBPgVJAT4FVwE8BWUBOwVzATkFgQE4BY8BNwWdATYFqwE1BbkBMwXHATEF1QEvBeMBLQXwASsF/QEpBQsCKAUYAiYFJQIkBTICIAU/Ah4FSwIaBVgCFgViAhAFawIKBXICAgV0AvoEcgLyBG0C6wRkAuUEWQLfBE0C2wRBAtcENALVBCcC0wQaAtAEDALNBP8BywTxAckE4wHHBNYBxgTIAcQEugHCBKwBwASeAb8EkQG+BIMBvQR1AbwEZwG6BFoBuQRMAbgEPQG4BC8BtwQhAbcEEwG2BAUBtgT3ALUE6QC0BNsAswTNALIEvwCxBLEAsASjAK8ElQCvBIcArwR6AK4EbACuBF4ArQRQAK0EQgCtBDQArQQmAK0EGACtBAoArAT8/60E7v+tBOD/rQTT/60Exf+tBLf/rgSq/64EnP+vBI7/rwSA/68Ecv+wBGT/sARW/7EESf+yBA=="),
        "12": ([4, 2, 59, 2, 54, 2, 41, 2, 38], "1vvv/M379/zF+//8wPsJ/b/7FP3B+x/9xvsq/c37Mv3X+zr94vtB/e77Rv36+0v9CPxP/RX8U/0h/FT9LvxU/Tf8Uv05/E39NvxI/S78Q/0j/D39F/w4/Qr8NP3/+y798/sp/ej7I/3h+xz93vsU/eD7Df3n+wn98fsH/fz7CP0I/Az9FPwR/SH8Fv0s/B39N/wl/UH8Lf1K/Df9U/xB/Vz8Sv1k/FD9bPxS/XH8Tv1x/Ef9bvw+/Wf8Nf1f/Cr9Vvwf/Uz8Fv1C/A39N/wF/Sz8/fwg/Pf8FPzy/An87fz8++z87vvr/OL77Pz2A3H96QNz/dwDd/3QA3z9xQOD/bkDiv2uA5L9pAOa/ZsDpP2SA679iwO5/YUDxP2DA839hQPV/YsD1/2RA9X9mQPO/aIDxP2tA7r9twOw/cEDp/3MA5/91gOX/eIDkf3uA439+gOL/QMEjP0KBJD9CwSX/QgEnf0ABKP99QOp/ekDsP3cA7b90QO9/cgDw/3FA8r9yQPP/dAD0f3aA9D95gPN/fIDyP3+A8T9CQS9/RQEtv0eBK79JQSl/SkEm/0pBJH9JgSH/SAEff0YBHb9DgRy/QIEcP3W+9j9yPvb/bz73/2x++T9pvvr/Z779P2Z+/79mPsI/pr7Ev6g+xr+qfsg/rP7JP6/+yT+y/sk/tf7If7k+xz+8PsV/vn7D/7++wr++vsG/vL7Bf7n+wX+2vsH/s77Cv7E+wr+v/sG/r77AP7D+/v9zPv3/dj78/3l+/D98/vt/QH86/0N/On9Fvzl/Rj84P0T/Nz9C/zZ/f/71/3y+9b95PvX/QYEOP75Azr+7QM9/uQDQf7gA0f+4wNM/uoDTf71A07+AgRP/g8EUv4cBFX+KQRY/jIEXf42BGL+MgRl/ikEaP4dBGr+EQRs/gcEb/4DBHT+BAR6/goEfv4TBID+IASA/i0EgP47BH/+RwR8/lAEeP5XBHD+WgRn/lkEXv5VBFX+TQRN/kQERv45BED+LQQ8/iAEOv4TBDj+"),
        "22": ([6, 4, 135, 4, 58, 4, 122, 4, 64, 4, 111, 4, 49], "Ov7F+y3+yfsg/sz7FP7R+wf+1fv7/dr77/3g++P95vvX/ev7y/3y+7/9+Pu0/f77qP0F/J39DPyR/RT8hf0b/Hn9I/xu/Sr8Y/0x/Ff9OfxM/UH8Qv1J/Df9Uvwr/Vr8If1j/Bb9a/wM/XT8Av1+/Pj8iPzu/JL85Pyc/Nr8pvzR/LD8x/y6/L78xfy2/M/8rfzZ/KT84/yc/O38lPz4/Iv8A/2E/A79fPwZ/XX8I/1u/C79Z/w6/WD8Rf1Z/FH9Uvxd/Uz8aP1G/HT9QPyA/Tr8jP01/Jj9L/yl/Sr8sf0l/L79IPzK/Rz81/0Y/OT9FPzx/RD8/f0O/Ar+DPwX/g38H/4S/CP+Ffwf/hn8Fv4e/An+I/z8/Sf88P0s/OP9MvzY/Tf8zP08/L/9Qvyz/Uf8p/1N/Jv9VPyQ/Vr8hP1h/Hj9aPxs/W/8YP12/FX9fvxJ/YX8Pv2M/DL9lPwn/Zv8HP2j/BH9rPwG/bT8+/y8/PD8xfzm/M383PzW/NL83vzJ/Oj8v/zx/LX8+/ys/AX9ovwP/Zn8GP2Q/CL9iPws/X78Nv12/ED9bfxL/WT8Vf1c/GH9U/xs/Uv8d/1D/IL9O/yO/TP8mf0s/KT9Jfyv/R38u/0V/Mb9D/zS/Qn83f0C/On9/Pv0/fb7AP7w+wz+6/sY/uX7JP7g+zD+2/s9/tb7Sv7R+1T+zfta/sj7WP7E+1L+wvtH/sP7Av0F/Pb8Cvzq/BD83vwX/NP8H/zI/Cf8vfww/LL8Ofyo/EL8nvxM/JX8VvyL/F/8gvxp/Hn8c/xw/H38Z/yI/F/8k/xX/J78T/yp/Ej8tPxB/MD8OvzM/DT82Pwu/OT8KPzv/CP8/Pwh/Af9IvwO/Sf8DP0s/Ab9Mvz8/Dn88PxA/OT8SPzZ/FD8zfxY/ML8X/y3/Gf8rPxw/KH8efyW/IP8i/yM/IH8lfx3/J/8bfyo/GL8svxZ/Lz8T/zH/Eb80fw9/Nv8NPzm/Cv88vwj/P38G/wI/RT8E/0M/Bj9B/wU/QP8Df0C/EsDHf1MAyP9UQMq/VkDNP1iA0D9agNL/XIDVv15A2L9gANt/YcDef2NA4X9lAOR/ZoDnf2hA6n9pwO1/a0Dwv2yA879uAPb/b0D6P3CA/T9xwMB/ssDDv7PAxv+0wMo/tYDNf7ZA0L+3ANQ/uADXf7jA2r+5QN4/ucDhv7pA5P+6wOh/u0Drv7vA7z+8APK/vID2P70A+b+9AP0/vUDAv/1AxH/9QMf//UDLf/0Azz/9ANK//MDWP/xA2b/8AN0/+8Dgv/uA5H/7AOe/+oDrP/nA7r/5QPI/+MD1f/gA+L/3QPv/9oD/P/XAwgA1gMSANkDFwDdAxQA4QMNAOUDAgDqA/b/7gPp//MD3P/2A9D/+QPD//0Dtv8ABKj/AwSb/wUEjf8GBID/CARx/woEZP8MBFb/DQRI/w0EOv8OBCv/DgQd/w4ED/8OBAH/DgTy/g0E5P4NBNb+DATI/goEuv4IBKz+BwSd/gUEj/4DBIL+AAR0/v4DZ/77A1r++ANN/vYDQP7zAzP+7wMn/usDGv7nAw7+4gMB/t0D9f3YA+j90wPc/c0D0P3IA8T9wgO3/bwDq/23A579sAOS/aoDhv2jA3r9nANu/ZQDYv2MA1f9gwNM/XoDQf1xAzf9ZwMu/V0DJf1TAx79OgS//TcExf04BM39PATX/UAE5P1FBPH9SQT+/U0EC/5QBBn+VAQl/lYEMv5ZBED+WwRO/l4EXP5gBGr+YgR5/mMEh/5kBJX+ZQSj/mUEsv5lBMD+ZQTO/mYE3f5lBOv+ZQT6/mUECP9kBBb/YwQk/2EEMv9gBD//YARM/2EEVP9jBFb/ZQRQ/2gERv9sBDv/bwQu/3MEIf92BBP/dwQG/3kE+P56BOr+fATb/n0Ezv59BMD+fQSx/n0Eo/57BJX+egSH/nkEef53BGv+dgRd/nQET/5yBEH+bwQz/mwEJv5oBBn+ZQQM/mAE//1bBPL9VgTm/VAE2/1IBND9QQTF/aP7lgCf+50AnfupAJ37tgCd+8QAnvvSAJ/74ACg++0Aovv7AKX7CAGn+xYBq/sjAa77MAGz+z0BtvtJAbv7VgG/+2IBxPtvAcn7ewHO+4gB1PuUAdn7oQHf+60B5fu5Aez7xgHz+9IB+vveAQL86QEJ/PUBEPwAAhj8DAIg/BcCKfwhAjL8KwI6/DYCQ/w/Akz8SQJV/FMCX/xcAmj8ZgJy/G8CfPx4Aob8gQKQ/IoCm/yTAqb8mwKx/KICvPyqAsf8sQLT/LgC3vy+Aun8xgL1/MwCAv3SAg392AIX/dsCHf3ZAh391AIW/c8CDP3IAgH9wAL1/LgC6fyxAt78qQLT/KACyPyYAr38jwKz/IUCqfx8Ap/8cwKU/GoCivxgAoD8VgJ2/E0CbPxDAmL8OQJZ/C8CT/wkAkf8GgI+/A8CNfwEAi38+QEm/O4BHvziARf81gEP/MsBCPy/AQL8tAH8+6gB9fucAe77kAHo+4QB4/t3Ad37agHY+14B0/tRAc77RQHK+zkBxvssAcP7HwG/+xMBvfsGAbn7+QC3++wAtfveALP70QCx+8MAr/u1AK77pwCt+5sAqfuVAJL7wwGN+8gBjfvRAY/73gGS++oBlvv3AZr7BAKg+xECpvsdAqz7KgK0+zUCu/tBAsT7TALM+1YC1vtgAuD7agLp+3QC8/t+Avz7hwIH/I8CEvyXAh78nQIq/KQCNvypAkL8rgJL/K8CTvytAkn8qAJA/KACNfyYAir8jwIf/IYCFfx9Agr8cwIA/GoC9/tgAu77VgLl+0sC3PtBAtT7NQLL+yoCxPsfArz7FAK1+wkCrvv9Aaj78QGi++UBnPvZAZb7zQE="),
    ]
    private static let faceRaw: [String: String] = [
        "00.eL": "Wv4R/13+Af9m/vP+dP7q/oT+5v6U/uv+of71/qj+BP+q/hT/rv4l/7L+NP+5/kT/wv5S/8z+Xv/Z/mn/5/5y//b+eP8H/3v/F/95/yf/dP81/2v/Qf9g/0v/U/9U/0X/Wv81/2D/Jv9o/xj/df8O/4X/C/+V/w7/o/8X/6n/J/+r/zf/qf9I/6X/WP+f/2f/l/92/4//hP+G/5L/e/+e/2//qv9i/7T/U/+8/0X/xP81/8r/Jf/O/xX/0P8E/9D/9P7O/+P+y//U/sb/xP6//7b+uP+o/q//m/6k/5D+mP+F/oz/e/5+/3P+cP9r/mH/Zv5R/2D+Qv9d/jH/Wv4h/w==",
        "00.eR": "4P9R/+H/QP/o/zD/8/8j/wIAHP8TAB7/IgAm/yoANP8vAET/MQBV/zUAZv86AHb/QgCF/0sAk/9XAJ//ZgCo/3UArv+GALP/lwCz/6cAsP+3AKr/xgCi/9MAl//eAIr/5wB8/+8Abf/2AF3//wBP/w4BR/8fAUX/LwFJ/zoBVv8/AWb/PwF3/zoBh/80AZf/LAGm/yMBtP8ZAcL/DwHP/wIB2//1AOX/5gDu/9cA9v/IAP3/twACAKcABQCWAAYAhQAGAHQABQBjAAMAUwD+/0QA9/81AO//JgDl/xoA2v8OAM7/BADA//v/sv/z/6L/7P+T/+f/g//i/3L/4f9i/w==",
        "00.m": "hf4hAIv+CgCf/v7/t/7//8r+DADY/h8A5v4zAPT+RgAF/1cAGP9mACv/cwBA/34AVv+IAGz/kQCD/5cAmv+dALL/ogDJ/6QA4f+kAPn/owARAJ8AKACaAD8AkwBVAIoAagCAAH8AdACSAGYApABWALYARgDMAD4A4wBDAPMAVAD3AGsA7wCBAN4AkgDMAKEAuACvAKQAvACQAMgAewDTAGUA3ABOAOQANwDqACAA8AAIAPQA8f/1ANn/9QDB//UAqf/0AJL/7wB6/+sAY//lAE3/3gA2/9UAIf/KAA3/vgD4/rEA5f6kANL+lQDA/oUAsP50AKD+YQCU/k0Aif44AA==",
        "01.eL": "4P50/+H+af/i/l7/4/5T/+T+SP/n/j7/6v4z/+z+KP/w/h7/8/4T//b+Cf/7/v/+//71/gT/6/4J/+H+D//Y/hf/0P4f/8j+J//C/jH/vf48/7n+Rv+5/lH/vP5b/8H+Y//I/mr/0f5v/9v+c//l/nT/8P51//v+dv8G/3b/Ef91/xz/dP8n/3P/Mv9y/z3/b/9I/2z/Uv9r/13/af9o/2X/cv9i/33/Xv+H/1v/kv9Y/5z/U/+m/03/sP9I/7n/Qf/C/zr/yv8x/9D/J//V/xz/1/8R/9j/B//U//3+z//1/sf/7v6+/+r+tP/l/qv/4v6g/+D+lf/g/or/4P5//w==",
        "01.eR": "OwCk/zsAmf88AI7/PACD/z0AeP8/AG3/QgBi/0QAV/9GAEz/SgBC/0wAN/9RAC3/VAAi/1kAGP9dAA7/YgAE/2gA+/5uAPH+dgDp/n4A4v6IAN3+kwDZ/p4A2f6pANz+sgDh/roA6f7AAPL+xAD8/skABv/LABH/zAAc/8wAKP/MADP/ywA+/8sASf/KAFT/yABf/8YAav/EAHX/wwCA/8EAi/+9AJX/uwCg/7kAq/+0ALX/sQC//6wAyf+oANT/ogDd/5sA5v+UAO7/iwD1/4IA+v93AP7/bAD+/2IA+v9YAPX/UADt/0oA5P9EANr/QQDQ/z0Axf88ALr/OwCv/w==",
        "01.m": "+v58APv+awD9/loACf9NABj/RAAp/0AAOv9AAEv/QABd/0AAbv9AAID/QACR/0AAov9AALT/QADF/z8A1v89AOf/OAD4/zgACgA3ABsANgAsADUAPgA2AE8ANwBfAD0AbgBGAHoAUgB+AGMAgwBzAH4AhAB7AJUAdgClAHIAtgBqAMUAYwDVAFsA5ABTAPMARwAAATwADgEzABwBJQAmARcAMQEKAD0B+v9CAer/SQHa/04Byf9QAbf/UAGm/08Blv9JAYb/QgF1/z4BZv83AVj/LAFK/yMBPf8XATH/CgEl//4AHf/uABX/3wAN/88ABv/AAAL/rwD9/p8A+/6NAA==",
        "01.tg": "bf8UAW3/DQFv/wcBc/8BAXf//AB8//cAgf/yAIf/7wCM/+sAkv/nAJj/5QCe/+EApf/gAKz/3gCy/9wAuf/aAL//2QDG/9gAzf/YANT/1wDb/9cA4f/XAOj/2ADv/9gA9v/ZAPz/2wADAN0ACQDfABAA4QAWAOQAHADnACEA6wAjAPIAIQD4AB4A/gAaAAMBFQAJAREADgEMABIBBwAXAQIAGwH8/x8B9v8jAfH/JwHr/ysB5f8uAd//MAHY/zIB0f8zAcr/NAHE/zQBvf8zAbb/MwGv/zIBqP8xAaL/MAGb/y8Blf8tAY7/KgGI/ygBgv8kAXz/IQF2/x4Bcf8ZAQ==",
        "02.bL": "QP4Z/0T+Df9P/gf/W/4D/2f+//5z/v3+f/76/ov+9v6X/vL+ov7t/q7+6f66/uT+xf7f/tH+2v7c/tX+5/7P/vL+yf79/sT+CP+8/hL/tv4c/67+Jv+m/i//nf44/5X+Qf+M/kr/g/5S/3r+W/9x/mX/af5x/2T+ff9l/ob/bf6I/3n+hP+F/n3/kP52/5r+bv+k/mb/rf5d/7b+U/++/kr/x/5A/8/+N//W/iz/3v4i/+X+F//s/g3/8v4B//j+9v79/uv+A//g/gj/1P4M/8j+Ef+8/hX/sf4a/6X+Hf+Z/iH/jf4l/4D+J/90/ir/aP4s/1v+LP9P/ir/RP4k/w==",
        "02.bR": "RQB5/kcAbf5PAGT+XABj/mYAav5vAHL+dwB8/oAAhf6IAI7+kQCX/pwAnv6lAKb+sACt/rsAsv7GALn+0QC+/twAxP7nAMr+8wDO/v4A0/4LAdb+FwHa/iMB3P4vAd7+PAHf/kgB4v5UAeT+YQHl/m0B5/55Aer+hgHt/o8B9f6RAQH/jQEM/4IBE/92ARX/agEW/10BFv9RARX/RAEU/zgBE/8rARH/HwEO/xMBDf8GAQr/+wAG/+8AA//jAP7+1wD7/ssA9v7AAPH+tQDr/qsA5P6gAN7+lgDW/owAzv6DAMb+egC9/nEAtP5oAKz+XwCi/lcAmf5QAI/+SQCE/g==",
        "02.eL": "4v6h/+b+m//p/pX/6P6O/+f+h//l/oH/5f56/+X+c//m/mz/6P5l/+r+X//v/lr/8v5U//f+T//8/kr/Av9G/wf/Qv8N/z7/FP88/xr/Of8g/zf/J/81/y7/Nf81/zX/PP81/0P/N/9J/zn/UP88/1b/Pv9c/0L/Yf9G/2b/S/9q/1H/bv9X/3D/Xf9x/2T/cv9r/3H/cv9w/3j/b/9//2z/hf9o/4v/Zf+R/2H/l/9c/5z/V/+h/1H/pf9M/6n/Rv+s/z//r/85/7L/M/+0/yz/tf8l/7b/Hv+3/xf/uP8Q/7n/Cv+4/wP/t//8/rX/9v6z//D+r//q/qz/5f6n/w==",
        "02.eR": "aAB5/2gAcv9oAGv/aQBk/2sAXf9uAFf/cQBR/3UAS/97AEb/gABC/4UAPf+MADv/kgA3/5gANf+fADP/pgAz/60AM/+0ADT/uwA1/8IAN//IADr/zgA+/9QAQv/ZAEb/3wBK/+QAT//oAFX/7ABb//AAYf/xAGf/8gBu//MAdf/zAHz/8gCD//EAiv/wAJH/7QCY//EAnf/2AKH/9wCo//IArP/rAK//5QCx/94AtP/XALX/0AC1/8kAtf/CALX/uwC1/7QAtP+uALL/pwCv/6AArf+aAKv/kwCo/40Apf+GAKP/gACg/3oAnP90AJj/cACT/2wAjf9pAIf/aACA/w==",
        "02.m": "7/6RAPD+ewD4/mcABf9WABj/SwAs/0UAQv9FAFj/RQBs/0AAe/8wAIj/HwCX/xAAqv8FAL/////U//3/6f8BAPz/DAANABkAHQAnADIAJwBFAB0AWAASAGwADACCAAsAlwANAKsAFgC9ACIAzAAxANkAQwDjAFYA7ABqAPMAfgD0AJMA5ACgANEAmQDFAIcAvQBzALUAXwCrAEwAnAA9AIgANABzADMAYAA9AE4ASgA6AFEAJQBSABAATAD//z8A7v8xANz/JgDG/yUAs/8uAKL/PACV/00Ahv9dAHT/aABf/20ASv9sADT/bAAf/3AAEf+AAAv/lQAG/6oA9P6lAA==",
        "10.eLa": "mv4h/53+FP+l/gr/sf4E/77+BP/L/gj/1/4N/+P+FP/u/hv/+v4h/wX/KP8R/y7/HP81/yj/O/80/0H/P/9H/0v/Tv9X/1T/Y/9Z/2//Xv97/2T/h/9q/5P/b/+f/3X/q/97/7j/f//E/4X/z/+M/9v/kf/n/5j/8f+g//n/qv/8/7f/+f/E/+//zf/j/9L/1v/S/8n/z/+8/8v/sP/G/6T/wP+X/7z/i/+3/3//sv9y/63/Z/+m/1v/of9P/5v/Q/+V/zj/j/8r/4n/IP+D/xT/ff8I/3f//P5x//D+a//l/mT/2v5e/87+WP/D/lH/t/5K/63+Qv+j/jn/nP4u/w==",
        "10.eLb": "sv7R/7j+w//F/r3/1P68/+P+vf/y/r7/Af+//xD/wP8f/8L/Lv/E/zz/xv9L/8n/Wv/M/2n/zf94/9D/hv/U/5X/2P+j/9z/sv/f/8D/5f/N/+3/1v/4/9r/BgDU/xQAyf8dALv/IwCt/ycAn/8sAJD/MACC/zYAdP87AGb/QABY/0YAS/9MAD3/UgAv/1cAIf9eABT/ZAAH/2wA+f5yAOr+dADc/nAA1P5kANf+VgDg/kkA6/4/APf+NgAD/y0AD/8lAB3/HgAq/xgAOP8SAEb/DQBJ/wMAO//+/yz//f8d//v/Dv/4///+9f/x/vH/4v7t/9P+6//G/uX/uf7e/w==",
        "10.eRa": "bQCZ/20AjP9wAID/dgB1/30Aa/+FAGH/jQBY/5UATv+dAET/pQA7/64AMv+2ACj/vgAf/8YAFf/OAAz/1gAC/94A+P7mAO/+7gDl/vcA3P7/ANL+BwHJ/g8Bv/4YAbb+IAGt/ikBpP4yAZv+OgGS/kUBi/5QAYf+XQGH/mgBjP5wAZb+dAGi/nIBrv5sAbn+ZgHE/l4Bzv5XAdj+TgHh/kYB6/4+AfX+NgH+/i4BCP8mARL/HwEb/xYBJP8NAS3/BQE3//wAQP/0AEn/6wBS/+MAW//aAGT/0QBt/8gAdf+/AH7/tgCH/60Aj/+kAJj/mQCf/44ApP+CAKX/dQCi/w==",
        "10.eRb": "nQDR/58Aw/+mALb/sACs/7sAo//HAJr/0wCR/94AiP/qAH//9QB3/wEBb/8NAWf/GQFf/yYBWP8zAVH/PwFK/0wBQ/9ZATz/ZgE2/3MBMP+BATP/iwE9/4oBS/+CAVf/eAFh/2wBav9hAXP/VQF7/0kBg/89AYz/MQGU/yYBnv8qAaX/OQGl/0cBpf9WAaX/ZAGl/3MBpv+BAaj/jwGs/50Br/+qAbb/swHB/7YBz/+wAdv/pAHk/5YB5/+HAeb/eQHl/2sB5f9cAeT/TgHk/z8B5P8wAeT/IgHk/xMB5P8FAeT/9gDl/+gA5v/aAOf/ywDo/70A6f+uAOb/owDe/w==",
        "10.m": "FP9BARb/KAEe/xEBK//8ADr/6ABK/9UAW//DAG3/sgCB/6MAlP+TAKn/hgC//3kA1P9tAOr/YgAAAFcAFwBOAC8ARwBHAEEAYAA9AHgANwCQADIAqQAuAMEALQDaACwA8wAtAAwBLgAkATMAPAE6AFMBRABoAVAAewFhAIsBdACWAYoAnAGiAJwBugCVAdIAiQHnAHYB9wBfAQEBRgEEAS0BBQEVAQMB/AABAeMA/gDLAP0AsgD9AJkA/gCBAAMBaQALAVIAEwE7AB4BJQAoAQ8AMwH4/z4B4/9KAcz/VQG2/2ABoP9rAYj/cgFw/3cBV/96AT//dgEo/2wBGf9ZAQ==",
        "11.eL": "3vuj/977lv/f+4n/4Pt8/+L7cP/m+2T/6vtY//T7T/8A/E3/CfxW/w38Yv8O/G//Dvx8/w78iP8O/JX/D/yi/xD8r/8T/Lv/FvzI/xz80/8n/Nf/MvzQ/zn8xf8//Lr/RPyu/0j8ov9N/Jb/UPyK/1T8ff9X/HH/Xfxm/2j8X/90/F3/gPxj/4j8bf+K/Hn/ifyG/4j8k/+G/KD/hPys/4D8uP99/MX/ePzR/3P83f9u/Oj/Z/zz/2D8/v9Y/AgAT/wQAET8FwA4/B0ALPwfAB/8HwAS/BwAB/wWAPz7DwD0+wUA7fv6/+j77//l++L/4vvW/+D7yf/e+7z/3vuw/w==",
        "11.eR": "v/yb/7/8iv/A/Hr/xfxq/9D8Xv/g/Fv/7vxj//b8cf/4/IH/+vyS//78ov8D/bL/CP3B/xH9z/8b/d3/J/3n/zb97/9G/fP/Vv3y/2b97P90/eT/gP3Z/4r9y/+S/b3/mP2u/579n/+k/Y//qP1//7H9cv+//Wj/z/1m/9/9av/p/Xb/7v2G/+79lv/r/af/5/22/+L9xv/b/dX/1P3k/8z98v/C/QAAuP0MAKz9GACf/SMAkf0rAIP9NABz/TkAY/08AFP9PQBC/T0AMv07ACL9NwAT/TAABP0pAPf8IADq/BQA4PwHANf8+v/Q/Ov/yfzc/8X8zP/B/Lz/v/yr/w==",
        "11.m": "9vujAPr7kAAL/IoAGvyXACX8pwAx/LcAPPzHAEn81QBY/OMAaPzuAHn8+ACL/AABnfwGAbH8CgHE/A0B2PwOAev8DQH+/AgBEv0EAST9/QA2/fQARv3qAFb93gBk/dEAcv3CAH79swCJ/aMAlv2UAKb9iQC5/YkAyf2UANL9pQDQ/bkAyf3LAL/92wC0/ewAp/37AJn9CQGL/RYBfP0jAWv9LgFb/TgBSf1BATf9SAEk/U4BEf1TAf78VgHq/FcB1vxXAcP8VgGv/FMBnPxPAYn8SQF3/EMBZfw6AVT8MAFE/CYBNfwZASb8DAEZ/P0AD/zsAAb82wD9+8kA9/u2AA==",
        "12.eL": "1P6p/9T+ov/V/pz/1/6W/9n+j//b/on/3v6D/+H+fv/k/nj/6f5z/+7+b//y/mr/+P5n//7+ZP8E/2L/Cv9g/xH/Xv8X/17/Hv9f/yT/Yf8q/2P/MP9l/zb/af87/23/P/9x/0P/d/9G/3z/Sv+C/0z/iP9N/4//Tv+V/0//nP9Q/6L/T/+p/07/r/9M/7X/S/+8/0n/wv9G/8j/RP/O/0D/1P88/9n/OP/d/zP/4v8u/+b/KP/o/yL/6/8b/+z/Ff/t/w7/7P8I/+z/Af/q//v+6P/1/uX/8P7h/+v+3f/m/tn/4/7T/9/+zv/b/sj/2f7C/9f+vP/V/rb/1P6v/w==",
        "12.eR": "UQCh/1EAmv9SAJP/UwCM/1UAhv9YAID/WwB6/18AdP9kAG//aQBq/24AZv9zAGH/eQBe/4AAXP+GAFn/jQBX/5MAV/+aAFf/oQBY/6gAWv+uAFz/tABf/7oAY//AAGb/xQBr/8kAcf/OAHb/0QB8/9MAgv/VAIn/1wCP/9gAlv/ZAJ3/2QCk/9gAq//WALH/1AC4/9IAvv/PAMT/ygDK/8YAz//BANT/vADY/7YA3P+wAOD/qgDj/6QA5f+dAOb/lgDm/48A5v+IAOX/gQDk/3sA4v91AN//bwDb/2oA1/9lANL/YQDN/1wAx/9YAML/VQC8/1MAtf9SAK//UQCo/w==",
        "12.m": "wf4RAcT++gDN/uUA2/7SAO7+xQAE/8AAG//FAC7/0QA//+IAUP/xAGb/9QB6/+kAif/XAJj/xgCs/7gAwv+yANn/sgDu/7sAAQDIABEA2QAlAOIANwDUAEgAxABaALYAbwCsAIYAqACcAK8ArwC8ALwAzwDNAN4A4wDiAPcA7QACAQEB/AAWAeYAFgHQAA4BugAJAaYA/ACZAOkAiQDYAHQA2wBiAOoAUgD7AEAACQEpAA8BEwALAf///gDv/+4A3P/gAMf/2QCy/+MAov/0AJP/BQF//xIBaf8XAVL/FQE9/wsBK//7ABz/6gAH/+AA8f7mAOL+9wDZ/gwBz/4gAQ==",
        "12.cL": "M/7x/zb+7f86/u3/Pv7v/0H+8/9C/vj/Rf78/0f+AABK/gQATP4IAE/+DABR/hAAVP4UAFf+FwBa/hsAXf4fAGD+IgBj/iYAZv4qAGr+LQBt/jAAcf4zAHX+NgB4/jkAfP48AID+PwCE/kIAiP5FAIz+RwCQ/kkAkv5OAJL+UgCP/lYAi/5XAIb+WACB/lcAff5WAHj+VQB0/lMAcP5RAGz+TgBn/kwAZP5JAGD+RgBc/kMAWP5AAFX+PQBS/jkAT/42AEv+MgBI/i8ARf4rAEP+JwBB/iIAP/4eADz+GgA6/hYAOf4RADf+DQA2/ggANP4EADT+//8z/vr/M/72/w==",
        "12.cR": "/wBhAAIBXgAGAVwACQFZAA0BVgAQAVMAEwFQABYBTQAaAUoAHQFHACEBRAAkAUEAKAE+ACsBOwAuATgAMQE1ADQBMQA3AS4AOgEqAD0BJwBAASMAQgEgAEQBHABHARgASQEVAEwBEQBPAQ4AUwEMAFcBCwBbAQ0AXgEQAF8BFQBfARkAXQEdAFsBIQBaASYAWAEqAFYBLgBUATIAUgE2AFABOgBNAT0ASgFBAEcBRABEAUcAQQFLAD4BTgA7AVEANwFUADQBVwAwAVkALQFcACkBXwAlAWEAIQFjAB0BZQAZAWcAFQFoABEBagANAWwACAFsAAQBawAAAWkA/gBlAA==",
        "12.sw": "YgHp/mMB3/5jAdX+YwHM/mQBwv5kAbj+ZQGv/mcBpf5pAZv+bwGV/nUBnf55Aab+egGv/nsBuf57AcP+ewHN/nwB1v59AeD+fgHq/oAB8/6BAf3+ggEG/4MBEP+GARn/igEi/5IBJ/+cASb/owEf/6cBF/+qAQ3/qQEE/6gB+v6mAfH+owHn/qIB3f6iAdT+qAHN/rAB0v61Adv+ugHj/r4B7P7BAfX+wgH//sMBCP/DARL/wgEc/8ABJf+8AS7/twE2/7ABPf+oAUP/nwFF/5UBRf+LAUT/ggFA/3sBOv90ATP/bwEr/2sBIv9oARn/ZAEQ/2MBBv9jAfz+YwHz/g==",
        "20.eL": "uv4qAL7+HQDI/hUA1f4VAOH+GwDs/iIA9/4pAAH/MgAM/zgAGP89ACT/QQAx/0QAPv9GAEv/RgBY/0UAZf9CAHH/PgB9/zkAif8zAJP/KgCd/yIApP8XAKv/DACx/wAAtf/0/7j/5/+7/9r/wv/P/8z/x//Z/8f/4//O/+j/2v/p/+f/6f/0/+f/AQDj/w4A3/8aANn/JgDS/zEAzP89AMT/RwC7/1AAsP9YAKX/YACa/2cAj/9sAIP/cgB2/3YAaf94AFz/ewBP/3wAQv98ADX/ewAo/3kAHP92AA//cwAC/28A9v5pAOv+ZADg/l0A1f5VAMv+TADD/kIAvv42AA==",
        "20.eR": "OgDC/zwAtv9EAKz/UACr/1oAsf9kALn/bgDA/3gAyP+CAM//jADV/5gA2P+kANz/sQDd/70A3f/JAN3/1gDb/+EA1//tANT/+ADO/wIBxv8LAb7/EwG1/xoBqv8fAZ//JAGU/ycBiP8rAXz/MQFx/zsBav9HAWj/UQFu/1cBeP9ZAYX/WQGR/1cBnf9UAan/TwG1/0oBwP9EAcr/PQHU/zQB3f8sAef/IgHv/xkB9/8PAf3/BAEEAPgACADtAAwA4AAOANQAEADIABEAuwAQAK8ADwCjAA4AlwALAIsABwB/AAMAdAD+/2kA+P9fAPH/VQDp/0wA4f9EANj/PgDN/w==",
        "21.eL": "ZP9Y/2T/UP9k/0f/Zf8//2f/N/9p/zD/a/8o/23/IP9x/xn/dP8R/3f/Cv97/wL/gP/8/ob/9v6M//D+kf/r/pf/5f6e/+H+pf/d/q3/2/61/9r+vf/a/sX/3P7N/9/+1P/j/tr/6P7g/+7+5P/1/uf//f7q/wT/7P8M/+3/FP/u/xz/7v8k/+3/LP/s/zX/7P89/+r/Rf/o/03/5f9U/+P/XP/g/2T/3P9r/9n/cv/U/3j/z/9//8n/hf/D/4r/vf+Q/7b/lP+u/5X/pv+X/57/mP+W/5j/jv+W/4b/lP9//5D/eP+L/3P/hf9u/37/a/93/2f/cP9l/2j/ZP9g/w==",
        "21.eR": "6wCo/+sAoP/rAJf/7ACP/+0Ah//vAH//8gB4//QAcP/3AGn/+wBh/wABW/8EAVT/CQFO/w8BSP8WAUP/HAE//yQBO/8rATj/MwE2/zsBNv9DATf/SwE6/1IBPf9ZAUL/YAFG/2UBTP9qAVP/bgFa/3EBYv9zAWn/dAFx/3UBef92AYL/dwGK/3YBkv91AZr/dAGi/3MBqv9xAbL/bQG5/2sBwf9nAcj/ZAHP/18B1v9aAdz/VAHi/04B5/9HAev/PwHu/zgB8f8wAfL/KAHy/yAB8f8YAe7/EQHr/woB5/8DAeL//QDc//gA1v/0AM//8QDH/+4AwP/sALj/6wCw/w==",
        "21.m": "1v9gANb/WADY/1AA2/9IAN3/QQDh/zoA5P8zAOn/LADu/yYA8/8gAPj/GgD//xUABgASAA0ADgAUAAoAHAAHACMABgArAAUAMwAGADsACABCAAsASgAOAFEAEgBXABYAXQAcAGEAIwBlACoAaQAxAGwAOABtAEAAbwBIAHAAUABvAFgAbgBgAGwAZwBrAG8AaQB3AGUAfgBiAIUAXgCMAFkAkwBUAJkATgCeAEgAowBBAKcAOgCqADIArQArAK8AIwCxABsAsQATALAACwCuAAQArAD8/6kA9v+lAO//oADp/5sA5f+UAOD/jgDc/4cA2v9/ANf/eADW/3AA1v9oAA==",
    ]
}
