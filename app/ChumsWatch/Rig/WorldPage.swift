import SwiftUI

/// Eyes' world: a page of code in the dark. The eyes read it word by word — 160–260 ms fixations, 35 ms jumps,
/// a 90 ms sweep back at each line end. Tool calls happen on the page: an edit rewrites a word in clay,
/// a command adds a › line and its output, a test adds a ✓ line (or a red one if it failed).
final class PageWorld: WorldImpl {
    static let X = 30.0, WIDTH = 138.0, Y = 110.0, LH = 9.0, ROWS = 8
    private let HELP: [(Double, Double)] = [(44, 132), (154, 132), (99, 166)]

    enum LineKind { case code, cmd, out, pass, fail }
    struct Line { var kind: LineKind; var ind: Double; var words: [Double]; var born = 99.0; var edit = -1 }
    struct Event { var kind: ToolCall.Kind; var t = 0.0; var row: Int; var j = -1 }

    var lines: [Line] = []
    var indent = 0
    var row = 1, word = 0, fixT = 0.3
    var top = 0.0, topS = 0.0
    var gx = 0.0, gy = 0.6
    private var from = (0.0, 0.6), to = (0.0, 0.6), sT = 1.0, sDur = 0.04
    var ev: Event?
    var linesRead = 0
    var alpha = 0.0, happyT = 0.0, doneT = -1.0
    var bad = -1
    var helpK = [0.0, 0.0, 0.0]
    var subT = 0.0

    func reset() {
        lines = []; indent = 0; row = 1; word = 0; fixT = 0.3; top = 0; topS = 0; gx = 0; gy = 0.6
        from = (0, 0.6); to = (0, 0.6); sT = 1; sDur = 0.04; ev = nil; linesRead = 0; alpha = 0; happyT = 0; doneT = -1; bad = -1; helpK = [0, 0, 0]
        for _ in 0..<40 { lines.append(makeLine(.code)) }
    }

    private func makeLine(_ kind: LineKind) -> Line {
        if kind == .code {
            let r = Double.random(in: 0..<1)
            indent = min(3, max(0, indent + (r < 0.3 ? 1 : r < 0.58 ? -1 : 0)))
        }
        let ind = kind == .code ? Double(indent) * 8 : 0, maxW = PageWorld.WIDTH - ind - 12
        let n = kind == .pass || kind == .fail ? 1 : kind == .out ? Int.random(in: 1...3) : Int.random(in: 2...5)
        var words: [Double] = [], used = 0.0
        for _ in 0..<n {
            let w = (kind == .pass || kind == .fail) ? 42 : rnd(6, 26)
            if used + w > maxW { break }
            words.append(w); used += w + 4
        }
        if words.isEmpty { words = [12] }
        return Line(kind: kind, ind: ind, words: words)
    }

    private func wordPos(_ r: Int, _ j: Int) -> (x: Double, y: Double) {
        let L = lines[r]
        var x = PageWorld.X + L.ind + (L.kind == .cmd || L.kind == .pass || L.kind == .fail ? 10 : 0)
        for i in 0..<min(j, L.words.count) { x += L.words[i] + 4 }
        return (x + L.words[min(j, L.words.count - 1)] / 2, PageWorld.Y + (Double(r) - topS) * PageWorld.LH)
    }
    private func lookAtWord(_ r: Int, _ j: Int, _ dur: Double) {
        let q = wordPos(r, j)
        from = (gx, gy); to = (clamp((q.x - 99) / 62, -1, 1), clamp(0.4 + (Double(r) - top) / Double(PageWorld.ROWS) * 0.6, 0, 1)); sT = 0; sDur = dur
    }

    private func startEvent(_ rig: Rig) {
        guard let e = rig.worlds.nextEvent(rig) else { return }
        ev = Event(kind: e.kind, row: row); rig.worlds.announce(rig, e.text)
        switch e.kind {
        case .edit:
            let j = min(1, lines[row].words.count - 1)
            lines[row].edit = j; word = j; ev?.j = j; fixT = 1.3
        case .bash, .test, .agent:
            var add = [makeLine(.cmd), makeLine(.out), makeLine(.out)]
            if e.kind == .test { add.append(makeLine(rig.worlds.results[e.id] == false ? .fail : .pass)) } else { add.append(makeLine(.out)) }
            for i in add.indices { add[i].born = -(0.2 + Double(i) * 0.1) }
            lines.insert(contentsOf: add, at: row); word = 0; fixT = 0.4
        default: break
        }
    }

    func onState(_ r: Rig, _ s: ChumsState, _ v: Bool) {
        if s == .subagents { r.W.subCalls = 0 }
        bad = s == .blocked ? row : -1
        doneT = s == .done ? 0 : -1
        if s == .working { fixT = 0.25 }
    }

