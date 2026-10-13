import Foundation
import CoreGraphics
import ImageIO

// Renders the Pix port (app/ChumsWatch/Rig/Pix.swift) on the Mac: the same 104 frames as design/pix/reference, at 3×
// (594 × 726) on black, so tools/pix-compare.py can diff them pixel for pixel. Also times a frame at the watch's scale.
//
//   tools/pix-compare.sh                       # build, render, compare (writes app/build/pix-compare)
//   pix-render OUTDIR                          # the 104 frames
//   pix-render OUTDIR --time                   # plus per-state render times
//   pix-render OUTDIR --float-bilinear --high-linear   # resampling variants (see Pix.lowpBilinear / Pix.highIsCubic)

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("usage: pix-render OUTDIR [--time] [--float-bilinear] [--high-linear]"); exit(2) }
        let out = URL(fileURLWithPath: args[1])
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        func mode(_ v: String?) -> Pix.Bilinear? { v == "lowp" ? .lowp : v == "hw8" ? .hw8 : v == "float" ? .float : nil }
        if let m = mode(env["PIX_HALVE"]) { Pix.halveMode = m }
        if let m = mode(env["PIX_LAST"]) { Pix.lastMode = m }
        if let v = env["PIX_HALVE_TIES"] { Pix.halveTiesUp = v == "up" }
        if let v = env["PIX_LAST_TIES"] { Pix.lastTiesUp = v == "up" }
        if let v = env["PIX_UNPREMUL_TIES"] { Pix.unpremulTiesUp = v == "up" }
        if let b = env["PIX_SUBTEXEL"], let n = Int(b) { Pix.subtexelBits = n }
        if env["PIX_HIGH"] == "cubic" { Pix.highIsCubic = true }
        if env["PIX_HIGH"] == "linear" { Pix.highIsMip = false }
        if let v = env["PIX_MIPBIAS"], let d = Double(v) { Pix.mipBias = d }
        if env["PIX_MIPAXIS"] == "max" { Pix.mipAxisMax = true }

        let stateTs: [(Double, String)] = [(0.3, "0_3"), (1, "1"), (2, "2"), (3.2, "3_2")]
        var cases: [(String, Pix.Params)] = []
        for species in Pix.Species.allCases {
            for st in Pix.State.allCases {
                for (T, name) in stateTs {
                    var p = Pix.Params()
                    p.species = species; p.state = st; p.stateT = T; p.t = 10 + T
                    p.cx = 99; p.cy = st == .needs ? 146 : st == .working ? 134 : 118; p.px = 7
                    p.voice = 0.6
                    p.text = "ALL 14 TESTS PASS. I ALSO FIXED A TYPO."
                    p.tools = ["READ", "EDIT", "BASH"]
                    p.subagents = 3
                    p.screen = CGRect(x: 0, y: 36, width: 198, height: 206)
                    p.room = 150
                    cases.append(("pix-\(species.rawValue)-\(st.rawValue)-\(name)", p))
                }
            }
        }

        let r = Pix.Raster(w: 594, h: 726)
        let dump = env["PIX_DUMP"]          // a directory: every atRes stage of every frame goes there as <frame>-<stage>.png
        for (name, p) in cases {
            r.fill(Pix.RGBA(0, 0, 0))
            if let dump {
                try? FileManager.default.createDirectory(atPath: dump, withIntermediateDirectories: true)
                Pix.debugHook = { stage, ras in writePNG(ras, URL(fileURLWithPath: dump).appendingPathComponent("\(name)-\(stage).png")) }
            }
            Pix.draw(r, transform: Pix.Matrix(a: 3, b: 0, c: 0, d: 3, e: 0, f: 0), p)
            Pix.debugHook = nil
            writePNG(r, out.appendingPathComponent(name + ".png"))
        }
        print("rendered \(cases.count) frames to \(out.path)")

        if args.contains("--time") {
            // the 45 mm watch: 198 × 242 pt at 2× = 396 × 484 px
            let w = Pix.Raster(w: 396, h: 484)
            let m = Pix.Matrix(a: 2, b: 0, c: 0, d: 2, e: 0, f: 0)
            print("\nrender time per frame at 396 × 484 (the watch's pixels), mean of 40 after warm-up:")
            var worst = ("", 0.0), total = 0.0, n = 0
            for species in Pix.Species.allCases {
                print("  \(species.rawValue):")
                for st in Pix.State.allCases {
                    var ms: [Double] = []
                    for (T, _) in stateTs {
                        let p = cases.first { $0.0 == "pix-\(species.rawValue)-\(st.rawValue)-\(T == 1 ? "1" : T == 2 ? "2" : T == 0.3 ? "0_3" : "3_2")" }!.1
                        for _ in 0..<3 { w.fill(Pix.RGBA(0, 0, 0)); Pix.draw(w, transform: m, p) }
                        let t0 = Date()
                        for _ in 0..<40 { w.fill(Pix.RGBA(0, 0, 0)); Pix.draw(w, transform: m, p) }
                        let dt = Date().timeIntervalSince(t0) / 40 * 1000
                        ms.append(dt); total += dt; n += 1
                        if dt > worst.1 { worst = ("\(species.rawValue) \(st.rawValue) T=\(T)", dt) }
                    }
                    print(String(format: "    %-11@ %@ ms", st.rawValue as NSString, ms.map { String(format: "%.2f", $0) }.joined(separator: " / ") as NSString))
                }
            }
            print(String(format: "  mean %.2f ms, worst %.2f ms (%@)", total / Double(n), worst.1, worst.0 as NSString))
        }
    }

    static func writePNG(_ r: Pix.Raster, _ url: URL) {
        guard let img = r.image(), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { print("cannot write \(url.path)"); return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
