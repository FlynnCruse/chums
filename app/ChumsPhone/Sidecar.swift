import SwiftUI

/// Every agent, in a panel that slides in from the left over the screen: its face (ringed when it's doing something:
/// white working, amber needs you, red stuck), its name, and the last thing said in its conversation. A tap talks to
/// it; … opens its card. Press and hold one: it lifts under your finger, the others make room, and it settles where
/// you let go.
struct Sidecar: View {
    let agents: [AgentInfo]
    let active: String
    let connected: Bool
    let last: [String: String]                       // each agent's last line in its conversation
    let pick: (String) -> Void
    let settings: (AgentInfo) -> Void
    let reorder: ([String]) -> Void
    @State private var lifted: String?               // the agent under your finger
    @State private var from = 0                      // where it was picked up
    @State private var target = 0                    // where it would land
    @State private var dragY = 0.0
    @State private var local: [String]?              // the order just dropped, until the saved one comes back
    @GestureState private var touching = false       // a finger is on a row's press (ends however the gesture ends)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let rowH = 68.0

    /// The rows, in the order on screen: the one just dropped, else the saved one.
    private var rows: [AgentInfo] {
        guard let local else { return agents }
        return local.compactMap { id in agents.first { $0.id == id } } + agents.filter { !local.contains($0.id) }
    }

    /// The agents in a few words: those that need you, else those working, stuck or rate limited, else how many are
    /// idle and how many aren't running.
    private var summary: String {
        if !connected { return "Can't reach your Mac" }
        let needs = agents.filter(\.needs).count
        func count(_ s: String...) -> Int { agents.filter { s.contains($0.status) }.count }
        let working = count("working", "compacting"), stuck = count("blocked"), limited = count("limited"), off = count("offline")
        if needs > 0 { return needs == 1 ? "1 needs you" : "\(needs) need you" }
        if working > 0 { return "\(working) working" }
        if stuck > 0 { return "\(stuck) stuck" }
        if limited > 0 { return "\(limited) rate limited" }
        if off == 0 { return "All idle" }
        if off == agents.count { return "None running on your Mac" }
        return "\(agents.count - off) idle, \(off) not running"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Agents").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Text(summary).font(.subheadline.weight(.medium))
                    .foregroundStyle(!connected || agents.contains(where: \.needs) ? Pal.amber : Ink.quiet)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in row(a, at: i) }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(lifted != nil)

            HStack(spacing: 8) {
                Circle().fill(connected ? Color.white : Pal.amber).frame(width: 7, height: 7)
                Text(connected ? "Connected to your Mac" : "Can't reach your Mac")
                    .font(.footnote).foregroundStyle(Ink.quiet)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(bottomTrailingRadius: 34, topTrailingRadius: 34, style: .continuous)
                .fill(Ink.panel)
                .overlay(UnevenRoundedRectangle(bottomTrailingRadius: 34, topTrailingRadius: 34, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .ignoresSafeArea()
        }
        .animation(.snappy, value: summary)
        .onChange(of: agents.map(\.id)) { _, ids in if ids == local { local = nil } }      // the saved order caught up
        // the press ended without a drop (let go without dragging, or the system took the touch): it settles anyway
        .onChange(of: touching) { _, on in if !on && lifted != nil { drop() } }
    }

    private func row(_ a: AgentInfo, at i: Int) -> some View {
        let up = lifted == a.id
        return AgentRow(agent: a, on: a.id == active, lifted: up, line: last[a.id]) { settings(a) }
            .frame(height: Self.rowH)
            .scaleEffect(up && !reduceMotion ? 1.035 : 1)                          // Reduce Motion: lifted by its shadow only
            .shadow(color: .black.opacity(up ? 0.55 : 0), radius: 20, y: 10)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)                     // the rows' height is fixed
            .offset(y: offset(a.id, i))
            .zIndex(up ? 2 : 0)
            .contentShape(Rectangle())
            .onTapGesture { pick(a.id) }
            .gesture(
                LongPressGesture(minimumDuration: 0.32)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { v in
                        switch v {
                        case .first(true):
                            if lifted == nil { lift(a.id, i) }
                        case .second(true, let d):
                            if lifted == nil { lift(a.id, i) }
                            guard let d else { return }
                            dragY = d.translation.height                                  // under the finger, no easing
                            let t = min(rows.count - 1, max(0, from + Int((dragY / Self.rowH).rounded())))
                            if t != target { withAnimation(Move.snap) { target = t }; Haptics.play(.click) }
                        default: break
                        }
                    }
                    .onEnded { _ in drop() }
            )
            .accessibilityAction(named: "Move up") { move(i, to: i - 1) }
            .accessibilityAction(named: "Move down") { move(i, to: i + 1) }
            .accessibilityValue(up ? "Lifted" : "")
    }

