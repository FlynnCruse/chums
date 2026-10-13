import SwiftUI

/// Drawing helpers the flat characters share: polylines resampled to a fixed count (so any two can be blended point
/// by point), and a marker stroke (a ribbon a little uneven in width, cut flat at the ends) instead of a perfect one.
typealias P2 = SIMD2<Double>

enum Strokes {
    /// The points of a polyline, `n` of them, evenly spaced along its length.
    static func resample(_ pts: [P2], _ n: Int) -> [P2] {
        guard pts.count > 1 else { return [P2](repeating: pts.first ?? .zero, count: n) }
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + simd_length(pts[i] - pts[i - 1])) }
        let total = cum.last!
        guard total > 1e-9 else { return [P2](repeating: pts[0], count: n) }
        var out: [P2] = [], j = 0
        for k in 0..<n {
            let d = total * Double(k) / Double(n - 1)
            while j < pts.count - 2 && cum[j + 1] < d { j += 1 }
            let seg = max(1e-9, cum[j + 1] - cum[j]), u = (d - cum[j]) / seg
            out.append(pts[j] + (pts[j + 1] - pts[j]) * u)
        }
        return out
    }
    static func line(_ a: P2, _ b: P2) -> [P2] { [a, b] }
    /// An arc around `c`, from angle `a0` to `a1` (radians; screen y down, so π/2 is straight down).
    static func arc(_ c: P2, _ r: Double, _ a0: Double, _ a1: Double, rx: Double? = nil) -> [P2] {
        (0...48).map { i in let a = a0 + (a1 - a0) * Double(i) / 48; return c + P2(cos(a) * (rx ?? r), sin(a) * r) }
    }
    static func mirrored(_ g: [P2]) -> [P2] { g.map { P2(-$0.x, $0.y) } }
    static func mix(_ a: [P2], _ b: [P2], _ k: Double) -> [P2] { zip(a, b).map { (p: P2, q: P2) -> P2 in p + (q - p) * k } }
    static func length(_ g: [P2]) -> Double { zip(g, g.dropFirst()).reduce(0) { $0 + simd_length($1.1 - $1.0) } }

    @inline(__always) static func hash(_ a: Double, _ b: Double) -> Double {
        let v = sin(a * 127.1 + b * 311.7) * 43758.5453; return v - floor(v)
    }

    /// A marker stroke along `pts` (already placed): `width` thick, its width wandering a little along the way
    /// (`seed` keeps the wander the same from frame to frame), cut flat at the ends, rounded where it turns hard.
    static func marker(_ ctx: GraphicsContext, _ pts0: [P2], width w: Double, color: Color, seed: Double = 0, wander: Double = 0.14, boil: Double? = nil) {
        let n = pts0.count
        guard n > 1, length(pts0) > 1.5 else { return }
        // the line breathes, like hand-drawn frames: a smooth sway along it, new each `boil` step
        var pts = pts0
        if let b = boil {
            let ph1 = hash(seed, b) * (Double.pi * 2), ph2 = hash(b, seed + 3) * (Double.pi * 2)
            pts = pts0.enumerated().map { i, q in
                let u = Double(i) / Double(n - 1)
                return q + P2(sin(u * 5 + ph1), cos(u * 4 + ph2)) * 0.45
            }
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        left.reserveCapacity(n); right.reserveCapacity(n)
        var joints: [P2] = []
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            var t = b - a; let l = simd_length(t); t = l > 1e-9 ? t / l : P2(1, 0)
            let nrm = P2(-t.y, t.x)
            let ww = w * (1 + wander * (hash(seed, Double(i) * 0.37) - 0.5) * 2 * (0.5 + 0.5 * sin(Double(i) * 0.6 + seed)))
            let p = pts[i]
            left.append(CGPoint(x: p.x + nrm.x * ww / 2, y: p.y + nrm.y * ww / 2))
            right.append(CGPoint(x: p.x - nrm.x * ww / 2, y: p.y - nrm.y * ww / 2))
            if i > 0 && i < n - 1 {
                let u = pts[i] - pts[i - 1], v = pts[i + 1] - pts[i]
                let lu = simd_length(u), lv = simd_length(v)
                if lu > 1e-6 && lv > 1e-6 && simd_dot(u / lu, v / lv) < 0.75 { joints.append(p) }
            }
        }
        var path = Path()
        path.move(to: left[0]); for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
        if !joints.isEmpty {                                            // round where it turns hard (a separate fill)
            var j = Path()
            for q in joints { j.addEllipse(in: CGRect(x: q.x - w * 0.48, y: q.y - w * 0.48, width: w * 0.96, height: w * 0.96)) }
            ctx.fill(j, with: .color(color))
        }
    }

    /// A smooth closed curve through points (Catmull-Rom as cubic Béziers).
    static func smoothClosed(_ p: [P2]) -> Path {
        var path = Path(); let n = p.count
        guard n > 2 else { return path }
        path.move(to: CGPoint(x: p[0].x, y: p[0].y))
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6
            path.addCurve(to: CGPoint(x: p2.x, y: p2.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
        }
        path.closeSubpath()
        return path
    }
    /// A smooth open curve through points.
    static func smoothOpen(_ p: [P2]) -> Path {
        var path = Path(); let n = p.count
        guard n > 1 else { return path }
        path.move(to: CGPoint(x: p[0].x, y: p[0].y))
        for i in 0..<(n - 1) {
            let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(n - 1, i + 2)]
            let c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6
            path.addCurve(to: CGPoint(x: p2.x, y: p2.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
        }
        return path
    }
}