    func step(_ r: Rig, _ dt: Double) {
        let targets: [ChumsState: Double] = [.working: 1, .done: 1, .blocked: 0.9, .idle: 0.45, .thinking: 0.3, .subagents: 0.16, .approval: 0.2]
        alpha += ((targets[r.state] ?? 0) - alpha) * min(1, dt * 4)
        topS += (top - topS) * min(1, dt * 6)
        sT += dt
        let e = minJerk(clamp(sT / sDur, 0, 1)); gx = lerp(from.0, to.0, e); gy = lerp(from.1, to.1, e)
        happyT = max(0, happyT - dt); if doneT >= 0 { doneT += dt }
        for i in lines.indices { lines[i].born += dt }
        if ev != nil { ev!.t += dt }
        for i in 0..<3 { helpK[i] = clamp(helpK[i] + dt * 3 * (r.state == .subagents && r.stateT > 0.3 + Double(i) * 0.3 ? 1 : -1), 0, 1) }
        if r.state == .subagents && helpK[0] >= 1 {
            subT -= dt
            if subT <= 0 { subT = rnd(0.5, 1); r.W.subCalls += 1; r.worlds.announce(r, "3 subagents: \(r.W.subCalls) tool calls") }
        }
        if r.W.launch?.world == true || r.state != .working { return }
        fixT -= dt
        if fixT > 0 { return }
        word += 1
        if word >= lines[row].words.count {
            row += 1; word = 0; linesRead += 1
            while lines.count < row + 14 { lines.append(makeLine(.code)) }
            if lines.count > 120 { let cut = lines.count - 120; lines.removeFirst(cut); row -= cut; top -= Double(cut); topS -= Double(cut); if bad >= 0 { bad -= cut } }
            if Double(row) - top > 3 { top = Double(row) - 3 }
            if lines[row].kind == .pass { happyT = 0.8; r.onHaptic?(.click) }
            fixT = 0.3
            if linesRead % 2 == 0 && (ev == nil || ev!.t > 1.4) { startEvent(r) }
            lookAtWord(row, word, 0.09)                                   // the sweep back to the next line
        } else { lookAtWord(row, word, 0.035); fixT = rnd(0.16, 0.26) }
    }

    func pose(_ r: Rig, _ p: Pose) -> WorldPose {
        let par = sin(r.worlds.watchRot(r)) * 2, dyc = (r.clip?.frame().dy ?? 0) * 0.6
        var w = WorldPose(cx: 99 + par, cy: (r.state == .subagents ? 58 : 66) - dyc, scale: r.state == .subagents ? 0.6 : 0.72)
        w.o.tilt = 0
        if let L = r.W.launch, L.world {
            w.o.open = L.t < 0.4 ? 0 : L.t < 0.55 ? (L.t - 0.4) / 0.15 : (L.t > 0.9 && L.t < 1.02 ? 0 : 1)
            w.o.gx = 0; w.o.gy = L.t > 1.1 ? 0.6 : 0
            return w
        }
        switch r.state {
        case .working:
            w.o.gx = gx; w.o.gy = gy; w.o.intent = (ev?.kind == .edit && ev!.t < 1.3) ? 0.8 : 0.3
            if happyT > 0 { w.o.happy = 1 }
        case .thinking:
            w.o.gx = 0.5 + 0.18 * sin(p.t * 0.8); w.o.gy = -0.35 + 0.08 * sin(p.t * 1.3); w.o.sleepy = 0.3
        case .subagents:
            let hx = [-1.0, 0, 1, 0][Int(r.stateT / 1.3) % 4]; w.o.gx = hx * 0.75; w.o.gy = hx == 0 ? 1 : 0.75
        case .blocked:
            let q = bad >= 0 && bad < lines.count ? wordPos(bad, 0) : (x: 99.0, y: 0.0)
            w.o.gx = clamp((q.x + 30 - 99) / 62, -1, 1); w.o.gy = 0.75
        case .approval:
            w.o.gx = 0; w.o.gy = Int(r.stateT / 1.4) % 2 == 1 ? 0 : 1
        default: break
        }
        return w
    }

