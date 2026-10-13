import Foundation
import CoreGraphics
import CoreText

/* Pix: a deadpan fruit sprite that knows it is a sprite. A port of design/pix/pix.js, frame for frame.
 *
 * `Pix.draw(cg, p)` is a pure function of its input, like PIX.draw(ctx, p) in the Lab. It draws into a bitmap
 * CGContext made by `Pix.makeContext` (premultiplied RGBA, rows top-down): every hard-edged thing (cells, eyes,
 * the pixel font, boxes) is written straight into the bitmap by a small rasterizer that snaps edges to device
 * pixels exactly the way the JS `snapper` does, so neighbouring cells share an edge at any scale; the HD painting
 * (paths, gradients, the badge) goes through CoreGraphics on the same bitmap; `atRes` (draw at full resolution,
 * show at `block` pt per sample with hard edges) is done in software: a chain of bilinear halvings, a Mitchell
 * cubic last step, alpha thresholded at 96/255, then nearest-neighbour back on screen, mirroring what a browser
 * canvas does for drawImage with smoothing on / off. CoreGraphics works on watchOS and macOS alike, so
 * tools/pix-render.swift renders the same frames on the Mac to compare with design/pix/reference.
 *
 * The context's user space is the 198 × 242 design space of the Lab: set its transform (scale, offset) before
 * calling draw, exactly as the Lab does with ctx.scale(). Colours are memoized like the JS MEMO.
 */
enum Pix {
    // MARK: - input

    enum Species: String, CaseIterable { case apple, banana }
    enum State: String, CaseIterable {
        case idle, listening, thinking, compacting, working, subagents, speaking, done, needs, waiting, blocked, dizzy, sleep
    }
    enum EyeMode { case side, none, closed, happy, cam, up, cross, squint }
    enum Mood: Int, CaseIterable { case apple, greenApple, golden, pinkLady, rot, banana, greenBanana, redBanana, ripe, gray, turning }

    struct Params {
        var species: Species = .apple
        var cx = 99.0, cy = 118.0
        var px = 7.0
        var t = 0.0
        var state: State = .idle
        var stateT = 0.0
        var look: Double? = nil           // idle: force the side-eye direction
        var voice: Double? = nil          // listening: 0…1
        var text: String? = nil           // speaking
        var tools: [String] = []          // working
        var subagents: Int? = nil
        var screen: CGRect? = nil         // the area it may use (below the watch's status row)
        var room: Double? = nil           // needs: max height when it leans in
        var bang = true                   // needs: false hides the !
        var eyeMode: EyeMode? = nil       // force the eyes (e.g. .cam)
        var palette: Mood? = nil
        var ripe: Ripe? = nil              // the crown's ripeness, over the state's own colours
        init() {}
    }

    /// A banana's ripeness, from the crown: its colours, its sugar spots, how brown it's gone.
    struct Ripe { var mood: Mood; var spots: Double; var rot: Double }
    static let RIPENESS: [Ripe] = [Ripe(mood: .greenBanana, spots: 0, rot: 0), Ripe(mood: .turning, spots: 0, rot: 0),
                                   Ripe(mood: .banana, spots: 0, rot: 0), Ripe(mood: .banana, spots: 0.22, rot: 0),
                                   Ripe(mood: .ripe, spots: 0.45, rot: 0), Ripe(mood: .ripe, spots: 0.68, rot: 0.1),
                                   Ripe(mood: .ripe, spots: 0.8, rot: 0.38)]

    // MARK: - colour (OKLab)

    typealias V3 = SIMD3<Double>

