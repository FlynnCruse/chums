import SwiftUI

/// The agents: every character is its own agent on the Mac (Claude Code or Codex), with its own soul, thread and
/// conversation. The one on screen is the one you talk to; the others keep working and come to you when they're done
/// or need you.
enum Agents {
    /// Lines from before there were agents were the first agent's.
    static let fallback = "noodle"
    /// Until the hub has said who's there: one per character.
    static let known = SoulView.looks.map { AgentInfo(id: $0, name: CharacterKind(id: $0)?.name ?? $0, character: $0, status: "offline", line: nil, needs: false) }

    /// What it's doing, in a few words, for its row and its pill.
    static func status(_ a: AgentInfo) -> String {
        switch a.status {
        case "offline": return "Not running on your Mac"
        case "working": return "Working"
        case "compacting": return "Tidying its memory"
        case "limited": return "Rate limited, resumes by itself"
        case "blocked": return a.line.map { "Stuck: \($0)" } ?? "Stuck"
        default: return a.needs ? (a.line.map { "Needs you: \($0)" } ?? "Needs you") : (a.line ?? "Idle")
        }
    }
    /// Its color dot: amber needs you, white working, gray idle, dim not running, red stuck.
    static func dot(_ a: AgentInfo) -> Color {
        if a.needs { return Pal.amber }
        switch a.status {
        case "working", "compacting": return Pal.white
        case "blocked": return Pal.red
        case "offline": return Pal.dim
        default: return Pal.gray
        }
    }
}

/// Who you talk to, then the settings. Opened from the faces at the top left. A tap on an agent talks to it; swiping
/// its row left (Edit) opens its soul.
struct AgentsView: View {
    let agents: [AgentInfo]
    @Binding var active: String
    let settings: AnyView
    let soul: (AgentInfo) -> AnyView
    @Environment(\.dismiss) private var dismiss
    /// The order you put them in (press and hold one, then drag it up or down), kept.
    @AppStorage("characterOrder") private var orderRaw = ""
    private var order: [String] {
        let saved = orderRaw.split(separator: ",").map(String.init).filter { SoulView.looks.contains($0) }
        return saved + SoulView.looks.filter { !saved.contains($0) }
    }
    @State private var path: [String] = (UserDefaults.standard.string(forKey: "openSoul")).map { [$0] } ?? []   // -openSoul <id>

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                // every character is its own agent: a tap talks to it, swiping its row left (Edit) opens its soul
                Section {
                    ForEach(order, id: \.self) { c in
                        if let a = agents.first(where: { $0.id == c }) {
                            row(c, a).contentShape(Rectangle()).onTapGesture { active = a.id; Haptics.play(.click); dismiss() }
                                .swipeActions(edge: .trailing) {
                                    Button { path.append(a.id) } label: { Label("Edit", systemImage: "pencil") }.tint(Color(white: 0.3))
                                }
                                .id(a.id)
                        } else {
                            row(c, nil).id(c)                       // a hub from before every character had an agent
                        }
                    }
                    .onMove { from, to in
                        var o = order; o.move(fromOffsets: from, toOffset: to)
                        orderRaw = o.joined(separator: ","); Haptics.play(.click)
                    }
                } header: { Text("Characters") }
                Section {
                    NavigationLink { settings } label: { Label("Settings", systemImage: "gearshape") }.id("settings")
                }
            }
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "listBottom") ? .bottom : .top)   // Simulator captures
            // Simulator captures: the scene driver scrolls, picks and opens as a finger would
            .onChange(of: Capture.shared.listScroll) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.9)) { proxy.scrollTo(id, anchor: id == agents.first?.id ? .bottom : .center) }
            }
            .onChange(of: Capture.shared.pick) { _, id in
                guard let id else { return }
                active = id; Haptics.play(.click); dismiss(); Capture.shared.pick = nil
            }
            .onChange(of: Capture.shared.openSoul) { _, id in
                guard let id else { return }
                path.append(id); Capture.shared.openSoul = nil
            }
            }
            .navigationDestination(for: String.self) { id in
                if let a = agents.first(where: { $0.id == id }) { soul(a) }
            }
        }
        .overlay { if ScreenModel.fakeVoice { TouchSpot(show: Capture.shared.touch).ignoresSafeArea() } }
    }

    /// An agent's row: its face and name, its status (and its dot), what it runs on, a check if it's the one you talk to.
    private func row(_ c: String, _ a: AgentInfo?) -> some View {
        HStack(spacing: 10) {
            AgentFace(character: c, size: 34)
                .overlay(alignment: .bottomTrailing) {
                    if let a { Circle().fill(Agents.dot(a)).frame(width: 9, height: 9).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)) }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(CharacterKind(id: c)?.name ?? c).font(.system(size: 15, weight: .semibold)).foregroundStyle(Pal.white)
                if let a { Text(Agents.status(a)).font(.system(size: 12)).foregroundStyle(a.needs ? Pal.amber : Pal.gray).lineLimit(2) }
                else { Text("Not on your Mac yet: update the hub").font(.system(size: 12)).foregroundStyle(Pal.dim).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if let a, a.id == active { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Pal.clay) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Another agent finished, asked, needs an approval or showed you something: its face, name and line, above the
/// handle. A tap goes to that agent (and opens what it showed you); it goes away by itself after a while.
struct AgentNotice: View {
    let agent: AgentInfo
    let line: String
    let open: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            AgentFace(character: agent.character, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Pal.white).lineLimit(1)
                Text(line).font(.system(size: 12)).foregroundStyle(Color(white: 0.75)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(5).padding(.trailing, 10)
        .background(Color(white: 0.13).opacity(0.96), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .onTapGesture { open() }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}
