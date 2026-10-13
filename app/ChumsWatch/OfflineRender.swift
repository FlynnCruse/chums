#if targetEnvironment(simulator)
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Simulator only: renders the character offline, in simulated time, frame by frame at any resolution, to PNG files
/// in the app's Documents/render/<name>, for a recording script to turn into a sheet or a video.
/// Launched with -render <base64 JSON>:
///   name, character, mode (portrait|world), scale (pixels per point, default 6), fps (default 60), clock ("10:09"),
///   ao (true: the dimmed, always-on look)
///   sheet: ["idle", "done@0.4", …]  one still per state (after its time in that state, default `settle` 1.6 s)
///   or duration + events: a timeline; every frame is written
///     {"t": 0, "state": "working"}  {"t": 1, "tap": [x, y]}  {"t": 2, "drag": [[x, y], …], "over": 1.2}
///     {"t": 3, "crown": 12, "over": 0.8}  {"t": 5, "shake": 2.5, "over": 1}  {"t": 6, "voice": 0.7}  {"t": 7, "voice": null}
///     {"t": 7, "tool": "read Read cart.ts"}  {"t": 8, "caption": "…"}  {"t": 8, "label": "WORKING"}
@MainActor
enum OfflineRender {
    struct Event: Decodable {
        var t: Double
        var state: String?, variant: Bool?
        var tap: [Double]?, drag: [[Double]]?, over: Double?
        var crown: Double?, shake: Double?
        var voice: Double??, tool: String?, caption: String?, label: String?
    }
    struct Spec: Decodable {
        var name: String, character: String
        var mode: String?, scale: Double?, fps: Double?, clock: String?
        var sheet: [String]?, settle: Double?
        var duration: Double?, events: [Event]?
        var faces: [String]?
        var ao: Bool?                                 // the dimmed (always on) look
    }

