import SwiftUI
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// Draws one frame of the rig into a Canvas, in the 198 × 242 design space scaled to the screen.
enum Renderer {
    /// Scale and offset that fit the design space into `size`, centered.
    static func fit(_ size: CGSize) -> (s: Double, ox: Double, oy: Double) {
        let s = min(size.width / DESIGN.width, size.height / DESIGN.height)
        return (s, (size.width - DESIGN.width * s) / 2, (size.height - DESIGN.height * s) / 2)
    }

    static func draw(_ r: Rig, _ context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let f = fit(size)
        ctx.translateBy(x: f.ox, y: f.oy); ctx.scaleBy(x: f.s, y: f.s)
        let p = r.pose()
#if os(watchOS)
        r.pixelScale = f.s * WKInterfaceDevice.current().screenScale
#else
        r.pixelScale = f.s * context.environment.displayScale      // the screen's, or a picture's (the widgets)
#endif
        if let st = r.staged { drawStaged(r, st, ctx); return }
        let worldOn = r.worlds.worldOn(r)
        if !r.ao && r.chrome { drawLabel(r, ctx) }
        // shaken, the scene judders (whole pixels); the words and buttons around it stay still
        var scene = ctx
        let q = r.worlds.quake(r); if q != .zero { scene.translateBy(x: q.x, y: q.y) }
        r.worlds.drawBack(r, scene, p)
        Characters.draw(r, p.fade > 0 ? scene.faded(max(0, 1 - p.fade)) : scene, p)
        guard !r.ao else { return }
        r.worlds.drawFront(r, scene, p)
        if !r.character.gridded && !worldOn { Characters.drawProps(r, scene, p) }
        if r.state == .working && !worldOn { Characters.drawTyping(r, scene, pixel: r.character.gridded) }
        if r.state == .subagents && !worldOn { Characters.drawHelpers(r, scene, p) }
        guard r.chrome else { return }
        if r.state == .approval { drawApproval(r, ctx, compact: worldOn) }
        drawCaption(r, ctx, worldOn: worldOn)
        drawTalkBar(r, ctx)
    }