    private func lift(_ id: String, _ i: Int) {
        from = i; target = i; dragY = 0
        withAnimation(Move.or(Move.lift, reduced: reduceMotion)) { lifted = id }
        Haptics.play(.start)
    }

    /// While one is carried: it sits under the finger; the ones it has passed sit a row toward where it came from.
    private func offset(_ id: String, _ i: Int) -> CGFloat {
        guard let l = lifted else { return 0 }
        if id == l { return dragY }
        if from < target && i > from && i <= target { return -Self.rowH }
        if from > target && i >= target && i < from { return Self.rowH }
        return 0
    }

    /// Let go: in one movement the order changes and every row settles into its place (the carried one from under the
    /// finger to its new place; the others are already there).
    private func drop() {
        guard lifted != nil else { return }
        var ids = rows.map(\.id)
        if target != from { ids.insert(ids.remove(at: from), at: target) }
        withAnimation(Move.settle) {
            local = ids
            lifted = nil; dragY = 0
        }
        if target != from { reorder(ids) }
        Haptics.play(.settle)                                                   // set down: firmer than a row passing
    }

    private func move(_ i: Int, to: Int) {
        guard to >= 0, to < rows.count, i != to else { return }
        var ids = rows.map(\.id)
        ids.insert(ids.remove(at: i), at: to)
        withAnimation(Move.settle) { local = ids }
        reorder(ids)
    }
}

/// One agent in the panel: its face (ringed when it's doing something), its name, the last thing said, and … for its
/// card.
struct AgentRow: View {
    let agent: AgentInfo
    let on: Bool
    var lifted = false
    var line: String? = nil
    let settings: () -> Void

    /// What it's doing, when it's doing something (idle says nothing: its last words say more).
    private var busy: (Color, String)? {
        if agent.needs { return (Pal.amber, "Needs you") }
        switch agent.status {
        case "working", "compacting": return (.white, "Working")
        case "blocked": return (Pal.red, "Stuck")
        case "limited": return (Pal.amber, "Rate limited")
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            AgentFace(character: agent.character, size: 44)
                .opacity(agent.status == "offline" ? 0.45 : 1)
                .padding(3)
                .overlay { if let b = busy { Circle().strokeBorder(b.0, lineWidth: 2) } }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name).font(.body.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    if agent.runtime == "codex" {
                        Text("Codex").font(.caption2.weight(.semibold)).foregroundStyle(Color(white: 0.75))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(white: 0.2), in: Capsule())
                    }
                }
                Group {
                    if let b = busy { Text(b.1).foregroundStyle(b.0 == .white ? Color(white: 0.85) : b.0) }
                    else if agent.status == "offline" { Text("Not running on your Mac").foregroundStyle(Ink.ghost) }
                    else { Text(line ?? agent.line ?? "Nothing said yet").foregroundStyle(Ink.quiet) }
                }
                .font(.footnote).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: settings) {
                Image(systemName: "ellipsis").font(.body.weight(.bold)).foregroundStyle(Color(white: 0.55))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("\(agent.name)'s settings")
            .accessibilityIdentifier("settings-\(agent.id)")
        }
        .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 6)
        .background(Color(white: lifted ? 0.17 : on ? 0.13 : 0.065).opacity(on || lifted ? 1 : 0),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(agent.name)
        .accessibilityIdentifier("agent-\(agent.id)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// The agents button at the top left, as on the watch: the others' faces stacked, the most urgent in front and bigger,
/// two behind it smaller and dimmer (an amber ring on any that needs you). Just the faces, no plate behind them. A tap
/// opens the agents.
struct AgentsButton: View {
    let others: [AgentInfo]
    let action: () -> Void

    var body: some View {
        let shown = Array(others.prefix(3))
        Button(action: action) {
            ZStack(alignment: .leading) {
                ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { i, a in
                    let front = i == 0
                    AgentFace(character: a.character, size: front ? 32 : 26)
                        .padding(2).background(Circle().fill(a.needs ? Pal.amber : .black))
                        .opacity(front ? 1 : 0.75)
                        .offset(x: front ? 0 : 24 + CGFloat(i - 1) * 15)
                }
            }
            .frame(width: 36 + CGFloat(max(0, shown.count - 1)) * 15 + (shown.count > 1 ? 9 : 0), height: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("Agents")
        .accessibilityValue({ let n = others.filter(\.needs).count; return n == 0 ? "" : n == 1 ? "1 needs you" : "\(n) need you" }())
    }
}

/// Three dots, on their own (no plate): a corner's way into settings.
struct DotsButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(label)
    }
}