    static func hex(_ h: String) -> V3 {
        let s = Array(h.utf8)
        func b(_ i: Int) -> Double { Double(Int(String(bytes: s[i..<i + 2], encoding: .ascii)!, radix: 16)!) }
        return V3(b(1), b(3), b(5))
    }
    @inline(__always) static func toLin(_ c: Double) -> Double { let c = c / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    @inline(__always) static func toSrgb(_ c: Double) -> Double { 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055) }
    static func oklab(_ c: V3) -> V3 {
        let r = toLin(c.x), g = toLin(c.y), b = toLin(c.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return V3(0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
                  1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
                  0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s)
    }
    static func srgb(_ c: V3) -> V3 {
        let l = pow(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z, 3)
        let m = pow(c.x - 0.1055613458 * c.y - 0.0638541728 * c.z, 3)
        let s = pow(c.x - 0.0894841775 * c.y - 1.291485548 * c.z, 3)
        let r = toSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        let g = toSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        let b = toSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)
        return V3(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    static let PAL: [[String]] = [   // indexed by Mood
        ["#FFC27A", "#FF5A4E", "#E3243F", "#8E1240"],   // apple
        ["#F4FFA8", "#B8F05E", "#62C93C", "#2E8A3A"],   // greenApple
        ["#FFF6B0", "#FFDA4A", "#FFAF1F", "#E2701A"],   // golden
        ["#FFD9C8", "#FF8E8A", "#F0507A", "#A8306E"],   // pinkLady
        ["#C8A47C", "#9A6C45", "#6E462A", "#4B2D1C"],   // rot
        ["#FFF8B8", "#FFE65C", "#FFC928", "#E39A1A"],   // banana
        ["#EEFFB8", "#C2EC6E", "#86CB42", "#559C30"],   // greenBanana
        ["#FFC9A8", "#F07F5E", "#C2454C", "#7E2A44"],   // redBanana
        ["#FFE9A0", "#FFC94A", "#F2A42A", "#C8781E"],   // ripe
        ["#D5D8DD", "#A3A9B2", "#7A828D", "#59606B"],   // gray
        ["#F6FFB2", "#E4F062", "#BFD936", "#8AA82A"],   // turning: a banana between green and yellow
    ]
    enum Part: Int { case leaf, stem, bstem, tip }
    static let PART: [[String]] = [["#C2F57E", "#5CC94F", "#2F8F43"], ["#8A5A2E", "#5A3418"], ["#A8A04A", "#5E5524"], ["#5A3A20", "#3A2414"]]
    static let LAB: [[V3]] = PAL.map { $0.map { oklab(hex($0)) } }
    static let PLAB: [[V3]] = PART.map { $0.map { oklab(hex($0)) } }

    @inline(__always) static func grad(_ stops: [V3], _ u0: Double) -> V3 {
        let u = max(0, min(0.9999, u0)) * Double(stops.count - 1)
        let i = Int(floor(u)), f = u - Double(i), a = stops[i], b = stops[i + 1]
        return a + (b - a) * f
    }
    @inline(__always) static func mix(_ a: V3, _ b: V3, _ k: Double) -> V3 { a + (b - a) * k }
    @inline(__always) static func hash(_ x: Double, _ y: Double, _ s: Double) -> Double {
        let v = sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
        return v - floor(v)
    }
    @inline(__always) static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
    @inline(__always) static func ease(_ k0: Double) -> Double { let k = clamp01(k0); return k * k * (3 - 2 * k) }
    @inline(__always) static func step(_ v: Double, _ n: Double) -> Double { floor(v * n) / n }
    /// JS Math.round: halves go up (toward +∞), unlike Swift's rounded().
    @inline(__always) static func jsRound(_ v: Double) -> Double { floor(v + 0.5) }
    @inline(__always) static func fmod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }
    /// JS Math.hypot as V8 computes it (normalize to the largest, Kahan-summed squares), not libm's correctly
    /// rounded hypot: the last bit decides which way a `d <= seg` goes in the blocked path.
    static func jsHypot(_ a: Double, _ b: Double) -> Double {
        let aa = abs(a), ab = abs(b), mx = max(aa, ab)
        if mx == 0 { return 0 }
        var sum = 0.0, comp = 0.0
        for v in [aa, ab] {
            let n = v / mx, summand = n * n - comp, prelim = sum + summand
            comp = (prelim - sum) - summand; sum = prelim
        }
        return sqrt(sum) * mx
    }
    /// A float to 8 bits the way a GPU render target stores it: round to nearest, ties to even.
    @inline(__always) static func unorm8(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v)).rounded(.toNearestOrEven)) }

    /// An unpremultiplied 8-bit colour, like a canvas fillStyle.
    struct RGBA: Hashable {
        var r: UInt8, g: UInt8, b: UInt8, a: UInt8
        init(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) { self.r = UInt8(r); self.g = UInt8(g); self.b = UInt8(b); self.a = UInt8(a) }
        /// `rgba(r,g,b,alpha)`: the alpha is rounded to 8 bits like a parsed CSS colour.
        init(_ r: Int, _ g: Int, _ b: Int, alpha: Double) { self.init(r, g, b, Int(jsRound(alpha * 255))) }
        init(hex h: UInt32) { self.init(Int((h >> 16) & 0xFF), Int((h >> 8) & 0xFF), Int(h & 0xFF)) }
        var cg: CGColor { CGColor(colorSpace: deviceRGB, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(a) / 255])! }
    }
    static let deviceRGB = CGColorSpaceCreateDeviceRGB()
    /// `css(lab)`: rgb() with each channel truncated (`| 0`).
    @inline(__always) static func css(_ lab: V3) -> RGBA { let c = srgb(lab); return RGBA(Int(c.x), Int(c.y), Int(c.z)) }
    static let WHITE = RGBA(255, 255, 255), INK = RGBA(0x0A, 0x0A, 0x0C)

    // MARK: - species

    enum StemPose { case curl, antenna, droop }
    enum LegPose { case stand, stepL, stepR }
    enum PartKind: UInt8 { case body = 0, stem = 1, leaf = 2, nub = 3 }   // S, L, N in the JS

    final class SpeciesData {
        let key: Species, name: String, W: Int, H: Int, pxScale: Double, visW: Int, blushDX: Double
        let rows: [[UInt8]]
        let parts: [StemPose: [(Int, Int, PartKind)]]
        let stemKind: Part
        let eyes: [Int], eyeY: Int, mouth: (Int, Int, Int)
        let legs: [LegPose: [(Int, Int)]]
        let legsHD: [(Double, Double, Double, Double)]
        let shine: [(Int, Int)]
        let tip: (Double, Double), bangX: Double, badge: (Double, Double)
        let base: Mood, moods: [State: Mood], cycle: [Mood]
        let cells: [(Int, Int, UInt8)]
        let span: [(Int, Int)?]
        let bodyMask: [Bool]
        init(key: Species, name: String, W: Int, H: Int, pxScale: Double = 1, visW: Int? = nil, blushDX: Double = 1.45, rows: [String],
             parts: [StemPose: [(Int, Int, PartKind)]], stemKind: Part, eyes: [Int], eyeY: Int, mouth: (Int, Int, Int),
             legs: [LegPose: [(Int, Int)]], legsHD: [(Double, Double, Double, Double)], shine: [(Int, Int)], tip: (Double, Double),
             bangX: Double, badge: (Double, Double), base: Mood, moods: [State: Mood], cycle: [Mood]) {
            self.key = key; self.name = name; self.W = W; self.H = H; self.pxScale = pxScale; self.visW = visW ?? W; self.blushDX = blushDX
            self.rows = rows.map { Array($0.utf8) }
            self.parts = parts; self.stemKind = stemKind; self.eyes = eyes; self.eyeY = eyeY; self.mouth = mouth
            self.legs = legs; self.legsHD = legsHD; self.shine = shine; self.tip = tip; self.bangX = bangX; self.badge = badge
            self.base = base; self.moods = moods; self.cycle = cycle
            var cells: [(Int, Int, UInt8)] = []
            for (y, r) in self.rows.enumerated() { for (x, c) in r.enumerated() where c != UInt8(ascii: ".") { cells.append((x, y, c)) } }
            self.cells = cells
            self.span = self.rows.map { r in
                guard let a = r.firstIndex(where: { $0 != UInt8(ascii: ".") }) else { return nil }
                var b = r.count - 1; while r[b] == UInt8(ascii: ".") { b -= 1 }
                return (a, b)
            }
            var mask = [Bool](repeating: false, count: W * self.rows.count)
            for (y, r) in self.rows.enumerated() { for x in 0..<min(W, r.count) where r[x] != UInt8(ascii: ".") { mask[y * W + x] = true } }
            self.bodyMask = mask
        }
        @inline(__always) func isBody(_ x: Int, _ y: Int) -> Bool { y >= 0 && y < rows.count && x >= 0 && x < W && bodyMask[y * W + x] }
    }

    static let APPLE = SpeciesData(
        key: .apple, name: "CRUNCH", W: 15, H: 17,
        rows: [
            "...............", "...............", "...............",
            "..XXXX...XXXX..", ".XXXXXXXXXXXXX.",
            "XXXXXXXXXXXXXXX", "XXXXXXXXXXXXXXX", "XXXXXXXXXXXXXXX", "XXXXXXXXXXXXXXX", "XXXXXXXXXXXXXXX",
            ".XXXXXXXXXXXXX.", ".XXXXXXXXXXXXX.", "..XXXXXXXXXXX..", "...XXXXXXXXX...", "....XXX.XXX....",
        ],
        parts: [   // S stem, L leaf
            .curl: [(8, 0, .stem), (7, 1, .stem), (7, 2, .stem), (7, 3, .stem), (10, 0, .leaf), (11, 0, .leaf), (9, 1, .leaf), (10, 1, .leaf), (11, 1, .leaf), (12, 1, .leaf), (8, 2, .leaf), (9, 2, .leaf), (10, 2, .leaf)],
            .antenna: [(7, 0, .stem), (7, 1, .stem), (7, 2, .stem), (7, 3, .stem), (8, 2, .leaf), (9, 2, .leaf), (9, 1, .leaf), (10, 1, .leaf), (10, 2, .leaf), (11, 1, .leaf)],
            .droop: [(7, 3, .stem), (7, 2, .stem), (6, 2, .leaf), (5, 2, .leaf), (4, 2, .leaf), (3, 2, .leaf), (5, 1, .leaf), (4, 1, .leaf)],
        ],
        stemKind: .stem,
        eyes: [4, 9], eyeY: 8, mouth: (6, 10, 3),
        legs: [
            .stand: [(5, 15), (5, 16), (4, 16), (9, 15), (9, 16), (8, 16)],
            .stepL: [(5, 15), (4, 15), (3, 15), (9, 15), (9, 16), (8, 16)],
            .stepR: [(5, 15), (5, 16), (4, 16), (9, 15), (8, 15), (7, 15)],
        ],
        legsHD: [(5.5, 14.6, 16.45, 4.3), (9.5, 14.6, 16.45, 8.3)],
        shine: [(2, 5), (3, 5), (2, 6)],
        tip: (7.5, 0.5), bangX: 7.5, badge: (2.2, 0.7),
        base: .apple, moods: [.needs: .golden, .dizzy: .greenApple], cycle: [.apple, .greenApple, .golden, .pinkLady])

    static let BANANA = SpeciesData(
        // a ")" crescent: long tapered neck up to the stem, belly bowing right, blunt bottom with a dark nub
        key: .banana, name: "NANA", W: 15, H: 23, pxScale: 6 / 7, visW: 13, blushDX: 1.1,
        rows: [   // rasterized from the HD outline so both versions are the same banana
            "...............", "...XX..........", "..XXXXX........", "...XXXXXX......", "....XXXXXX.....", "....XXXXXXX....",
            ".....XXXXXXX...", ".....XXXXXXXX..", "......XXXXXXX..", "......XXXXXXXX.", "......XXXXXXXX.", "......XXXXXXXX.",
            ".....XXXXXXXXX.", ".....XXXXXXXX..", ".....XXXXXXXX..", "....XXXXXXXXX..", "....XXXXXXXX...", "...XXXXXXXX....",
            "...XXXXXXX.....", "..XXXXXXX......", "..TTXXX........",
        ],
        parts: [
            .curl: [(3, 0, .stem), (2, 0, .nub)],
            .antenna: [(3, 0, .stem), (2, 0, .nub)],
            .droop: [(2, 1, .stem), (1, 1, .nub)],
        ],
        stemKind: .bstem,
        eyes: [7, 11], eyeY: 11, mouth: (8, 13, 2),
        legs: [
            .stand: [(4, 21), (4, 22), (3, 22), (6, 21), (6, 22), (5, 22)],
            .stepL: [(4, 21), (3, 21), (2, 21), (6, 21), (6, 22), (5, 22)],
            .stepR: [(4, 21), (4, 22), (3, 22), (6, 21), (7, 21)],
        ],
        legsHD: [(4.5, 20.6, 22.45, 3.3), (6.5, 20.6, 22.45, 5.3)],
        shine: [(6, 6), (7, 6), (6, 7)],
        tip: (3.5, 0.5), bangX: 3.5, badge: (12.6, 4.2),
        base: .banana, moods: [.needs: .ripe, .dizzy: .greenBanana], cycle: [.banana, .greenBanana, .redBanana, .ripe])

    static func species(_ s: Species) -> SpeciesData { s == .apple ? APPLE : BANANA }

    // the shade of one cell: gradient + per-pixel jitter + bevel + glint, then rot / spots
    static func shadeBody(_ sp: SpeciesData, _ mood: Mood, _ x: Int, _ y: Int, _ boost: Double, _ rot: Double, _ spots: Double) -> V3 {
        let st = LAB[mood.rawValue], W = Double(sp.W), H = Double(sp.H), ch = sp.rows[y][x]
        let fx = Double(x), fy = Double(y)
        if ch == UInt8(ascii: "T") { let c = grad(PLAB[Part.tip.rawValue], (fx + fy) / 30); return V3(c.x + boost * 0.5, c.y, c.z) }
        var c = grad(st, (fx / W) * 0.42 + (fy / H) * 0.58)
        if rot > 0 { c = mix(c, grad(LAB[Mood.rot.rawValue], (fx / W) * 0.42 + (fy / H) * 0.58), rot) }
        var L = c.x + (hash(fx, fy, 3) - 0.5) * 0.035 + boost
        if !sp.isBody(x + 1, y) || !sp.isBody(x, y + 1) { L -= 0.065 }
        else if !sp.isBody(x - 1, y) || !sp.isBody(x, y - 1) { L += 0.045 }
        if sp.shine.contains(where: { $0.0 == x && $0.1 == y }) { L += 0.12 }
        if sp.key == .banana, let s = sp.span[y], y >= 5 && y <= 17 && x == s.1 - 2 { L -= 0.035 }      // the banana's ridge
        c = V3(L, c.y, c.z)
        if spots > 0 && hash(fx, fy, 5) < spots * 0.32 { c = mix(c, grad(PLAB[Part.tip.rawValue], 0.3), 0.8) }
        return c
    }
    static func shadePart(_ sp: SpeciesData, _ kind: PartKind, _ x: Int, _ y: Int, _ boost: Double, _ rot: Double) -> V3 {
        let fx = Double(x), fy = Double(y)
        if kind == .leaf {
            var c = grad(PLAB[Part.leaf.rawValue], clamp01((fy + (fx - 8) * 0.25) / 3.2))
            if rot > 0 { c = mix(c, grad(LAB[Mood.rot.rawValue], 0.5), rot * 0.8) }
            return V3(c.x + boost + (hash(fx, fy, 9) - 0.5) * 0.03, c.y, c.z)
        }
        if kind == .nub { let c = grad(PLAB[Part.tip.rawValue], 0.4); return V3(c.x + boost, c.y, c.z) }
        let c = grad(PLAB[sp.stemKind.rawValue], fy / 3); return V3(c.x + boost, c.y, c.z)
    }

    struct MemoKey: Hashable { var sp: UInt8, kind: UInt8, mood: Int8, x: Int8, y: Int8, b: Int16, rot: Int8, spots: Int8 }
    nonisolated(unsafe) static var MEMO: [MemoKey: RGBA] = [:]
    @inline(__always) static func color(_ key: MemoKey, _ f: () -> V3) -> RGBA {
        if let c = MEMO[key] { return c }
        let c = css(f()); if MEMO.count > 30000 { MEMO.removeAll(keepingCapacity: true) }; MEMO[key] = c; return c
    }
    nonisolated(unsafe) static var LEG_MEMO: [Int: RGBA] = [:]
    static func legColor(_ sp: SpeciesData, _ mood: Mood) -> RGBA {
        if let c = LEG_MEMO[mood.rawValue] { return c }
        let c = grad(LAB[mood.rawValue], 0.9), out = css(V3(c.x * 0.7, c.y * 0.85, c.z * 0.85)); LEG_MEMO[mood.rawValue] = out; return out
    }

    // MARK: - the bitmap and the drawing context

    /// Premultiplied RGBA, 8 bits per channel, rows top-down: the pixels of one canvas.
    final class Raster {
        let w: Int, h: Int
        let data: UnsafeMutablePointer<UInt8>
        private let owned: Bool
        private var _cg: CGContext?
        init(w: Int, h: Int) {
            self.w = max(1, w); self.h = max(1, h); owned = true
            data = UnsafeMutablePointer<UInt8>.allocate(capacity: self.w * self.h * 4)
            data.initialize(repeating: 0, count: self.w * self.h * 4)
        }
        /// Over bytes owned by someone else (a bitmap CGContext's data).
        init(borrowed: UnsafeMutablePointer<UInt8>, w: Int, h: Int) { self.w = w; self.h = h; data = borrowed; owned = false }
        deinit { if owned { data.deallocate() } }
        func clear() { data.update(repeating: 0, count: w * h * 4) }
        func fill(_ c: RGBA) {   // opaque background
            var i = 0
            for _ in 0..<(w * h) { data[i] = c.r; data[i + 1] = c.g; data[i + 2] = c.b; data[i + 3] = 255; i += 4 }
        }
        /// A CoreGraphics context on the same bytes, y flipped so user space is the canvas's (origin top-left).
        var cg: CGContext {
            if let c = _cg { return c }
            let c = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: deviceRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
            _cg = c
            return c
        }
        /// A CGImage over the same bytes (no copy): valid as long as the raster lives and until it is drawn into again.
        func image() -> CGImage? {
            guard let provider = CGDataProvider(dataInfo: nil, data: data, size: w * h * 4, releaseData: { _, _, _ in }) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: deviceRGB,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    /// A canvas transform: x' = a x + c y + e, y' = b x + d y + f.
    struct Matrix {
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
        func concat(_ n: Matrix) -> Matrix {
            Matrix(a: a * n.a + c * n.b, b: b * n.a + d * n.b, c: a * n.c + c * n.d, d: b * n.c + d * n.d,
                   e: a * n.e + c * n.f + e, f: b * n.e + d * n.f + f)
        }
        var cg: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f) }
    }
    struct IRect { var x0: Int, y0: Int, x1: Int, y1: Int }

    /// The canvas: a transform, a clip, a fill style and global alpha over a Raster. Mirrors the subset of
    /// CanvasRenderingContext2D that pix.js uses.
    final class G {
        let r: Raster
        var m = Matrix()
        var clip: IRect
        var alpha = 1.0
        var fill = RGBA(0, 0, 0)
        private var stack: [(Matrix, IRect, Double, RGBA)] = []
        init(_ r: Raster) { self.r = r; clip = IRect(x0: 0, y0: 0, x1: r.w, y1: r.h) }

        func save() { stack.append((m, clip, alpha, fill)) }
        func restore() { if let s = stack.popLast() { (m, clip, alpha, fill) = s } }
        func setTransform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) { m = Matrix(a: a, b: b, c: c, d: d, e: e, f: f) }
        func translate(_ x: Double, _ y: Double) { m = m.concat(Matrix(e: x, f: y)) }
        func scale(_ x: Double, _ y: Double) { m = m.concat(Matrix(a: x, d: y)) }
        func rotate(_ t: Double) { let c = cos(t), s = sin(t); m = m.concat(Matrix(a: c, b: s, c: -s, d: c)) }
        func clipRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            let d = deviceRect(x, y, w, h)
            clip = IRect(x0: max(clip.x0, Int(floor(d.x0))), y0: max(clip.y0, Int(floor(d.y0))), x1: min(clip.x1, Int(ceil(d.x1))), y1: min(clip.y1, Int(ceil(d.y1))))
        }
        /// Device-space bounding box of a user rect (axis-aligned transforms, and the hourglass's quarter turn).
        func deviceRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
            if m.b == 0 && m.c == 0 {
                let X0 = x * m.a + m.e, X1 = (x + w) * m.a + m.e, Y0 = y * m.d + m.f, Y1 = (y + h) * m.d + m.f
                return (min(X0, X1), min(Y0, Y1), max(X0, X1), max(Y0, Y1))
            }
            var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
            for (px, py) in [(x, y), (x + w, y), (x, y + h), (x + w, y + h)] {
                let X = m.a * px + m.c * py + m.e, Y = m.b * px + m.d * py + m.f
                x0 = min(x0, X); y0 = min(y0, Y); x1 = max(x1, X); y1 = max(y1, Y)
            }
            return (x0, y0, x1, y1)
        }

        /// The paint as the GPU sees it: the fill colour's alpha is 8-bit (a parsed CSS colour), globalAlpha is not,
        /// the premultiplied source stays float until it is stored.
        @inline(__always) func paint() -> (Double, Double, Double, Double) {
            let a = Double(fill.a) / 255 * alpha
            return (Double(fill.r) * a, Double(fill.g) * a, Double(fill.b) * a, a * 255)
        }
        /// Source-over of one premultiplied pixel (float, 0…255) with a coverage in 0…1, stored round-to-even.
        @inline(__always) func blend(_ i: Int, _ sr: Double, _ sg: Double, _ sb: Double, _ sa: Double, _ cov: Double) {
            let p = r.data + i
            let k = 1 - sa * cov / 255
            p[0] = unorm8(sr * cov + Double(p[0]) * k); p[1] = unorm8(sg * cov + Double(p[1]) * k)
            p[2] = unorm8(sb * cov + Double(p[2]) * k); p[3] = unorm8(sa * cov + Double(p[3]) * k)
        }
        /// Fill an integer device rect [x0,x1) × [y0,y1) with the paint, clipped. Opaque paints are a plain store.
        func fillDevice(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            let X0 = max(x0, clip.x0), Y0 = max(y0, clip.y0), X1 = min(x1, clip.x1), Y1 = min(y1, clip.y1)
            guard X1 > X0 && Y1 > Y0 else { return }
            let (sr, sg, sb, sa) = paint()
            if sa >= 255 {
                let r8 = fill.r, g8 = fill.g, b8 = fill.b
                for y in Y0..<Y1 {
                    var p = r.data + (y * r.w + X0) * 4
                    for _ in X0..<X1 { p[0] = r8; p[1] = g8; p[2] = b8; p[3] = 255; p += 4 }
                }
            } else if sa > 0 {
                for y in Y0..<Y1 { for x in X0..<X1 { blend((y * r.w + x) * 4, sr, sg, sb, sa, 1) } }
            }
        }
        /// canvas fillRect: a fractional device edge is anti-aliased the way the GPU does a quad's edges:
        /// coverage = the smallest edge coverage (distance from the pixel centre + ½, clamped), not the area.
        func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            let d = deviceRect(x, y, w, h)
            let fx0 = d.x0, fy0 = d.y0, fx1 = d.x1, fy1 = d.y1
            guard fx1 > fx0 && fy1 > fy0 else { return }
            if fx0 == floor(fx0) && fy0 == floor(fy0) && fx1 == floor(fx1) && fy1 == floor(fy1) {
                fillDevice(Int(fx0), Int(fy0), Int(fx1), Int(fy1)); return
            }
            let (sr, sg, sb, sa) = paint(); guard sa > 0 else { return }
            let ix0 = max(clip.x0, Int(floor(fx0))), iy0 = max(clip.y0, Int(floor(fy0))), ix1 = min(clip.x1, Int(ceil(fx1))), iy1 = min(clip.y1, Int(ceil(fy1)))
            guard ix1 > ix0 && iy1 > iy0 else { return }
            for y in iy0..<iy1 {
                let c = Double(y) + 0.5, cy = max(0, min(1, min(c - fy0, fy1 - c) + 0.5))
                for x in ix0..<ix1 {
                    let cxx = Double(x) + 0.5, cov = min(cy, max(0, min(1, min(cxx - fx0, fx1 - cxx) + 0.5)))
                    if cov > 0 { blend((y * r.w + x) * 4, sr, sg, sb, sa, cov) }
                }
            }
        }
        /// The JS `snapper`: both edges rounded to device pixels (so neighbours share an edge at any scale).
        @inline(__always) func snap(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            let sx = m.a == 0 ? 1 : m.a, sy = m.d == 0 ? 1 : m.d, ex = m.e, fy = m.f
            let x0 = Int(jsRound(x * sx + ex)), x1 = Int(jsRound((x + w) * sx + ex)), y0 = Int(jsRound(y * sy + fy)), y1 = Int(jsRound((y + h) * sy + fy))
            if x1 > x0 && y1 > y0 { fillDevice(x0, y0, x1, y1) }
        }

        /// canvas drawImage(src, sx, sy, sw, sh, dx, dy, dw, dh): every device pixel in the destination samples the
        /// source at its centre, bilinear (smoothing on) or nearest (off); partial edge pixels are covered by area.
        func drawImage(_ src: Raster, _ sx: Double, _ sy: Double, _ sw: Double, _ sh: Double, _ dx: Double, _ dy: Double, _ dw: Double, _ dh: Double, smooth: Bool) {
            let d = deviceRect(dx, dy, dw, dh)
            guard d.x1 > d.x0 && d.y1 > d.y0 else { return }
            let flipX = m.a < 0, flipY = m.d < 0
            let ix0 = max(clip.x0, Int(floor(d.x0))), iy0 = max(clip.y0, Int(floor(d.y0))), ix1 = min(clip.x1, Int(ceil(d.x1))), iy1 = min(clip.y1, Int(ceil(d.y1)))
            guard ix1 > ix0 && iy1 > iy0 else { return }
            let kx = sw / (d.x1 - d.x0), ky = sh / (d.y1 - d.y0)
            for y in iy0..<iy1 {
                let c = Double(y) + 0.5, cy = max(0, min(1, min(c - d.y0, d.y1 - c) + 0.5))
                var v = (c - d.y0) * ky; if flipY { v = sh - v }; v += sy
                for x in ix0..<ix1 {
                    let cxx = Double(x) + 0.5, cov = min(cy, max(0, min(1, min(cxx - d.x0, d.x1 - cxx) + 0.5)))
                    if cov <= 0 { continue }
                    var u = (cxx - d.x0) * kx; if flipX { u = sw - u }; u += sx
                    var sr: Double, sg: Double, sb: Double, sa: Double
                    if smooth { (sr, sg, sb, sa) = Pix.bilinear(src, u, v) } else {
                        // nearest: when a pixel centre lands exactly on a sample boundary (a 5.25 px block does, every
                        // other row) the GPU's interpolated texture coordinate comes out just under it: the lower sample
                        let eps = 1e-6
                        let px = min(src.w - 1, max(0, Int(floor(u - eps)))), py = min(src.h - 1, max(0, Int(floor(v - eps))))
                        let p = src.data + (py * src.w + px) * 4
                        sr = Double(p[0]); sg = Double(p[1]); sb = Double(p[2]); sa = Double(p[3])
                    }
                    if alpha < 1 { sr *= alpha; sg *= alpha; sb *= alpha; sa *= alpha }
                    if sa <= 0 { continue }
                    if sa >= 255 && cov >= 1 { let p = r.data + (y * r.w + x) * 4; p[0] = UInt8(sr); p[1] = UInt8(sg); p[2] = UInt8(sb); p[3] = 255; continue }
                    blend((y * r.w + x) * 4, sr, sg, sb, sa, cov)
                }
            }
        }
    }

    // MARK: - resampling (what a canvas does for drawImage with smoothing)

    /// How the canvas resampled, tuned against the Lab's reference frames (tools/pix-compare.sh): the halvings
    /// happen on GPU canvases (hardware bilinear, 8-bit stores), the last step into the `lo` canvas on the CPU
    /// (willReadFrequently), where Chrome's 'high' quality came out as plain bilinear, not a cubic.
    enum Bilinear { case lowp, hw8, float }       // lowp: Skia's 8-bit areas; hw8: 8-bit fractions, float sum; float: exact
    nonisolated(unsafe) static var halveMode: Bilinear = .float
    nonisolated(unsafe) static var halveTiesUp = false            // the GPU's float → unorm8: ties to even (false) or up (true)
    nonisolated(unsafe) static var lastMode: Bilinear = .float
    nonisolated(unsafe) static var lastTiesUp = false             // the CPU canvas stores: ties to even matched the Lab best
    nonisolated(unsafe) static var unpremulTiesUp = false         // getImageData's unpremultiply
    nonisolated(unsafe) static var highIsCubic = false            // imageSmoothingQuality 'high' as a Mitchell cubic (B = C = 1/3)
    nonisolated(unsafe) static var highIsMip = true               // … or as linear filtering over linear mipmaps (what Chrome did)
    nonisolated(unsafe) static var subtexelBits = 8
    nonisolated(unsafe) static var mipBias = 0.5                   // Skia's sharpen bias on the mip level
    nonisolated(unsafe) static var mipAxisMax = false              // the level from the most shrunk axis (false, Skia) or the least
    @inline(__always) static func store8(_ v: Double, tiesUp: Bool) -> UInt8 {
        let c = max(0, min(255, v)); return UInt8(tiesUp ? floor(c + 0.5) : c.rounded(.toNearestOrEven))
    }

    /// Bilinear sample of a premultiplied raster at continuous pixel coords (u, v), clamped at the edges (0…255 floats).
    @inline(__always) static func bilinear(_ s: Raster, _ u: Double, _ v: Double, _ bilinearMode: Bilinear = .float) -> (Double, Double, Double, Double) {
        let fx0 = u - 0.5, fy0 = v - 0.5
        let x0 = Int(floor(fx0)), y0 = Int(floor(fy0))
        var tx = fx0 - Double(x0), ty = fy0 - Double(y0)
        let xa = min(s.w - 1, max(0, x0)), xb = min(s.w - 1, max(0, x0 + 1)), ya = min(s.h - 1, max(0, y0)), yb = min(s.h - 1, max(0, y0 + 1))
        let p00 = s.data + (ya * s.w + xa) * 4, p10 = s.data + (ya * s.w + xb) * 4, p01 = s.data + (yb * s.w + xa) * 4, p11 = s.data + (yb * s.w + xb) * 4
        switch bilinearMode {
        case .lowp:
            let w00 = Int((1 - tx) * (1 - ty) * 256), w10 = Int(tx * (1 - ty) * 256), w01 = Int((1 - tx) * ty * 256)
            let w11 = 256 - w00 - w10 - w01
            @inline(__always) func ch(_ i: Int) -> Double { Double((Int(p00[i]) * w00 + Int(p10[i]) * w10 + Int(p01[i]) * w01 + Int(p11[i]) * w11 + 128) >> 8) }
            return (ch(0), ch(1), ch(2), ch(3))
        case .hw8:
            let q = Double(1 << subtexelBits)
            tx = floor(tx * q) / q; ty = floor(ty * q) / q
            fallthrough
        case .float:
            let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
            @inline(__always) func ch(_ i: Int) -> Double { Double(p00[i]) * w00 + Double(p10[i]) * w10 + Double(p01[i]) * w01 + Double(p11[i]) * w11 }
            return (ch(0), ch(1), ch(2), ch(3))
        }
    }

    /// Mitchell–Netravali (B = C = 1/3) weights, Skia's near/far split: taps at −1.5, −0.5, +0.5, +1.5 from the sample.
    @inline(__always) static func cubicNear(_ t: Double) -> Double { t * (t * ((-21.0 / 18) * t + 27.0 / 18) + 9.0 / 18) + 1.0 / 18 }
    @inline(__always) static func cubicFar(_ t: Double) -> Double { t * t * ((7.0 / 18) * t - 6.0 / 18) }

    /// drawImage of a whole raster into a fresh `nw × nh` raster, as a canvas does with smoothing on.
    /// Skia's next mipmap level: a 2×2 box, or a 1-2-1 tent along an odd side, integer-truncated.
    static func mipLevel(_ src: Raster) -> Raster {
        let w1 = max(1, src.w >> 1), h1 = max(1, src.h >> 1), oddW = src.w & 1 == 1 && src.w > 1, oddH = src.h & 1 == 1 && src.h > 1
        let dst = surface("mip", w1, h1)
        let wx: [Int] = oddW ? [1, 2, 1] : [1, 1], wy: [Int] = oddH ? [1, 2, 1] : [1, 1]
        let shift = (oddW ? 1 : 0) + (oddH ? 1 : 0) + 2
        for y in 0..<h1 { for x in 0..<w1 {
            var acc = (0, 0, 0, 0)
            for (j, wyj) in wy.enumerated() { for (i, wxi) in wx.enumerated() {
                let p = src.data + ((2 * y + j) * src.w + 2 * x + i) * 4, w = wxi * wyj
                acc.0 += Int(p[0]) * w; acc.1 += Int(p[1]) * w; acc.2 += Int(p[2]) * w; acc.3 += Int(p[3]) * w
            } }
            let o = dst.data + (y * w1 + x) * 4
            o[0] = UInt8(acc.0 >> shift); o[1] = UInt8(acc.1 >> shift); o[2] = UInt8(acc.2 >> shift); o[3] = UInt8(acc.3 >> shift)
        } }
        return dst
    }

    static func resample(_ src: Raster, into dst: Raster, cubic: Bool, mode: Bilinear, tiesUp: Bool, mip: Bool = false) {
        let nw = dst.w, nh = dst.h, sw = src.w, sh = src.h
        let kx = Double(sw) / Double(nw), ky = Double(sh) / Double(nh)
        dst.clear()
        // linear mipmapping as Skia does it when the draw shrinks the image: level L = −log2(scale) − ½ (its GPU-style
        // sharpen bias), the two nearest levels sampled bilinearly and mixed
        var mip1: Raster? = nil, mipT = 0.0
        if mip && !cubic {
            let scale = mipAxisMax ? max(Double(nw) / Double(sw), Double(nh) / Double(sh)) : min(Double(nw) / Double(sw), Double(nh) / Double(sh))
            let L = max(-log2(scale) - mipBias, 0)
            if L > 0 { mip1 = mipLevel(src); mipT = min(1, L) }
        }
        for j in 0..<nh {
            let cy = (Double(j) + 0.5) * ky
            for i in 0..<nw {
                let cx = (Double(i) + 0.5) * kx
                let o = dst.data + (j * nw + i) * 4
                if !cubic {
                    var (r, g, b, a) = bilinear(src, cx, cy, mode)
                    if let m = mip1 {
                        let (r1, g1, b1, a1) = bilinear(m, cx * Double(m.w) / Double(sw), cy * Double(m.h) / Double(sh), mode)
                        r += (r1 - r) * mipT; g += (g1 - g) * mipT; b += (b1 - b) * mipT; a += (a1 - a) * mipT
                    }
                    o[0] = store8(r, tiesUp: tiesUp); o[1] = store8(g, tiesUp: tiesUp); o[2] = store8(b, tiesUp: tiesUp); o[3] = store8(a, tiesUp: tiesUp); continue
                }
                let fx = cx + 0.5 - floor(cx + 0.5), fy = cy + 0.5 - floor(cy + 0.5)
                let wx = SIMD4<Double>(cubicFar(1 - fx), cubicNear(1 - fx), cubicNear(fx), cubicFar(fx))
                let wy = SIMD4<Double>(cubicFar(1 - fy), cubicNear(1 - fy), cubicNear(fy), cubicFar(fy))
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for yy in 0..<4 {
                    let py = min(sh - 1, max(0, Int(floor(cy - 1.5 + Double(yy)))))
                    for xx in 0..<4 {
                        let px = min(sw - 1, max(0, Int(floor(cx - 1.5 + Double(xx)))))
                        let w = wx[xx] * wy[yy], p = src.data + (py * sw + px) * 4
                        r += Double(p[0]) * w; g += Double(p[1]) * w; b += Double(p[2]) * w; a += Double(p[3]) * w
                    }
                }
                a = max(0, min(255, a))
                o[0] = store8(min(a, r), tiesUp: tiesUp); o[1] = store8(min(a, g), tiesUp: tiesUp); o[2] = store8(min(a, b), tiesUp: tiesUp); o[3] = store8(a, tiesUp: tiesUp)
            }
        }
    }

    /// Pooled scratch surfaces (hi, half0, half1, lo), reused between frames like the JS `pool`.
    nonisolated(unsafe) static var pool: [String: Raster] = [:]
    static func surface(_ key: String, _ w: Int, _ h: Int) -> Raster {
        if let r = pool[key], r.w == w, r.h == h { return r }
        let r = Raster(w: w, h: h); pool[key] = r; return r
    }

    /// For the verification harness: sees every intermediate surface of atRes (name, raster).
    nonisolated(unsafe) static var debugHook: ((String, Raster) -> Void)? = nil

    /// Draw something at full resolution, then show it at `block` pt per sample, with hard pixel edges.
    static func atRes(_ g: G, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ block: Double, _ draw: (G) -> Void) {
        let s0 = jsHypot(g.m.a, g.m.b), s = s0 == 0 ? 1 : s0
        let hi = surface("hi", Int(ceil(w * s)), Int(ceil(h * s)))
        hi.clear()
        let hg = G(hi); hg.setTransform(s, 0, 0, s, -x * s, -y * s); draw(hg)
        debugHook?("hi", hi)
        if block * s <= 1.01 { g.drawImage(hi, 0, 0, Double(hi.w), Double(hi.h), x, y, w, h, smooth: true); return }
        let lw = max(1, Int(jsRound(w / block))), lh = max(1, Int(jsRound(h / block)))
        var src = hi, sw = hi.w, sh = hi.h, k = 0
        while Double(sw) / 2 >= Double(lw) && Double(sh) / 2 >= Double(lh) {
            let nw = max(lw, Int(jsRound(Double(sw) / 2))), nh = max(lh, Int(jsRound(Double(sh) / 2)))
            let c = surface("half\(k % 2)", nw, nh); k += 1
            resample(src, into: c, cubic: false, mode: halveMode, tiesUp: halveTiesUp)
            debugHook?("half\(k)", c)
            src = c; sw = nw; sh = nh
        }
        let lo = surface("lo", lw, lh)
        resample(src, into: lo, cubic: highIsCubic, mode: lastMode, tiesUp: lastTiesUp, mip: highIsMip)
        debugHook?("lo", lo)
        // getImageData (unpremultiplied) → alpha thresholded at 96 → putImageData
        let n = lw * lh
        for i in 0..<n {
            let p = lo.data + i * 4, a = Int(p[3])
            if a > 96 {
                if a < 255 {
                    p[0] = store8(Double(p[0]) * 255 / Double(a), tiesUp: unpremulTiesUp)
                    p[1] = store8(Double(p[1]) * 255 / Double(a), tiesUp: unpremulTiesUp)
                    p[2] = store8(Double(p[2]) * 255 / Double(a), tiesUp: unpremulTiesUp)
                }
                p[3] = 255
            } else { p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0 }
        }
        g.drawImage(lo, 0, 0, Double(lw), Double(lh), x, y, Double(lw) * block, Double(lh) * block, smooth: false)
    }

    // MARK: - pixel font, 3 × 5

    static let FONT: [UInt8: [UInt8]] = {
        let f: [Character: [UInt8]] = [
            "A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6], "C": [3, 4, 4, 4, 3], "D": [6, 5, 5, 5, 6], "E": [7, 4, 6, 4, 7], "F": [7, 4, 6, 4, 4], "G": [3, 4, 5, 5, 3],
            "H": [5, 5, 7, 5, 5], "I": [7, 2, 2, 2, 7], "J": [1, 1, 1, 5, 2], "K": [5, 5, 6, 5, 5], "L": [4, 4, 4, 4, 7], "M": [5, 7, 7, 5, 5], "N": [6, 5, 5, 5, 5],
            "O": [2, 5, 5, 5, 2], "P": [6, 5, 6, 4, 4], "Q": [2, 5, 5, 6, 3], "R": [6, 5, 6, 5, 5], "S": [3, 4, 2, 1, 6], "T": [7, 2, 2, 2, 2], "U": [5, 5, 5, 5, 7],
            "V": [5, 5, 5, 5, 2], "W": [5, 5, 7, 7, 5], "X": [5, 5, 2, 5, 5], "Y": [5, 5, 2, 2, 2], "Z": [7, 1, 2, 4, 7],
            "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [6, 1, 2, 4, 7], "3": [6, 1, 2, 1, 6], "4": [5, 5, 7, 1, 1], "5": [7, 4, 6, 1, 6], "6": [3, 4, 6, 5, 2],
            "7": [7, 1, 2, 2, 2], "8": [2, 5, 2, 5, 2], "9": [2, 5, 3, 1, 6], "+": [0, 2, 7, 2, 0], "-": [0, 0, 7, 0, 0], ".": [0, 0, 0, 0, 2], "!": [2, 2, 2, 0, 2],
            "?": [6, 1, 2, 0, 2], ":": [0, 2, 0, 2, 0], "'": [2, 2, 0, 0, 0], "/": [1, 1, 2, 4, 4], ",": [0, 0, 0, 2, 4], "(": [1, 2, 2, 2, 1], ")": [4, 2, 2, 2, 4], " ": [0, 0, 0, 0, 0],
            "$": [3, 6, 2, 3, 6], "%": [5, 1, 2, 4, 5],
        ]
        var out: [UInt8: [UInt8]] = [:]
        for (k, v) in f { out[k.asciiValue!] = v }
        return out
    }()
    enum Align { case left, center, right }
    static func textWidth(_ str: String, _ s: Double) -> Double { max(0, Double(str.utf8.count) * 4 * s - s) }
    static func text(_ g: G, _ str0: String, _ x: Double, _ y: Double, _ s: Double, _ col: RGBA, _ align: Align = .left) {
        let str = str0.uppercased()
        var cx = align == .center ? x - textWidth(str, s) / 2 : align == .right ? x - textWidth(str, s) : x
        g.fill = col
        let blank = FONT[32]!
        for ch in str.utf8 {
            let gl = FONT[ch] ?? blank
            for r in 0..<5 { for c in 0..<3 where gl[r] & (4 >> c) != 0 { g.snap(cx + Double(c) * s, y + Double(r) * s, s, s) } }
            cx += 4 * s
        }
    }

    // MARK: - the sprite

    /// What `paint` draws: the JS `o` object.
    struct Sprite {
        var sp: SpeciesData
        var ox: Double, oy: Double, px: Double
        var mood: Mood
        var eyeMode: EyeMode? = nil        // nil → side
        var look = 1.0
        var legs: LegPose = .stand
        var dy = 0.0
        var flip = false
        var stem: StemPose = .curl
        var mouth = 0                      // 0 none, 1 thin, 2 open
        var boost = 0.0, rot = 0.0, spots = 0.0
        var by = 0.0                       // HD: vertical float
        var offset: ((Int, Int) -> (Double, Double))? = nil
    }
    static func base(_ sp: SpeciesData, _ px: Double, _ cx: Double, _ cy: Double, _ mood: Mood) -> Sprite {
        Sprite(sp: sp, ox: jsRound(cx - Double(sp.W) * px / 2), oy: jsRound(cy - Double(sp.H) * px / 2), px: px, mood: mood)
    }

    static func paint(_ g: G, _ o: Sprite) {
        let sp = o.sp, ox = o.ox, oy = o.oy, px = o.px, mood = o.mood, dy = o.dy, H = sp.H
        let b = jsRound(o.boost * 200) / 200, rot = jsRound(o.rot * 20) / 20, spots = jsRound(o.spots * 20) / 20
        let bq = Int16(jsRound(o.boost * 200)), rq = Int8(jsRound(o.rot * 20)), sq = Int8(jsRound(o.spots * 20))
        @inline(__always) func Y(_ y: Int) -> Double { Double(o.flip ? H - 1 - y : y) }
        let lift = dy * (o.flip ? -1 : 1)
        @inline(__always) func cell(_ x: Int, _ y: Int, _ col: RGBA, _ lifted: Bool) {
            let off = o.offset?(x, y) ?? (0, 0)
            g.fill = col
            g.snap(ox + (Double(x) + off.0) * px, oy + (Y(y) + off.1 + (lifted ? lift : 0)) * px, px, px)
        }
        let leg = legColor(sp, mood)
        for (x, y) in sp.legs[o.legs]! { cell(x, y, leg, false) }
        let spi = UInt8(sp.key == .apple ? 0 : 1)
        for (x, y, k) in sp.parts[o.stem]! {
            let key = MemoKey(sp: spi, kind: k.rawValue, mood: -1, x: Int8(x), y: Int8(y), b: bq, rot: rq, spots: 0)
            cell(x, y, color(key) { shadePart(sp, k, x, y, b, rot) }, true)
        }
        let mi = Int8(mood.rawValue)
        for (x, y, _) in sp.cells {
            let key = MemoKey(sp: spi, kind: 0, mood: mi, x: Int8(x), y: Int8(y), b: bq, rot: rq, spots: sq)
            cell(x, y, color(key) { shadeBody(sp, mood, x, y, b, rot, spots) }, true)
        }
        eyes(g, o, Y)
        if o.mouth != 0 {
            let (mx, my, mw) = sp.mouth, top = oy + (Y(my) + lift) * px, h = o.mouth == 1 ? px * 0.45 : px
            g.fill = INK; g.snap(ox + Double(mx) * px, top + (px - h) / 2, px * Double(mw), h)
        }
    }

    static func eyes(_ g: G, _ o: Sprite, _ Y: (Int) -> Double) {
        let sp = o.sp, ox = o.ox, oy = o.oy, px = o.px, mode = o.eyeMode ?? .side, look = o.look, dy = o.dy * (o.flip ? -1 : 1), EY = sp.eyeY
        if mode == .none { return }
        func box(_ cx: Int, _ cy: Int, _ col: RGBA, _ fx: Double = 0, _ fy: Double = 0, _ fw: Double = 1, _ fh: Double = 1) {
            g.fill = col; g.snap(ox + (Double(cx) + fx) * px, oy + (Y(cy) + dy + fy) * px, fw * px, fh * px)
        }
        for (i, ex) in sp.eyes.enumerated() {
            if mode == .closed { box(ex, EY, RGBA(10, 10, 12, alpha: 0.82), 0, 0.55, 2, 0.3); continue }
            if mode == .happy { box(ex, EY, WHITE, 0, 0, 2, 0.42); continue }
            if mode == .cam { box(ex, EY, INK, 0, 0, 2, 1); box(ex, EY, WHITE, 0.18, 0.16, 0.32, 0.32); continue }
            if mode == .up { box(ex, EY, WHITE, 0, 0, 2, 1); box(ex, EY - 1, WHITE, 0, 0, 2, 1); box(ex + (look > 0 ? 1 : 0), EY - 1, INK); continue }
            var right = look > 0
            if mode == .cross { right = i == 0 }
            if mode == .squint { box(ex, EY, right ? WHITE : INK, 0, 0.5, 1, 0.5); box(ex + 1, EY, right ? INK : WHITE, 0, 0.5, 1, 0.5); continue }
            box(ex, EY, right ? WHITE : INK); box(ex + 1, EY, right ? INK : WHITE)
        }
    }

    // MARK: - HD: the same fruit as smooth shapes, with everything the pixels could not afford

    /// A closed curve through the midpoints of a point list.
    static func smooth(_ path: CGMutablePath, _ pts: [CGPoint]) {
        let n = pts.count
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n { let p = pts[i], q = mid(pts[i], pts[(i + 1) % n]); path.addQuadCurve(to: q, control: p) }
        path.closeSubpath()
    }
    static func ellipsePath(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ rot: Double) -> CGPath {
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: CGAffineTransform(translationX: x, y: y).rotated(by: rot))
        return p
    }
    static func gradient(_ stops: [(Double, RGBA)]) -> CGGradient {
        CGGradient(colorsSpace: deviceRGB, colors: stops.map { $0.1.cg } as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    struct BananaPoint { var x: Double, y: Double, nx: Double, ny: Double, w: Double }
    static let BANANA_P: [(Double, Double)] = [(2.6, 1.7), (16.6, 10.6), (2.9, 20.9)]
    /// centerline: a quadratic from the stem end (top left) bowing right to the blunt end (bottom left)
    static func bananaAt(_ t: Double) -> BananaPoint {
        let (a, b, c) = (BANANA_P[0], BANANA_P[1], BANANA_P[2]), u = 1 - t
        let x = u * u * a.0 + 2 * u * t * b.0 + t * t * c.0, y = u * u * a.1 + 2 * u * t * b.1 + t * t * c.1
        let dx = 2 * u * (b.0 - a.0) + 2 * t * (c.0 - b.0), dy = 2 * u * (b.1 - a.1) + 2 * t * (c.1 - b.1), l0 = jsHypot(dx, dy), l = l0 == 0 ? 1 : l0
        var w = 1.5 + 6.6 * pow(sin(Double.pi * pow(min(t, 0.985), 1.18)), 0.62)
        if t > 0.86 { w = max(w, 4.6 - (t - 0.86) * 7) }                  // the blunt end
        return BananaPoint(x: x, y: y, nx: -dy / l, ny: dx / l, w: w)      // n points to the concave (left) side
    }

    /// The HD painting goes through CoreGraphics on the same bitmap. `cg` carries the canvas transform.
    static func paintHD(_ g: G, _ o: Sprite, _ t: Double) {
        let sp = o.sp, ox = o.ox, oy = o.oy, px = o.px, mood = o.mood, P = PAL[mood.rawValue], look = o.look, by = o.by
        let X: (Double) -> Double = { ox + $0 * px }, Y: (Double) -> Double = { oy + $0 * px + by }
        let cg = g.r.cg
        cg.saveGState()
        cg.clip(to: CGRect(x: g.clip.x0, y: g.clip.y0, width: g.clip.x1 - g.clip.x0, height: g.clip.y1 - g.clip.y0))   // the canvas's clip, in pixels
        cg.concatenate(g.m.cg)                                                                                            // then its transform
        cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.setAlpha(CGFloat(g.alpha))
        cg.setStrokeColor(legColor(sp, mood).cg); cg.setLineWidth(px * 0.78)
        for (lx, y0, y1, fx) in sp.legsHD {
            cg.beginPath(); cg.move(to: CGPoint(x: X(lx), y: Y(y0))); cg.addLine(to: CGPoint(x: X(lx), y: Y(y1))); cg.addLine(to: CGPoint(x: X(fx), y: Y(y1))); cg.strokePath()
        }
        let bounds: (Double, Double, Double, Double)
        func body() -> CGPath {
            let p = CGMutablePath()
            if sp.key == .apple {
                p.move(to: CGPoint(x: X(7.5), y: Y(4.1)))
                p.addCurve(to: CGPoint(x: X(14.2), y: Y(5.2)), control1: CGPoint(x: X(8.6), y: Y(2.7)), control2: CGPoint(x: X(12.6), y: Y(2.4)))
                p.addCurve(to: CGPoint(x: X(11.6), y: Y(14.5)), control1: CGPoint(x: X(15.5), y: Y(8.2)), control2: CGPoint(x: X(14.6), y: Y(12.8)))
                p.addCurve(to: CGPoint(x: X(7.5), y: Y(14.8)), control1: CGPoint(x: X(10.2), y: Y(15.3)), control2: CGPoint(x: X(8.7), y: Y(14.7)))
                p.addCurve(to: CGPoint(x: X(3.4), y: Y(14.5)), control1: CGPoint(x: X(6.3), y: Y(14.7)), control2: CGPoint(x: X(4.8), y: Y(15.3)))
                p.addCurve(to: CGPoint(x: X(0.8), y: Y(5.2)), control1: CGPoint(x: X(0.4), y: Y(12.8)), control2: CGPoint(x: X(-0.5), y: Y(8.2)))
                p.addCurve(to: CGPoint(x: X(7.5), y: Y(4.1)), control1: CGPoint(x: X(2.4), y: Y(2.4)), control2: CGPoint(x: X(6.4), y: Y(2.7)))
                p.closeSubpath()
            } else {
                let N = 28; var L: [CGPoint] = [], R: [CGPoint] = []
                for i in 0...N {
                    let q = bananaAt(Double(i) / Double(N))
                    L.append(CGPoint(x: X(q.x + q.nx * q.w / 2), y: Y(q.y + q.ny * q.w / 2))); R.append(CGPoint(x: X(q.x - q.nx * q.w / 2), y: Y(q.y - q.ny * q.w / 2)))
                }
                smooth(p, R + L.reversed())
            }
            return p
        }
        if sp.key == .apple {
            bounds = (-0.6, 2.3, 15.6, 15.4)
            // back: stem and leaf
            cg.setStrokeColor(RGBA(hex: 0x5A3418).cg); cg.setLineWidth(px * 0.9)
            cg.beginPath(); cg.move(to: CGPoint(x: X(7.5), y: Y(4.2))); cg.addQuadCurve(to: CGPoint(x: X(8.4), y: Y(0.5)), control: CGPoint(x: X(7.1), y: Y(2.0))); cg.strokePath()
            let leaf = CGMutablePath()
            leaf.move(to: CGPoint(x: X(8.2), y: Y(2.3))); leaf.addQuadCurve(to: CGPoint(x: X(13.1), y: Y(0.8)), control: CGPoint(x: X(9.4), y: Y(-0.3)))
            leaf.addQuadCurve(to: CGPoint(x: X(8.2), y: Y(2.3)), control: CGPoint(x: X(11.6), y: Y(3.1)))
            cg.saveGState(); cg.addPath(leaf); cg.clip()
            cg.drawLinearGradient(gradient([(0, RGBA(hex: 0x2F8F43)), (1, RGBA(hex: 0xC2F57E))]), start: CGPoint(x: X(8), y: Y(2.4)), end: CGPoint(x: X(13), y: Y(0.6)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            cg.restoreGState()
            cg.beginPath(); cg.move(to: CGPoint(x: X(8.6), y: Y(2.1))); cg.addQuadCurve(to: CGPoint(x: X(12.4), y: Y(0.95)), control: CGPoint(x: X(10.4), y: Y(1.2)))
            cg.setLineWidth(px * 0.16); cg.setStrokeColor(RGBA(20, 80, 30, alpha: 0.55).cg); cg.strokePath()
        } else {
            bounds = (0, 0, 15, 22)
            cg.setStrokeColor(RGBA(hex: 0x5E5524).cg); cg.setLineWidth(px * 1.0); cg.setLineCap(.butt)
            cg.beginPath(); cg.move(to: CGPoint(x: X(3.0), y: Y(2.4))); cg.addQuadCurve(to: CGPoint(x: X(1.0), y: Y(0.4)), control: CGPoint(x: X(2.1), y: Y(1.0))); cg.strokePath(); cg.setLineCap(.round)
            cg.addPath(ellipsePath(X(1.0), Y(0.4), px * 0.5, px * 0.55, 0.5)); cg.setFillColor(RGBA(hex: 0x3A2414).cg); cg.fillPath()
        }
        let (bx0, by0, bx1, by1) = bounds
        let bodyPath = body()
        cg.saveGState(); cg.addPath(bodyPath); cg.clip()
        cg.drawLinearGradient(gradient(P.enumerated().map { (Double($0.offset) / Double(P.count - 1), RGBA(hex: UInt32(P[$0.offset].dropFirst(), radix: 16)!)) }),
                              start: CGPoint(x: X(bx0), y: Y(by0)), end: CGPoint(x: X(bx0 + (bx1 - bx0) * 0.9), y: Y(by1 * 1.02)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.drawRadialGradient(gradient([(0, RGBA(255, 255, 255, alpha: 0.4)), (1, RGBA(255, 255, 255, alpha: 0))]),
                              startCenter: CGPoint(x: X(bx0 + 3.4), y: Y(by0 + 2.6)), startRadius: 0, endCenter: CGPoint(x: X(bx0 + 3.4), y: Y(by0 + 2.6)), endRadius: 9 * px, options: [.drawsBeforeStartLocation])
        cg.drawLinearGradient(gradient([(0, RGBA(60, 0, 40, alpha: 0)), (1, RGBA(60, 0, 40, alpha: 0.3))]),
                              start: CGPoint(x: 0, y: Y(by0 + (by1 - by0) * 0.45)), end: CGPoint(x: 0, y: Y(by1)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
        cg.addPath(bodyPath); cg.setLineWidth(px * 0.14); cg.setStrokeColor(RGBA(255, 255, 255, alpha: 0.35).cg); cg.strokePath()
        // front
        if sp.key == .apple {
            cg.addPath(ellipsePath(X(3.6), Y(5.8), px * 1.7, px * 0.7, -0.7)); cg.setFillColor(RGBA(255, 255, 255, alpha: 0.72).cg); cg.fillPath()
        } else {
            let e = bananaAt(1)
            cg.addPath(ellipsePath(X(e.x), Y(e.y), px * 1.3, px * 0.75, atan2(e.ny, e.nx))); cg.setFillColor(RGBA(hex: 0x5A3A20).cg); cg.fillPath()
            func line(_ t0: Double, _ t1: Double, _ off: Double, _ w: Double, _ col: RGBA) {
                cg.beginPath()
                for i in 0...20 {
                    let q = bananaAt(t0 + (t1 - t0) * Double(i) / 20), pt = CGPoint(x: X(q.x + q.nx * q.w * off), y: Y(q.y + q.ny * q.w * off))
                    if i == 0 { cg.move(to: pt) } else { cg.addLine(to: pt) }
                }
                cg.setLineWidth(px * w); cg.setStrokeColor(col.cg); cg.strokePath()
            }
            line(0.22, 0.9, -0.22, 0.2, RGBA(160, 100, 0, alpha: 0.22))                      // the ridge on the back
            line(0.3, 0.62, 0.3, 0.5, RGBA(255, 255, 255, alpha: 0.6))                        // gloss
        }
        // face
        let ec = sp.eyes.map { (Double($0) + 1, Double(sp.eyeY) + 0.5) }
        let bdx = sp.blushDX
        for (i, e) in ec.enumerated() {
            cg.addPath(ellipsePath(X(e.0 + (i == 1 ? bdx : -bdx)), Y(e.1 + 2.0), px * 1.0, px * 0.48, 0)); cg.setFillColor(RGBA(255, 80, 130, alpha: 0.42).cg); cg.fillPath()
        }
        for e in ec {
            cg.addPath(ellipsePath(X(e.0), Y(e.1), px * 1.05, px * 1.3, 0)); cg.setFillColor(WHITE.cg); cg.fillPath()
            let pxp = X(e.0) + look * px * 0.32
            cg.addPath(ellipsePath(pxp, Y(e.1) + px * 0.12, px * 0.66, px * 0.8, 0)); cg.setFillColor(INK.cg); cg.fillPath()
            cg.addPath(ellipsePath(pxp - px * 0.24, Y(e.1) - px * 0.22, px * 0.26, px * 0.26, 0)); cg.setFillColor(WHITE.cg); cg.fillPath()
            cg.addPath(ellipsePath(pxp + px * 0.24, Y(e.1) + px * 0.38, px * 0.11, px * 0.11, 0)); cg.fillPath()
        }
        let (mx, my, mw) = sp.mouth, mcx = Double(mx) + Double(mw) / 2
        cg.beginPath(); cg.move(to: CGPoint(x: X(mcx - 0.9), y: Y(Double(my) + 0.35))); cg.addQuadCurve(to: CGPoint(x: X(mcx + 0.9), y: Y(Double(my) + 0.35)), control: CGPoint(x: X(mcx), y: Y(Double(my) + 1.1)))
        cg.setLineWidth(px * 0.32); cg.setStrokeColor(INK.cg); cg.strokePath()
        // sparkles
        func spark(_ x: Double, _ y: Double, _ s: Double) {
            if s <= 0 { return }
            cg.beginPath(); cg.move(to: CGPoint(x: x, y: y - s))
            cg.addQuadCurve(to: CGPoint(x: x + s, y: y), control: CGPoint(x: x, y: y)); cg.addQuadCurve(to: CGPoint(x: x, y: y + s), control: CGPoint(x: x, y: y))
            cg.addQuadCurve(to: CGPoint(x: x - s, y: y), control: CGPoint(x: x, y: y)); cg.addQuadCurve(to: CGPoint(x: x, y: y - s), control: CGPoint(x: x, y: y))
            cg.setFillColor(WHITE.cg); cg.fillPath()
        }
        for (sx, sy, ph) in [(-0.6, by0 + 1.5, 0.0), (bx1 + 0.2, by0 + 3, 1.3), (bx1 - 0.8, by0 - 1.2, 2.1), (-0.2, by1 - 2.5, 3.2), (bx1 + 0.6, by1 - 3.5, 0.7)] {
            spark(X(sx), Y(sy), px * 0.9 * max(0, sin(t * 5 + ph)))
        }
        // badge
        let bx = X(sp.badge.0), byy = Y(sp.badge.1)
        cg.addPath(CGPath(roundedRect: CGRect(x: bx - px * 1.35, y: byy - px * 0.75, width: px * 2.7, height: px * 1.5), cornerWidth: px * 0.45, cornerHeight: px * 0.45, transform: nil))
        cg.setFillColor(WHITE.cg); cg.fillPath()
        badgeText(cg, "HD", bx, byy + px * 0.06, size: px * 1.15)
        cg.restoreGState()
    }

    /// The HD badge's label: `800 ${px*1.15}px ui-rounded, system-ui`, centred, baseline middle.
    nonisolated(unsafe) static var badgeFontCache: (size: Double, font: CTFont)? = nil
    static func badgeText(_ cg: CGContext, _ s: String, _ x: Double, _ y: Double, size: Double) {
        let font: CTFont
        if let c = badgeFontCache, c.size == size { font = c.font } else {
            let traits: [CFString: Any] = [kCTFontWeightTrait: 0.56]       // heavy
            let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: ".AppleSystemUIFont", kCTFontTraitsAttribute: traits]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            font = CTFontCreateWithFontDescriptor(desc, size, nil)
            badgeFontCache = (size, font)
        }
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): INK.cg]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        let asc = CTFontGetAscent(font), desc = CTFontGetDescent(font)
        cg.saveGState()
        cg.textMatrix = .identity
        // the context is y-down: flip around the baseline so glyphs stand upright
        cg.translateBy(x: x - w / 2, y: y + (asc - desc) / 2); cg.scaleBy(x: 1, y: -1)
        cg.setFillColor(INK.cg)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    // MARK: - states

    @inline(__always) static func blinkAt(_ t: Double, _ seed: Double = 0) -> Bool { fmod(t + seed * 0.7, 3.7) < 0.11 }

    /// Make a bitmap context Pix can draw into: premultiplied RGBA, origin top-left, user space in device pixels.
    static func makeRaster(width: Int, height: Int) -> Raster { Raster(w: width, h: height) }

    /// Draw one frame into a bitmap CGContext made by `Raster.cg` (or any premultiplied-RGBA, 32-bit, top-down bitmap
    /// context whose current transform maps the 198 × 242 design space to its pixels, like ctx.scale() in the Lab).
    static func draw(_ cg: CGContext, _ p: Params) {
        guard let data = cg.data, cg.bitsPerPixel == 32 else { return }
        let raster = Raster(borrowed: data.assumingMemoryBound(to: UInt8.self), w: cg.width, h: cg.height)
        var m = cg.ctm
        if m.d < 0 { m = m.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(cg.height))) }   // undo the y flip
        let g = G(raster); g.setTransform(m.a, m.b, m.c, m.d, m.tx, m.ty)
        draw(g, p)
    }
    /// Draw one frame into a Raster with a canvas transform (the fast path PixStage and the harness use).
    static func draw(_ r: Raster, transform m: Matrix, _ p: Params) { let g = G(r); g.m = m; draw(g, p) }

    static func draw(_ ctx: G, _ p: Params) {
        let sp = species(p.species), W = sp.W, H = sp.H, Wd = Double(W), Hd = Double(H)
        let st = p.state, T = p.stateT, t = p.t, px0 = jsRound(p.px * sp.pxScale)
        let scr = p.screen ?? CGRect(x: 0, y: 0, width: 198, height: 242)
        let sx = Double(scr.minX), sy = Double(scr.minY), sw = Double(scr.width), sh = Double(scr.height)
        let mood0 = p.ripe?.mood ?? p.palette ?? sp.moods[st] ?? sp.base
        func base(_ px: Double, _ cx: Double? = nil, _ cy: Double? = nil) -> Sprite {
            var o = Pix.base(sp, px, cx ?? p.cx, cy ?? p.cy, mood0)
            if let rp = p.ripe { o.spots = max(o.spots, rp.spots); o.rot = max(o.rot, rp.rot) }
            return o
        }
        let idleBob = Double(Int(floor(t * 1.25)) % 2)
        ctx.save()
        defer { ctx.restore() }

        switch st {
        case .idle:
            let ph = fmod(t, 8), look = p.look ?? (ph < 2.6 ? 1 : ph < 5.2 ? -1 : 1)
            let mode = p.eyeMode ?? (blinkAt(t) ? .closed : (ph > 5.2 && ph < 6.5) ? .cam : .side)
            var o = base(px0); o.dy = p.eyeMode != nil ? 0 : idleBob; o.eyeMode = mode; o.look = look
            paint(ctx, o)

        case .listening:
            let v = clamp01(p.voice ?? (0.5 + 0.5 * sin(t * 9) * sin(t * 2.3)))
            let px = px0 + 1
            var o = base(px); o.stem = .antenna; o.boost = v * 0.05; o.eyeMode = blinkAt(t) ? .closed : .cam
            paint(ctx, o)
            // the stem is an antenna: ((( · ))) like a broadcast icon, one arc per loudness step
            let c = max(3, jsRound(px * 0.5)), tipx = o.ox + sp.tip.0 * px, tipy = o.oy + sp.tip.1 * px, n = Int(ceil(v * 3))
            ctx.fill = WHITE
            for i in 0..<n {
                ctx.alpha = 1 - Double(i) * 0.22
                let hh = i + 1
                for j in -hh...hh { for side in [-1.0, 1.0] {
                    let dx = (2 * Double(i) + 2.2 - (abs(j) == hh ? 1 : 0)) * c * side
                    ctx.fillRect(jsRound(tipx + dx - c / 2), jsRound(tipy + Double(j) * c - c / 2), c, c)
                } }
            }
            ctx.alpha = 1

        case .thinking:
            let c = fmod(T, 4.6), block: Double = c < 0.45 ? 1 : c < 1.3 ? 2 : c < 2.4 ? 3 : c < 4.0 ? 4 : 1
            let lk: Double = Int(floor(T / 1.15)) % 2 != 0 ? -1 : 1
            var o = base(px0); o.eyeMode = .up; o.look = lk
            if block == 1 { o.eyeMode = c >= 4.0 ? .cam : .up; paint(ctx, o) }
            else {
                atRes(ctx, o.ox, o.oy, Wd * o.px, Hd * o.px, o.px * block) { g in var q = o; q.eyeMode = EyeMode.none; paint(g, q) }
                eyes(ctx, o) { Double($0) }
            }

        case .working:
            let stepI = Int(floor(T / 0.2)), legs: LegPose = stepI % 2 != 0 ? .stepL : .stepR
            var o = base(px0); o.legs = legs; o.dy = Double(stepI % 2); o.eyeMode = blinkAt(t) ? .closed : .squint; o.look = 1
            paint(ctx, o)
            let tools = (p.tools.isEmpty ? ["Read", "Edit", "Bash", "Grep", "Edit", "Test"] : p.tools).map { $0.uppercased() }
            let every = 0.75, k0 = Int(floor(T / every))
            for k in max(0, k0 - 2)...k0 {
                let age = T - Double(k) * every; if age < 0 || age > 1.5 { continue }
                let label = "+1 " + tools[k % tools.count], rise = step(age / 1.5, 10) * max(8, min(34, o.oy - 20 - sy))
                let x = o.ox + Wd * o.px / 2 + (k % 2 != 0 ? 30 : -30), y = o.oy - 14 - rise
                ctx.alpha = age > 1.1 ? 0.5 : 1
                text(ctx, label, x + 1, y + 1, 2, RGBA(120, 40, 0, alpha: 0.9), .center); text(ctx, label, x, y, 2, RGBA(hex: 0xFFE66B), .center)
            }
            ctx.alpha = 1
            if stepI % 4 == 1 { ctx.fill = RGBA(hex: 0x8FD8FF); let sx = o.ox + Wd * o.px + 2, sy = o.oy + 5 * o.px; ctx.fillRect(sx, sy, 3, 3); ctx.fillRect(sx, sy + 3, 2, 2) }

        case .speaking:
            let msg = (p.text ?? "All 14 tests pass. I also fixed a typo you made in 2019.").uppercased()
            let bx = sx + 8, bw = sw - 16, bh = 82.0, by = sy + sh - bh - 8, cpl = Int(floor((bw - 18) / 8))
            var lines: [String] = []; var line = ""
            for w in msg.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                if (line + " " + w).trimmingCharacters(in: .whitespaces).count > cpl { lines.append(line.trimmingCharacters(in: .whitespaces)); line = w } else { line += " " + w }
            }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line.trimmingCharacters(in: .whitespaces)) }
            let shown = Int(floor(T * 22)); var left = shown
            let typed: [String] = lines.map { l in let n = max(0, min(l.count, left)); left -= l.count; return String(l.prefix(n)) }
            let doneTyping = shown >= lines.joined().count
            let lastCh = (typed.last(where: { !$0.isEmpty }) ?? " ").last ?? " "
            let mouth = doneTyping ? 0 : ("AEIOU".contains(lastCh) ? 2 : Int(floor(T * 11)) % 2)
            let px = jsRound(5 * sp.pxScale)
            var o = base(px, sx + sw / 2, by - Hd * px / 2 - 8); o.dy = doneTyping ? idleBob : Double(Int(floor(T * 6)) % 2); o.mouth = mouth; o.eyeMode = blinkAt(t) ? .closed : .cam
            paint(ctx, o)
            ctx.fill = RGBA(hex: 0x0D0D1A); ctx.fillRect(bx, by, bw, bh)
            ctx.fill = WHITE; ctx.fillRect(bx, by, bw, 2); ctx.fillRect(bx, by + bh - 2, bw, 2); ctx.fillRect(bx, by, 2, bh); ctx.fillRect(bx + bw - 2, by, 2, bh)
            ctx.fill = RGBA(hex: 0x5B5BFF); ctx.fillRect(bx + 4, by + 4, bw - 8, 1); ctx.fillRect(bx + 4, by + bh - 5, bw - 8, 1)
            let tw = textWidth(sp.name, 2) + 12, ty = by - 15; ctx.fill = RGBA(hex: 0x0D0D1A); ctx.fillRect(bx + 10, ty, tw, 17)
            ctx.fill = WHITE; ctx.fillRect(bx + 10, ty, tw, 2); ctx.fillRect(bx + 10, ty, 2, 17); ctx.fillRect(bx + 10 + tw - 2, ty, 2, 17)
            text(ctx, sp.name, bx + 16, ty + 5, 2, RGBA(hex: 0xFFE66B))
            for (i, l) in typed.prefix(5).enumerated() { text(ctx, l, bx + 9, by + 12 + Double(i) * 13, 2, WHITE) }
            if doneTyping && Int(floor(t * 2.5)) % 2 != 0 { ctx.fill = WHITE; let ax = bx + bw - 16, ay = by + bh - 14; ctx.fillRect(ax, ay, 8, 2); ctx.fillRect(ax + 2, ay + 2, 4, 2); ctx.fillRect(ax + 3, ay + 4, 2, 2) }

        case .done:
            let c = fmod(T, 4.2); var o = base(px0); o.mood = sp.base
            let up = [0.14, 0.23, 0.32, 0.41], down = [2.55, 2.62, 2.69, 2.76], blocks = [1.0, 0.5, 0.25, 0.125]
            func region(_ b: Double, _ g: (G) -> Void) { atRes(ctx, o.ox - o.px, o.oy - 3 * o.px, (Wd + 2) * o.px, (Hd + 3) * o.px, o.px * b, g) }
            if c < 0.14 { var q = o; q.dy = -1; q.eyeMode = .happy; paint(ctx, q) }
            else if c < 0.5 { let i = up.firstIndex(where: { c < $0 + 0.09 }) ?? -1; region(blocks[max(0, i)]) { g in paintHD(g, o, t) } }
            else if c < 2.55 { var q = o; q.by = sin((c - 0.5) * 3.2) * 2.2; paintHD(ctx, q, t) }
            else if c < 2.83 { let i = down.firstIndex(where: { c < $0 + 0.07 }) ?? -1; region(blocks[3 - max(0, i)]) { g in paintHD(g, o, t) } }
            else { var q = o; q.dy = idleBob; q.eyeMode = c < 3.4 ? .happy : .side; q.look = 1; paint(ctx, q) }

        case .needs:
            let lean = max(0, min(3, min(floor((p.room ?? 172) / Hd) - px0, floor(max(0, T - 1.4) / 1.4))))
            let px = px0 + lean, hop = T < 0.26 ? -jsRound(sin(T / 0.26 * Double.pi) * 2) : 0
            var o = base(px, p.cx, p.cy + lean * 4); o.dy = hop; o.eyeMode = blinkAt(t, 2) && T > 1 ? .closed : .cam
            paint(ctx, o)
            if !p.bang { return }
            let pop = T < 0.1 ? T / 0.1 : 1, bob = Double(Int(floor(t * 2)) % 2), s = max(2, jsRound(px * 0.62 * pop))
            let ex = o.ox + sp.bangX * px - s, ey = o.oy - 1.5 * px + hop * px - bob * 2 - 7 * s
            ctx.fill = WHITE; ctx.fillRect(ex - s / 2, ey - s / 2, s * 3, s * 5.5); ctx.fillRect(ex - s / 2, ey + 5.5 * s, s * 3, s * 2.5)
            ctx.fill = RGBA(hex: 0xFF3B30); ctx.fillRect(ex, ey, s * 2, s * 4.5); ctx.fillRect(ex, ey + 6 * s, s * 2, s * 1.5)

        case .blocked:
            // dragged around like a frozen window: a stamp every frame, 15 pt apart, each one a bit more overripe
            let c = fmod(T, 6.5), px = max(3, jsRound(4 * sp.pxScale)), frames = min(Int(floor(c * 9)), 26)
            let pts: [(Double, Double)] = [(62, 96), (136, 104), (70, 160), (138, 178)]
            let P: [(Double, Double)] = pts.map { (q: (Double, Double)) -> (Double, Double) in
                let x: Double = sx + q.0 * sw / 198, y: Double = sy + q.1 * sh / 242
                return (x, y)
            }
            var seg: [Double] = []; var tot = 0.0
            for i in 1..<P.count { let l = jsHypot(P[i].0 - P[i - 1].0, P[i].1 - P[i - 1].1); seg.append(l); tot += l }
            func path(_ k: Int) -> (Double, Double) {
                var d = min(tot, Double(k) * 15)
                for i in 0..<seg.count { if d <= seg[i] { let f = d / seg[i]; return (P[i].0 + (P[i + 1].0 - P[i].0) * f, P[i].1 + (P[i + 1].1 - P[i].1) * f) }; d -= seg[i] }
                return P[P.count - 1]
            }
            for k in 0...frames {
                let (cx, cy) = path(k), age = Double(k) / 26
                var o = base(px, cx, cy); o.mood = sp.base; o.stem = k > 13 ? .droop : .curl
                o.rot = sp.key == .apple ? age * 0.85 : age * 0.3; o.spots = sp.key == .banana ? age : 0; o.eyeMode = .side; o.look = 1
                paint(ctx, o)
            }
            text(ctx, "NOT RESPONDING", sx + sw / 2, sy + 18, 2, Int(floor(t * 1.6)) % 2 != 0 ? WHITE : RGBA(hex: 0x9AA1AA), .center)

        case .dizzy:
            let c = fmod(T, 3.4), seed = 11.0
            let scatter = c < 0.45 ? ease(c / 0.45) : c < 1.0 ? 1 - ease((c - 0.45) / 0.55) : 0
            let flip = c >= 0.72 && c < 2.3
            let offset: ((Int, Int) -> (Double, Double))? = scatter > 0 ? { x, y in
                let a = hash(Double(x), Double(y), seed) * Double.pi * 2, r = (2 + hash(Double(y), Double(x), seed) * 5) * scatter
                return (jsRound(cos(a) * r), jsRound(sin(a) * r))
            } : nil
            let look: Double = Int(floor(t * 8)) % 2 != 0 ? 1 : -1
            let eyesMode: EyeMode = c < 1.0 ? .cross : flip ? (c > 1.6 && c < 1.75 ? .closed : .side) : c < 2.9 ? .cross : .side
            if c >= 2.3 && c < 2.42 {
                var o = base(px0); ctx.save(); ctx.translate(0, p.cy); ctx.scale(1, 0.45); ctx.translate(0, -p.cy)
                o.eyeMode = .closed; paint(ctx, o); ctx.restore()
            } else { var o = base(px0); o.flip = flip; o.offset = offset; o.eyeMode = eyesMode; o.look = look; paint(ctx, o) }

        case .compacting:
            // the context is being compacted, so it is: squashed flat under a press, its pixels JPEG'd into blocks
            let c = fmod(T, 2.4), squeeze = 0.56 + 0.05 * sin(c / 2.4 * Double.pi * 2) - min(0.1, T * 0.12)
            let o = base(px0), bottom = o.oy + Hd * px0
            ctx.save(); ctx.translate(p.cx, bottom); ctx.scale(1 + (1 - squeeze) * 0.4, squeeze); ctx.translate(-p.cx, -bottom)
            atRes(ctx, o.ox - px0 * 2, o.oy - px0, (Wd + 4) * px0, (Hd + 1) * px0, px0 * 2) { g in var q = o; q.eyeMode = EyeMode.none; paint(g, q) }
            var e = o; e.eyeMode = .cam; eyes(ctx, e) { Double($0) }
            ctx.restore()
            // the press rests on its head
            let top = bottom - Hd * px0 * squeeze - 3, plateW = sw - 24
            ctx.fill = RGBA(hex: 0x3A3F46); ctx.fillRect(sx + 12, top - 9, plateW, 9)
            ctx.fill = RGBA(hex: 0x5A6069); ctx.fillRect(sx + 12, top - 9, plateW, 2)
            ctx.fill = RGBA(hex: 0x2A2E33); ctx.fillRect(sx + sw / 2 - 3, sy, 6, top - 9 - sy)
            let pct = 40 + Int(floor(T * 9)) % 50
            text(ctx, "-\(pct)%", sx + sw - 16, top - 22, 2, RGBA(hex: 0xFFE66B), .right)

        case .waiting:
            // rate limited: it waits, tapping a foot under an hourglass, and keeps looking up at the clock
            let ph = fmod(T, 4), clock = ph > 1.2 && ph < 2.6
            var o = base(px0); o.legs = Int(floor(T * 2.2)) % 2 != 0 ? .stepR : .stand; o.dy = 0
            o.eyeMode = clock ? .up : blinkAt(t) ? .closed : .squint; o.look = 1
            paint(ctx, o)
            // the hourglass: 5 x 7 pixels, sand running down, turned over every 3 s
            let hp = max(2, jsRound(px0 * 0.55)), hx = o.ox + (Wd + 1) * px0, hy = o.oy + 2 * px0
            let run = fmod(T, 3) / 3, flip = fmod(T, 3) > 2.8
            let GL = ["XXXXX", ".X.X.", "..X..", "..X..", ".X.X.", "X...X", "XXXXX"]
            ctx.save(); if flip { ctx.translate(hx + 2.5 * hp, hy + 3.5 * hp); ctx.rotate(Double.pi / 2); ctx.translate(-(hx + 2.5 * hp), -(hy + 3.5 * hp)) }
            ctx.fill = RGBA(hex: 0xC9CDD2)
            for (j, r) in GL.enumerated() { for (i, ch) in r.enumerated() where ch == "X" { ctx.fillRect(hx + Double(i) * hp, hy + Double(j) * hp, hp, hp) } }
            ctx.fill = RGBA(hex: 0xFFD23F)
            let topN = jsRound((1 - run) * 3), botN = jsRound(run * 3)
            if topN > 0 { ctx.fillRect(hx + hp, hy + hp, 3 * hp, hp * min(1, topN)) }
            if topN > 1 { ctx.fillRect(hx + 2 * hp, hy + 2 * hp, hp, hp) }
            if Int(floor(T * 6)) % 2 != 0 { ctx.fillRect(hx + 2 * hp, hy + 3 * hp, hp, hp) }
            if botN > 0 { ctx.fillRect(hx + hp, hy + 5 * hp, 3 * hp, hp) }
            if botN > 1 { ctx.fillRect(hx + 2 * hp, hy + 4 * hp, hp, hp) }
            ctx.restore()
            let left = max(0, 33 * 60 - 1 - Int(floor(T))), mm = String(format: "%02d", left / 60), ss = String(format: "%02d", left % 60)
            text(ctx, "BACK IN \(mm):\(ss)", sx + sw / 2, o.oy + Hd * px0 + 10, 2, RGBA(hex: 0x9AA1AA), .center)

        case .sleep:
            let px = 4.0, swd = Wd * px, shd = Hd * px, m = 6.0, rx = sw - 2 * m - swd, ry = sh - 2 * m - shd
            let vx = rx / 2.5, vy = ry / 3.75, TT = T + 1.2                       // first corner hit at T = 6.3 s
            func tri(_ d: Double, _ r: Double) -> (Double, Int) { let n = Int(floor(d / r)), f = d - Double(n) * r; return (n % 2 != 0 ? r - f : f, n) }
            let (x, nx) = tri(TT * vx, rx), (y, ny) = tri(TT * vy, ry)
            var corner: [Double] = []; for k in 1..<8 { let tc = 7.5 * Double(k) - 1.2; if T >= tc && T - tc < 1.6 { corner.append(T - tc) } }
            var o = Sprite(sp: sp, ox: jsRound(sx + m + x), oy: jsRound(sy + m + y), px: px, mood: sp.cycle[(nx + ny) % sp.cycle.count])
            o.eyeMode = !corner.isEmpty && corner[0] < 0.9 ? .cam : .closed; o.stem = .droop; o.boost = -0.06
            paint(ctx, o)
            if !corner.isEmpty {                                                       // it hit the corner. Everyone has waited years for this.
                let a = corner[0]
                for i in 0..<26 {
                    let fi = Double(i), ang = hash(fi, 3, 1) * Double.pi * 2, spd = 30 + hash(fi, 9, 2) * 70, r0 = 22.0
                    let gx = o.ox + swd / 2 + cos(ang) * (r0 + spd * a), gy = o.oy + shd / 2 + sin(ang) * (r0 + spd * a) + 40 * a * a
                    ctx.fill = css(grad(LAB[sp.cycle[i % sp.cycle.count].rawValue], 0.3)); ctx.fillRect(jsRound(gx), jsRound(gy), 4, 4)
                }
                text(ctx, "CORNER!", sx + sw / 2, sy + sh / 2 - 6, 3, Int(floor(a * 8)) % 2 != 0 ? WHITE : RGBA(hex: 0xFFE66B), .center)
            } else {
                let zt = fmod(T, 1.4)
                ctx.alpha = 1 - zt / 1.4; text(ctx, "z", o.ox + swd - 2, o.oy - 4 - step(zt / 1.4, 6) * 16, 2, WHITE); ctx.alpha = 1
            }

        case .subagents:
            let n = max(1, min(5, p.subagents ?? 3)), all = n + 1, c = T, o = base(px0)
            if c < 0.5 {
                let jit: Double = Int(floor(c * 24)) % 2 != 0 ? 1 : -1
                var q = o; q.ox = o.ox + (c > 0.2 ? jit : 0); q.eyeMode = c > 0.2 ? .cam : .side; q.look = 1; paint(ctx, q)
            } else {
                let k = ease((c - 0.5) / 0.45), gap = (sw - 16) / Double(all), mpx = max(2, min(4, floor(gap / Double(sp.visW + 1))))
                for i in 0..<all {
                    let fi = Double(i)
                    let qx = o.ox + (Double(i % 2) + 0.5) * Wd * px0 / 2, qy = o.oy + (Double((i / 2) % 2) + 0.5) * Hd * px0 / 2
                    let fx = sx + sw / 2 + (fi - Double(all - 1) / 2) * gap, fy = p.cy + 16
                    let cx = jsRound(qx + (fx - qx) * k), cy = jsRound(qy + (fy - qy) * k)
                    let walk = Int(floor(c * 5 + fi * 0.5)) % 2
                    var q = base(mpx, cx, cy); q.mood = sp.cycle[i % sp.cycle.count]
                    q.legs = k >= 1 ? (walk != 0 ? .stepL : .stepR) : .stand; q.dy = k >= 1 ? Double(walk) : 0
                    q.eyeMode = blinkAt(t, fi) ? .closed : .side; q.look = i == 0 ? 1 : -1
                    paint(ctx, q)
                }
                if k >= 1 { text(ctx, "X\(all)", sx + sw / 2, p.cy - 36, 2, RGBA(hex: 0xFFE66B), .center) }
            }
        }
    }
}

