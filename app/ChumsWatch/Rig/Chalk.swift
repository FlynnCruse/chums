import SwiftUI

/// A hand-drawn stroke, like a white paint marker (Posca) dragged over a dark board: an opaque round-tipped line,
/// a little uneven in width, that presses in where it starts and lifts off where it ends (it thins out and fades),
/// with the dry streaks and grain of chalk inside it, more of them toward its edges and its tail.
/// Its texture is fixed to the line (by `seed` and the distance along it), so it never crawls or flickers as the line
/// moves; `squash` reshapes the line (a blink) without stretching the texture or the pen's width.
enum Chalk {
    /// The dryness of the pen: 0 is a fresh marker (solid, a few streaks), 1 is chalk (broken up, grainy).
    nonisolated(unsafe) static var dry = 0.55

    /// A stroke, made: its pieces as paths, to draw now or keep and draw again while its line stays the same.
    struct Stroke {
        var body = Path(), joints = Path(), pits = Path(), splits = Path(), dot: Path? = nil
        var tail: Path? = nil, fadeFrom = CGPoint.zero, fadeTo = CGPoint.zero
        func draw(_ g: GraphicsContext, color: Color = .white) {
            if let d = dot { g.fill(d, with: .color(color)); return }
            // the tail first, so where a ring's tail comes back over its start, the start stays whole on top of it
            if let t = tail {
                let fade = Gradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0.97), location: 0.35),
                                            .init(color: color.opacity(0.55), location: 0.7), .init(color: color.opacity(0.14), location: 0.9),
                                            .init(color: color.opacity(0), location: 1)])
                g.fill(t, with: .linearGradient(fade, startPoint: fadeFrom, endPoint: fadeTo))
                if !splits.isEmpty { g.fill(splits, with: .color(.black.opacity(0.85))) }
            }
            g.fill(body, with: .color(color))
            if !joints.isEmpty { g.fill(joints, with: .color(color)) }
            if !pits.isEmpty { g.fill(pits, with: .color(.black.opacity(0.85))) }
        }
    }

    static func draw(_ g: GraphicsContext, _ pts: [P2], width w: Double, seed: Double, color: Color = .white,
                     squash: ((P2) -> P2)? = nil) {
        make(pts, width: w, seed: seed, squash: squash).draw(g, color: color)
    }

    /// The stroke through `pts`, `w` wide; `seed` picks its texture; `squash` moves each point of the line after its
    /// texture is laid along it.
    static func make(_ pts: [P2], width w: Double, seed: Double, squash: ((P2) -> P2)? = nil) -> Stroke {
        var out = Stroke()
        guard pts.count > 1 else { return out }
        // the line, smooth and evenly sampled; `tex` is the distance along it before any squash
        let line0 = smooth(pts)
        var tex = [Double](repeating: 0, count: line0.count)
        for i in 1..<line0.count { tex[i] = tex[i - 1] + simd_length(line0[i] - line0[i - 1]) }
        let line = squash.map { f in line0.map(f) } ?? line0
        let n = line.count
        var arc = [Double](repeating: 0, count: n), nrm = [P2](repeating: P2(0, 1), count: n)
        for i in 0..<n {
            if i > 0 { arc[i] = arc[i - 1] + simd_length(line[i] - line[i - 1]) }
            let d = line[min(n - 1, i + 1)] - line[max(0, i - 1)], l = simd_length(d)
            nrm[i] = l > 1e-9 ? P2(-d.y / l, d.x / l) : (i > 0 ? nrm[i - 1] : P2(0, 1))
        }
        let L = arc[n - 1], h0 = w / 2
        // a dot: too short to be a line
        if L < w * 0.3 {
            let c = line[n / 2], r = h0 * (0.9 + 0.1 * min(1, L / (w * 0.3)))
            out.dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            return out
        }

        // its width: pressing in at the start, lifting off at the end, a slow wander between, each edge its own
        let pressIn = min(w * 0.55, L * 0.22), liftOff = min(w * 2.1, L * 0.42)
        let ph = Strokes.hash(seed, 1.7) * TAU, ph2 = Strokes.hash(seed, 2.9) * TAU
        var hl = [Double](repeating: 0, count: n), hr = hl
        for i in 0..<n {
            let a = arc[i], s = tex[i]
            var k = 1.0
            if a < pressIn { k *= 0.84 + 0.16 * smooth01(a / pressIn) }
            let e = L - a
            if e < liftOff { let u = 1 - e / liftOff; k *= 1 - 0.62 * pow(u, 1.6) }
            k *= 1 + 0.05 * sin(s / (w * 1.9) + ph) + 0.03 * sin(s / (w * 0.7) + ph2)
            hl[i] = h0 * k * (1 + 0.07 * (vnoise(s / (w * 0.55), seed + 11) - 0.5))
            hr[i] = h0 * k * (1 + 0.07 * (vnoise(s / (w * 0.55), seed + 23) - 0.5))
        }

        // the texture is cut out of it in the background's black: thin spindles along the line at a fraction `o` of its
        // half-width, `th(u)` thick along their length
        func spindle(_ path: inout Path, _ i: Int, _ j: Int, _ o: Double, _ th: (Double) -> Double) {
            var left: [CGPoint] = [], right: [CGPoint] = []
            for k in i...j {
                let u = Double(k - i) / Double(max(1, j - i)), t = th(u)
                let q = line[k] + nrm[k] * (o * (o > 0 ? hl[k] : hr[k]))
                left.append(CGPoint(x: q.x + nrm[k].x * t, y: q.y + nrm[k].y * t))
                right.append(CGPoint(x: q.x - nrm[k].x * t, y: q.y - nrm[k].y * t))
            }
            path.move(to: left[0]); for q in left.dropFirst() { path.addLine(to: q) }
            for q in right.reversed() { path.addLine(to: q) }
            path.closeSubpath()
        }

        // the tail first, where it lifts off: it thins, fades and, the pen running dry, splits into a few bristles.
        // The body goes over it, so where a ring's tail comes back over its start the start stays whole.
        let tailStart = L - liftOff * 0.95
        var iT = n - 1
        while iT > 1 && arc[iT - 1] > tailStart { iT -= 1 }
        if iT < n - 1 {
            let tail = ribbon(line, nrm, hl, hr, iT, n - 1, startCap: false, endCap: true)
            let dir = line[n - 1] - line[n - 2], a = line[iT], b = line[n - 1] + dir / max(1e-9, simd_length(dir)) * hl[n - 1]
            out.tail = tail; out.fadeFrom = CGPoint(x: a.x, y: a.y); out.fadeTo = CGPoint(x: b.x, y: b.y)
            var splits = Path()
            let count = 2 + Int((dry * 3).rounded())
            for k in 0..<count {
                let kk = Double(k)
                let o = (-0.62 + 1.24 * (kk + 0.5) / Double(count)) + (Strokes.hash(seed + kk, 12.1) - 0.5) * 0.18
                let from = L - liftOff * (0.85 - 0.6 * Strokes.hash(seed + kk, 13.3))
                var i = n - 1
                while i > 0 && arc[i - 1] >= from { i -= 1 }
                guard i < n - 2 else { continue }
                let mw = w * (0.045 + 0.06 * Strokes.hash(seed + kk, 14.7)) * (0.6 + 0.7 * dry)
                spindle(&splits, i, n - 1, o, { u in mw * pow(u, 1.3) })
            }
            out.splits = splits
        }
        // the body, overlapping the tail by a sample, rounded off where it turns hard (the ribbon's outer side opens up)
        let bEnd = min(n - 1, iT + 1)
        out.body = ribbon(line, nrm, hl, hr, 0, bEnd, startCap: true, endCap: bEnd >= n - 1)
        var joints = Path()
        if bEnd >= 2 {
            for i in 1..<bEnd where simd_dot(nrm[i - 1], nrm[i + 1]) < 0.6 {
                let r = (hl[i] + hr[i]) / 2
                joints.addEllipse(in: CGRect(x: line[i].x - r, y: line[i].y - r, width: 2 * r, height: 2 * r))
            }
        }
        out.joints = joints
        // the board's tooth in it: hairline pits running with the stroke, few in its middle, more at its edges (biting
        // into its outline)
        var pits = Path()
        let lanes = 11, cl = w * 0.3
        for b in 0..<lanes {
            let lb = Double(b)
            let o = -1.0 + 2.0 * lb / Double(lanes - 1) + (Strokes.hash(seed + lb, 5.1) - 0.5) * 0.08
            let edge = min(1, abs(o)), shift = Strokes.hash(seed + lb, 2.2) * cl
            var c = 0.0, i = 0
            while c * cl < tex[bEnd] {
                let r = Strokes.hash(seed * 1.3 + lb * 7.7, c * 0.917), r2 = Strokes.hash(c * 1.71 + lb, seed + 0.5)
                let t0 = c * cl - shift + r2 * cl * 0.4
                while i < bEnd && tex[i] < t0 { i += 1 }
                if r < dry * (0.05 + 0.42 * pow(edge, 4)) {
                    let t1 = t0 + cl * (0.6 + 1.8 * r2)
                    var j = i
                    while j < bEnd && tex[j + 1] <= t1 { j += 1 }
                    let tw = w * (0.012 + 0.022 * Strokes.hash(seed + lb * 3.3, c * 1.13 + 0.4)) * (0.7 + 0.6 * edge)
                    if j > i { spindle(&pits, i, j, o, { u in tw * pow(sin(u * Double.pi), 0.6) }) }
                }
                c += 1
            }
        }
        out.pits = pits
        return out
    }

    // MARK: pieces

    /// The outline of the stroke from sample `a` to `b`: its left edge, a round end, its right edge back.
    private static func ribbon(_ line: [P2], _ nrm: [P2], _ hl: [Double], _ hr: [Double], _ a: Int, _ b: Int,
                               startCap: Bool, endCap: Bool) -> Path {
        var p = Path()
        func pt(_ v: P2) -> CGPoint { CGPoint(x: v.x, y: v.y) }
        p.move(to: pt(line[a] + nrm[a] * hl[a]))
        for i in (a + 1)...b { p.addLine(to: pt(line[i] + nrm[i] * hl[i])) }
        if endCap { cap(&p, line[b], nrm[b], hl[b], hr[b], forward: true) } else { p.addLine(to: pt(line[b] - nrm[b] * hr[b])) }
        for i in stride(from: b - 1, through: a, by: -1) { p.addLine(to: pt(line[i] - nrm[i] * hr[i])) }
        if startCap { cap(&p, line[a], -nrm[a], hr[a], hl[a], forward: true) }
        p.closeSubpath()
        return p
    }
    /// A half-round end, from the side at +n to the side at -n, bulging along the line's direction.
    private static func cap(_ p: inout Path, _ c: P2, _ n: P2, _ h1: Double, _ h2: Double, forward: Bool) {
        let t = P2(n.y, -n.x)                       // the direction the line runs, out of this end
        for k in 1...7 {
            let a = Double(k) / 8 * Double.pi
            let h = h1 + (h2 - h1) * Double(k) / 8
            let v = c + n * (cos(a) * h) + t * (sin(a) * h * 0.92)
            p.addLine(to: CGPoint(x: v.x, y: v.y))
        }
        let e = c - n * h2
        p.addLine(to: CGPoint(x: e.x, y: e.y))
    }

    /// The points as a smooth line (Catmull-Rom), about every 0.6 pt.
    static func smooth(_ pts: [P2]) -> [P2] {
        let m = pts.count
        var out: [P2] = [pts[0]]
        for i in 0..<(m - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(m - 1, i + 2)]
            let gap: Double = simd_length(p2 - p1)
            let per = max(1, min(8, Int(gap / 0.6)))
            for k in 1...per {
                let u = Double(k) / Double(per), u2 = u * u, u3 = u2 * u
                let a: P2 = p1 * 2, b: P2 = (p2 - p0) * u
                let c1: P2 = p0 * 2 - p1 * 5, c2: P2 = p2 * 4 - p3, c: P2 = (c1 + c2) * u2
                let d1: P2 = p1 * 3 - p0, d2: P2 = p3 - p2 * 3, d: P2 = (d1 + d2) * u3
                let sum: P2 = a + b + c + d
                out.append(sum * 0.5)
            }
        }
        return out
    }
    @inline(__always) private static func smooth01(_ u: Double) -> Double { let v = clamp(u, 0, 1); return v * v * (3 - 2 * v) }
    /// Smooth value noise in 0…1.
    @inline(__always) static func vnoise(_ x: Double, _ seed: Double) -> Double {
        let i = floor(x), f = x - i, u = f * f * (3 - 2 * f)
        let a = Strokes.hash(seed, i * 0.618), b = Strokes.hash(seed, (i + 1) * 0.618)
        return a + (b - a) * u
    }
}