    /// Noodle and Pix fill the screen: they draw first, then what they share the screen with, then the settings dots
    /// and status on top (with a shadow), then captions over a scrim so the text stays readable over them.
    private static func drawStaged(_ r: Rig, _ st: Staged, _ ctx: GraphicsContext) {
        st.draw(r, ctx)
        guard !r.ao else { return }
        st.front(r, ctx)
        guard r.chrome else { return }
        // the settings dots and the status go over everything it draws (its glass rings too), with a shadow
        var shadowed = ctx; shadowed.addFilter(.shadow(color: .black.opacity(0.8), radius: 3)); drawLabel(r, shadowed)
        drawTalkBar(r, ctx)
        if r.state == .approval && !st.ownsApproval { drawApproval(r, ctx, compact: false) }
        guard !r.caption.isEmpty && r.state != .approval && !st.ownsCaption(r) else { return }
        let top = st.captionTop(r)
        let scrim = Gradient(colors: top ? [.black.opacity(0.75), .black.opacity(0)] : [.black.opacity(0), .black.opacity(0.75)])
        let band = top ? CGRect(x: 0, y: 30, width: 198, height: 70) : CGRect(x: 0, y: 160, width: 198, height: 82)
        ctx.fill(Path(band), with: .linearGradient(scrim, startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
        var c = ctx
        if top { c.translateBy(x: 0, y: -142) }
        drawCaption(r, c, worldOn: false)
    }

    /// The agents' faces at the top left, overlapping: the one you talk to in front, the others behind it, smaller and
    /// a little dimmer, an amber ring on any that needs you. Then the status (WORKING, ASKS, TO NOODLE …), up to the clock.
    private static func drawLabel(_ r: Rig, _ ctx: GraphicsContext) {
        let B = SettingsButton.self
        // back to front: the last one behind first, the one you talk to last
        for (i, f) in r.faces.enumerated().reversed() {
            let front = i == 0, R = front ? B.r : B.rBack, cx = B.x + (front ? 0 : B.r - B.rBack + Double(i) * B.step)
            let circle = Path(ellipseIn: CGRect(x: cx - R, y: B.y - R, width: 2 * R, height: 2 * R))
            ctx.fillCircle(cx, B.y, R + 1.6, .black)                       // a ring of the background between faces
            var c = ctx; c.opacity *= front ? 1 : 0.8
            c.fill(circle, with: .color(.black))                              // the avatars are pictures on black
            c.clip(to: circle)
            let full = AgentFace.fullBleed.contains(f.character), pad = full ? 0 : R * 0.22
            c.draw(Image("avatar-\(AgentFace.asset(f.character))").interpolation(full ? .high : .none),
                   in: CGRect(x: cx - R + pad, y: B.y - R + pad, width: 2 * (R - pad), height: 2 * (R - pad)))
            ctx.stroke(circle, with: .color(f.needs ? Pal.amber : .white.opacity(0.16)), lineWidth: f.needs ? 1.6 : 0.5)
        }
        guard !r.label.isEmpty else { return }
        let amber = r.state == .needs || r.state == .approval
        let t = ctx.resolve(Text(r.label).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(amber ? Pal.amber : Pal.gray))
        ctx.draw(t, in: CGRect(x: B.labelX, y: B.y - 6.5, width: 128 - B.labelX, height: 13))
    }

    private static func text(_ ctx: GraphicsContext, _ s: String, _ rect: CGRect, size: Double, weight: Font.Weight = .medium,
                             mono: Bool = false, color: Color, align: Alignment = .center) {
        let t = Text(s).font(.system(size: size, weight: weight, design: mono ? .monospaced : .default)).foregroundColor(color)
        let resolved = ctx.resolve(t)
        let m = resolved.measure(in: CGSize(width: rect.width, height: rect.height))
        let x = align == .leading ? rect.minX : rect.midX - m.width / 2
        ctx.draw(resolved, in: CGRect(x: x, y: rect.minY, width: min(m.width, rect.width), height: rect.height))
    }

    static func drawApproval(_ r: Rig, _ ctx: GraphicsContext, compact: Bool) {
        if compact {
            let y = 190.0
            ctx.fillRoundRect(22, y, 154, 36, 10, Pal.card)
            text(ctx, r.approvalTitle, CGRect(x: 34, y: y + 6, width: 130, height: 16), size: 13, mono: true, color: Pal.white, align: .leading)
            ctx.fillRoundRect(34, y + 25, 130, 3, 1.5, Color(hex: 0x26292D))
            if r.hold > 0 { ctx.fillRoundRect(34, y + 25, 130 * r.hold, 3, 1.5, Pal.amber) }
            return
        }
        let k = clamp(r.stateT / 0.45, 0, 1), y = lerp(250, 118, outC(k))
        ctx.fillRoundRect(14, y, 170, 66, 14, Pal.card)
        text(ctx, r.approvalTitle, CGRect(x: 28, y: y + 12, width: 142, height: 19), size: 15, mono: true, color: Pal.white, align: .leading)
        text(ctx, r.approvalDetail, CGRect(x: 28, y: y + 33, width: 142, height: 15), size: 11.5, weight: .regular, color: Pal.gray, align: .leading)
        guard r.cardControls else { return }
        ctx.fillRoundRect(28, y + 54, 142, 3, 1.5, Color(hex: 0x26292D))
        if r.hold > 0 { ctx.fillRoundRect(28, y + 54, 142 * r.hold, 3, 1.5, Pal.amber) }
        ctx.fillCircle(36, 210, 13, Color(hex: 0x1A1C1F))
        ctx.strokeLine(31.5, 205.5, 40.5, 214.5, Pal.gray, 1.8); ctx.strokeLine(40.5, 205.5, 31.5, 214.5, Pal.gray, 1.8)
        text(ctx, r.hold > 0 ? "keep holding" : "hold to allow", CGRect(x: 56, y: 203, width: 112, height: 15), size: 11, mono: true,
             color: r.hold > 0 ? Pal.amber : Pal.gray)
    }

    /// A caption in its box; when the whole reply doesn't fit, the box keeps its first lines (ending in …) and the
    /// rest is in the conversation card the handle pulls up.
    private static func fitted(_ r: Rig, _ ctx: GraphicsContext, _ s: String, full: String, _ rect: CGRect, size: Double, color: Color) {
        let need = ctx.resolve(Text(full).font(.system(size: size, weight: .medium))).measure(in: CGSize(width: rect.width, height: 2000)).height
        guard need > rect.height + 1 else { text(ctx, s, rect, size: size, color: color); return }
        r.captionLong = true                                      // the rest is in the conversation (the handle at the bottom)
        text(ctx, s, rect, size: size, color: color)
    }

    /// While you talk, centered near the top, clear of your finger: × (slide left onto it and let go: canceled), a live
    /// waveform of your voice, ✓ (slide right onto it, or just let go: sent). Plain colors; the one your finger is heading
    /// to grows, the other fades back.
    static func drawTalkBar(_ r: Rig, _ ctx0: GraphicsContext) {
        guard r.state == .listening else { return }
        var ctx = ctx0; ctx.addFilter(.shadow(color: .black.opacity(0.55), radius: 4))
        let y = 64.0, cancelK = clamp(-r.talkSlide / Rig.armed, 0, 1), sendK = clamp(r.talkSlide / Rig.armed, 0, 1)
        // ×: a gray circle, a white ×
        let rx = 15 + 3 * cancelK
        ctx.faded(1 - 0.5 * sendK).fillCircle(46, y, rx, Color(white: 0.3 + 0.12 * cancelK))
        var x = Path(); let a = 4.6 + 0.9 * cancelK
        x.move(to: CGPoint(x: 46 - a, y: y - a)); x.addLine(to: CGPoint(x: 46 + a, y: y + a))
        x.move(to: CGPoint(x: 46 + a, y: y - a)); x.addLine(to: CGPoint(x: 46 - a, y: y + a))
        ctx.faded(1 - 0.5 * sendK).stroke(x, with: .color(Pal.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        // ✓: a white circle, a black ✓
        let rv = 15 + 3 * sendK
        ctx.faded(1 - 0.5 * cancelK).fillCircle(152, y, rv, Pal.white)
        var v = Path(); let b = 5.2 + 1 * sendK
        v.move(to: CGPoint(x: 152 - b * 1.05, y: y + 0.3)); v.addLine(to: CGPoint(x: 152 - b * 0.3, y: y + b * 0.8)); v.addLine(to: CGPoint(x: 152 + b * 1.1, y: y - b * 0.85))
        ctx.faded(1 - 0.5 * cancelK).stroke(v, with: .color(.black), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        // the waveform: 11 bars, taller in the middle, moving with your voice (and a little even in a pause, so it's
        // plainly listening)
        let n = 11, w = 2.6, gap = 2.5, x0 = 99 - (Double(n) * w + Double(n - 1) * gap) / 2
        var bars = Path()
        for i in 0..<n {
            let c = 1 - abs(Double(i) - Double(n - 1) / 2) / (Double(n) / 2)          // 1 in the middle … ~0 at the ends
            let wob = 0.5 + 0.5 * sin(r.t * (7.3 + Double(i) * 0.9) + Double(i) * 1.7)
            let h = 3 + (0.12 + 0.88 * r.voice) * (6 + 15 * c) * (0.55 + 0.45 * wob)
            let bx = x0 + Double(i) * (w + gap)
            bars.addRoundedRect(in: CGRect(x: bx, y: y - h / 2, width: w, height: h), cornerSize: CGSize(width: w / 2, height: w / 2))
        }
        ctx.faded(1 - 0.35 * max(cancelK, 0)).fill(bars, with: .color(Pal.white))
    }

    static func drawCaption(_ r: Rig, _ ctx: GraphicsContext, worldOn: Bool) {
        let shown: String
        if r.captionShown >= Double(r.caption.count) { shown = r.caption }
        else if r.captionShown <= 0 { shown = "" }
        else { shown = String(r.caption.prefix(Int(r.captionShown))) }
        r.captionLong = false
        switch r.state {
        case .listening:
            break                                                    // no words: the talk bar at the top says it all
        case .speaking, .done:
            guard !shown.isEmpty else { return }
            fitted(r, ctx, shown, full: r.caption, CGRect(x: 18, y: worldOn ? 188 : 176, width: 162, height: worldOn ? 50 : 62), size: 15, color: Pal.white)
        case .needs:
            fitted(r, ctx, r.caption, full: r.caption, CGRect(x: 18, y: 186, width: 162, height: 40), size: 14, color: Pal.white)
        case .blocked:
            text(ctx, r.caption, CGRect(x: 18, y: 182, width: 162, height: 36), size: 14, color: Pal.white)
            if !r.subCaption.isEmpty { text(ctx, r.subCaption, CGRect(x: 18, y: 218, width: 162, height: 16), size: 13, weight: .regular, color: Pal.gray) }
        case .sleep, .idle:
            if !r.caption.isEmpty { text(ctx, r.caption, CGRect(x: 18, y: 192, width: 162, height: 36), size: 13, weight: .regular, color: Pal.gray) }
        case .thinking, .working, .subagents:
            // what you said, in quotes, while Claude works on it (the world's tool-call line steps aside meanwhile)
            if !r.caption.isEmpty { text(ctx, r.caption, CGRect(x: 18, y: worldOn ? 204 : 186, width: 162, height: 36), size: 13, weight: .regular, color: Pal.white) }
        default: break
        }
    }
}

/// The agents' faces at the top left, level with the clock, overlapping: the one you talk to in front, the others
/// behind it (an amber ring on one that needs you). A tap opens the agents and, below them, settings. Drawn with the
/// character (Renderer) and tapped through the character's own touch handling; the tap zone is the whole corner around
/// them, generous for a fingertip (design points).
enum SettingsButton {
    static let x = 20.0, y = 24.0, r = 11.5                      // the front face's center and radius
    static let step = 15.5, rBack = 9.5                           // each face behind: how far right, its radius
    static let labelX = 68.0                                      // the status starts after them
    static func near(_ pt: CGPoint) -> Bool { pt.x < 72 && pt.y < 50 }
}