    func back(_ r: Rig, _ ctx: GraphicsContext, _ p: Pose) {
        let launchT = r.W.launch?.world == true ? r.W.launch!.t : nil
        let px = -sin(r.worlds.watchRot(r)) * 6, off = r.W.scrub / 34
        let r0 = Int((topS + off).rounded(.down)) - 1
        for rr in max(0, r0)..<min(lines.count, r0 + PageWorld.ROWS + 3) {
            let L = lines[rr]
            guard L.born >= 0 else { continue }
            let y = PageWorld.Y + (Double(rr) - topS - off) * PageWorld.LH
            let edge = clamp(min(y - (PageWorld.Y - 12), PageWorld.Y + Double(PageWorld.ROWS) * PageWorld.LH - y) / 12, 0, 1)
            guard edge > 0 else { continue }
            var a = alpha * edge * clamp(L.born / 0.12, 0, 1)
            if let lt = launchT { a = edge * clamp((lt - 0.6 - Double(rr - r0) * 0.06) / 0.15, 0, 1) * 0.8 }
            guard a > 0.01 else { continue }
            let c = ctx.faded(a)
            let cur = rr == row && r.state == .working, read = rr < row
            var flash = 0.0
            if doneT >= 0 { let d = doneT * 12 - Double(rr - r0); flash = d > 0 && d < 2 ? 1 - abs(d - 1) : 0 }
            var x = PageWorld.X + L.ind + px
            if cur { c.fillRect(PageWorld.X - 9 + px, y - 3, 1.6, 6, Pal.gray) }
            if L.kind == .cmd {
                var ch = Path(); ch.move(to: CGPoint(x: x + 1, y: y - 2.5)); ch.addLine(to: CGPoint(x: x + 4, y: y)); ch.addLine(to: CGPoint(x: x + 1, y: y + 2.5))
                c.stroke(ch, with: .color(Color(hex: 0xA9AEB4)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)); x += 10
            }
            if L.kind == .pass || L.kind == .fail {
                if L.kind == .pass {
                    var ck = Path(); ck.move(to: CGPoint(x: x, y: y)); ck.addLine(to: CGPoint(x: x + 2, y: y + 2)); ck.addLine(to: CGPoint(x: x + 6, y: y - 2.5))
                    c.stroke(ck, with: .color(Pal.green), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                } else { c.strokeLine(x, y - 2.5, x + 5, y + 2.5, Pal.red, 1.5); c.strokeLine(x + 5, y - 2.5, x, y + 2.5, Pal.red, 1.5) }
                x += 10
            }
            let et = (ev?.kind == .edit && ev?.row == rr) ? ev!.t : 9
            for (j, w0) in L.words.enumerated() {
                var ww = w0
                var col: Color = read ? Color(hex: 0x43464B) : Color(hex: 0x303337)
                if cur { col = j < word ? Color(hex: 0x7A7F85) : j == word ? Color(hex: 0xEDEFF1) : Pal.dim }
                switch L.kind { case .cmd: col = Color(hex: 0xA9AEB4); case .out: col = Color(hex: 0x3A3D41); case .pass: col = Pal.green; case .fail: col = Pal.red; case .code: break }
                if L.edit == j {
                    if et < 0.22 { ww = w0 * (1 - et / 0.22) }
                    else if et < 1.3 { ww = w0 * min(1, (et - 0.22) / 0.6); col = Pal.clay }
                    else { col = Color(hex: 0x7B4A3A) }
                }
                if rr == bad { col = Pal.red }
                if flash > 0.3 && L.kind != .pass { col = Pal.gray }
                if ww > 0.5 { c.fillRoundRect(x, y - 1.6, ww, 3.2, 1.6, col) }
                if L.edit == j && et >= 0.22 && et < 1.3 && Int(r.t * 4) % 2 == 0 { c.fillRect(x + ww + 1.2, y - 3.6, 1.4, 7.2, Pal.white) }
                x += w0 + 4
            }
            if rr == bad {
                var sq = Path(), sx = PageWorld.X + L.ind + px
                for k in 0...40 { let pt = CGPoint(x: sx, y: y + 4.2 + (k % 2 == 1 ? 1.2 : -0.2)); if k == 0 { sq.move(to: pt) } else { sq.addLine(to: pt) }; sx += 2.2 }
                c.stroke(sq, with: .color(Pal.red), lineWidth: 1)
            }
        }
        // subagents: three more pairs of eyes open in the dark, each reading a few lines of its own
        for (i, (hx, hy)) in HELP.enumerated() where helpK[i] > 0.02 {
            let k = helpK[i]
            let sw = (r.t * 0.8 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let hgx = sw < 0.85 ? lerp(-0.8, 0.8, (sw / 0.85 * 5).rounded(.down) / 4) : 0.8 - 1.6 * (sw - 0.85) / 0.15
            let bl = (r.t * 0.5 + Double(i) * 0.31).truncatingRemainder(dividingBy: 3.1) < 0.09 ? 0.05 : 1
            let lc = ctx.faded(min(1, k * 2))
            for l in 0..<3 { lc.fillRoundRect(hx - 16, hy + 15 + Double(l) * 5, [30.0, 21, 26][l] * k, 2, 1, Color(hex: 0x303337)) }
            var m = p
            m.cx = hx + px * 0.5; m.cy = hy; m.scale = 0.3; m.sy = 1; m.tilt = 0; m.amber = 0; m.pulse = 0; m.tint = Pal.gray
            m.eye = .neutral(gx: hgx, gy: 0.8); m.eye.open = min(1, k * 1.3) * bl
            Characters.drawEyes(r, ctx, m)
        }
    }

    func front(_ r: Rig, _ ctx: GraphicsContext, _ p: Pose) {
        guard r.state == .blocked else { return }
        ctx.fill(Characters.dropPath(x: p.cx + 34, y: p.cy - 14, s: 0.8), with: .color(Pal.sweat))
    }

    func scrubLabel(_ r: Rig) -> String? {
        let n = Int((-r.W.scrub / 34).rounded()), h = r.W.history
        return h.count > n ? h[h.count - 1 - n] : nil
    }
}