    static func run(_ base64: String) async {
        guard let data = Data(base64Encoded: base64), let spec = try? JSONDecoder().decode(Spec.self, from: data) else {
            print("render: bad spec"); return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("render/\(spec.name)")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        StretchFrames.shared.waits = true                // every one of Stretch's frames in the pictures
        let rig = Rig()
        rig.ao = spec.ao ?? false
        rig.character = CharacterKind(id: spec.character) ?? .fallback
        rig.mode = StageMode(rawValue: spec.mode ?? "portrait") ?? .portrait
        rig.faces = (spec.faces ?? [spec.character]).map { ($0, false) }
        rig.approvalTitle = "git push origin main"; rig.approvalDetail = "Push the fix to GitHub"
        let fps = spec.fps ?? 60, dt = 1 / fps, scale = spec.scale ?? 6
        var index = 0
        func shoot(_ file: String) {
            let view = Canvas { ctx, size in
                Renderer.draw(rig, ctx, size: size)
                if let clock = spec.clock {
                    ctx.draw(Text(clock).font(.system(size: 17, weight: .semibold)).foregroundColor(.white),
                             at: CGPoint(x: size.width - 14, y: 21), anchor: .trailing)
                }
            }
            .frame(width: DESIGN.width, height: DESIGN.height)
            let r = ImageRenderer(content: view); r.scale = scale
            guard let img = r.cgImage,
                  let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(file) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
        }
        func advance(_ seconds: Double) { var s = 0.0; while s < seconds - 1e-9 { rig.tick(dt); s += dt } }

        if let sheet = spec.sheet {
            for (i, item) in sheet.enumerated() {
                let parts = item.split(separator: "@"), name = String(parts[0])
                let hold = parts.count > 1 ? Double(parts[1]) ?? 1.6 : spec.settle ?? 1.6
                guard let s = ChumsState(rawValue: name) else { continue }
                rig.restState = s; rig.label = s == .idle || s == .sleep ? "" : name.uppercased()
                rig.voiceInput = s == .listening ? 0.6 : nil
                rig.setState(s)
                advance(hold)
                shoot(String(format: "%02d-%@.png", i, name))
            }
        } else if let duration = spec.duration {
            let events = (spec.events ?? []).sorted { $0.t < $1.t }
            var next = 0
            var drags: [(Event, Double)] = [], crowns: [(Event, Double)] = [], shakes: [(Event, Double)] = []
            var lastDrag: CGPoint?, tapUp: Double?
            var t = 0.0
            while t < duration {
                while next < events.count && events[next].t <= t + 1e-9 {
                    let e = events[next]; next += 1
                    if let s = e.state.flatMap({ ChumsState(rawValue: $0) }) {
                        rig.restState = s; rig.setState(s, variant: e.variant ?? false)
                        rig.voiceInput = s == .listening ? 0.6 : nil                 // as the app does: your voice only while it listens
                    }
                    if let v = e.voice { rig.voiceInput = v }
                    if let c = e.caption { rig.caption = c }
                    if let l = e.label { rig.label = l }
                    if let tool = e.tool {
                        let w = tool.split(separator: " ", maxSplits: 1)
                        rig.push(ToolCall(id: UUID().uuidString, kind: ToolCall.Kind(rawValue: String(w[0])) ?? .bash, text: w.count > 1 ? String(w[1]) : tool))
                    }
                    if let p = e.tap {
                        let pt = CGPoint(x: p[0], y: p[1])
                        _ = rig.touchDown(pt); rig.staged?.touched(rig, at: pt)
                        if rig.worlds.onCharacter(rig, pt) { rig.poke() }
                        tapUp = t + 0.12
                    }
                    if e.drag != nil { drags.append((e, e.t)) }
                    if e.crown != nil { crowns.append((e, e.t)) }
                    if e.shake != nil { shakes.append((e, e.t)) }
                }
                if let u = tapUp, t >= u { rig.touchUp(); rig.staged?.released(rig); tapUp = nil }
                // drags: along their points, eased; the finger comes down at the first and lifts at the last
                for (i, (e, t0)) in drags.enumerated().reversed() {
                    let pts = e.drag!.map { CGPoint(x: $0[0], y: $0[1]) }, over = e.over ?? 1
                    let u = clamp((t - t0) / over, 0, 1), k = u * u * (3 - 2 * u), f = k * Double(pts.count - 1)
                    let j = min(pts.count - 2, Int(f)), w = f - Double(j)
                    let p = pts.count > 1 ? CGPoint(x: pts[j].x + (pts[j + 1].x - pts[j].x) * w, y: pts[j].y + (pts[j + 1].y - pts[j].y) * w) : pts[0]
                    if lastDrag == nil { _ = rig.touchDown(p); rig.staged?.touched(rig, at: p) }
                    else { rig.touchMoved(p); rig.staged?.dragged(rig, at: p) }
                    lastDrag = p
                    if u >= 1 { rig.touchUp(); rig.staged?.released(rig); lastDrag = nil; drags.remove(at: i) }
                }
                for (i, (e, t0)) in crowns.enumerated().reversed() {
                    let over = e.over ?? 1
                    rig.crown(e.crown! * dt / over)
                    if t - t0 >= over { crowns.remove(at: i) }
                }
                for (i, (e, t0)) in shakes.enumerated().reversed() {
                    let g = e.shake!, s = t - t0
                    rig.motion(g * sin(s * TAU * 4.5), g * 0.8 * sin(s * TAU * 3.7 + 1), g * 0.7 * sin(s * TAU * 5.3 + 2))
                    if s >= (e.over ?? 1) { rig.motion(0, 0, 0); shakes.remove(at: i) }
                }
                rig.tick(dt)
                shoot(String(format: "f%05d.png", index)); index += 1
                t += dt
            }
        }
        try? Data("done".utf8).write(to: dir.appendingPathComponent("DONE"))
        print("render: \(spec.name) done")
    }
}
#endif
