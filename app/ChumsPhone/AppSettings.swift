import SwiftUI

/// The iPhone app's own settings (each agent's are in its card: what it runs on, its voice, its soul), on a card that
/// slides up (drag it down to put it away): the connection to your Mac, reading replies aloud, haptics, the agents'
/// order, and which build this is.
struct AppSettings: View {
    let hub: HubClient
    var character: String = Agents.fallback          // the agent on screen: its colours are the card's ground
    @AppStorage("voice") private var speak = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("agentOrder") private var order = ""
    @State private var ms: Double?
    @State private var checking = false
    @State private var checked = false

    private var host: String { URL(string: hub.address)?.host() ?? hub.address }
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(v) · built \(HubConfig.build)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.title.weight(.bold)).foregroundStyle(.white).padding(.leading, 4).padding(.bottom, 6)

                card {
                    HStack(spacing: 14) {
                        Image(systemName: hub.connected ? "desktopcomputer" : "exclamationmark.triangle.fill")
                            .font(.title3).foregroundStyle(hub.connected ? .white : Pal.amber)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hub.connected ? "Connected to your Mac" : "Can't reach your Mac").font(.body.weight(.semibold))
                            Text(hub.lastError ?? (host.hasSuffix(".ts.net") ? "Through Tailscale Funnel" : "On this network"))
                                .font(.footnote).foregroundStyle(Ink.quiet)
                        }
                    }
                    divider
                    row("Address") { Text(host).foregroundStyle(Ink.quiet).lineLimit(1).truncationMode(.middle) }
                    divider
                    row("Answers in") {
                        if checking { ProgressView().controlSize(.small).tint(.white) }
                        else if let ms { Text("\(Int(ms.rounded())) ms").monospacedDigit().foregroundStyle(Ink.quiet) }
                        else { Text(checked ? "No answer" : "–").foregroundStyle(checked ? Pal.amber : Color(white: 0.5)) }
                    }
                    divider
                    Button { check() } label: {
                        Text("Check the connection").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(Pressable()).foregroundStyle(.white).disabled(checking)
                }
                note("Chums reaches the hub on your Mac at this address. If it can't, check that the hub is running, and run bin/chums-doctor on the Mac.")

                card {
                    Toggle("Read replies aloud", isOn: $speak).font(.body).frame(minHeight: 44)
                    divider
                    Toggle("Haptics", isOn: $haptics).font(.body).frame(minHeight: 44)
                }
                .toggleStyle(InkToggle())
                note("Replies to what you say on the iPhone are read aloud here, each in its agent's voice. Off, they only show in the conversation.")

                if !order.isEmpty {
                    card {
                        Button { withAnimation(Move.settle) { order = "" }; Haptics.play(.success) } label: {
                            Text("Put the agents back in their first order").font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(Pressable())
                        .foregroundStyle(.white)
                    }
                    note("You changed the agents' order. This puts them back as they came.")
                        .transition(.opacity)
                }

                Text(version).font(.footnote).foregroundStyle(Ink.ghost)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 30)
        }
        .cardSheet(character: character)
        .task { check() }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private func row<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        HStack { Text(title).font(.body); Spacer(minLength: 12); value().font(.body) }.frame(minHeight: 44)
    }
    private var divider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    private func note(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(Color(white: 0.5)).padding(.horizontal, 6).padding(.bottom, 10)
    }

    private func check() {
        checking = true
        Task { ms = await hub.ping(); checking = false; checked = true }
    }
}
