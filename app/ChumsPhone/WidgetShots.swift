#if DEBUG
import SwiftUI
import WidgetKit

/// Debug builds only: launched with -widgetShots YES, the app draws every widget size, with the hub's state now and
/// with Ray asking for an approval, to Documents/widgets/*.png (`xcrun simctl get_app_container <sim> dev.chums data`).
/// For checking the widgets without putting each one on a Home Screen.
@MainActor enum WidgetShots {
    static func run() async {
        guard UserDefaults.standard.bool(forKey: "widgetShots") else { return }
        let live = await WidgetHub.state() ?? WidgetHub.sample
        let asking = WState(
            rev: live.rev,
            agents: live.agents.map { a in
                a.id == "ray" ? WAgent(id: a.id, name: a.name, character: a.character, status: "waiting", line: "Delete the build folder?", needs: true) : a
            },
            approvals: [WApproval(requestId: "shot", session: "ray", tool: "Bash", description: "Delete the build folder",
                                  summary: "rm -rf ~/Developer/chums/app/build")],
            spoken: [])
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("widgets")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // the iPhone 17 Pro's widget sizes, in points
        let agentSizes: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("circular", .accessoryCircular, CGSize(width: 76, height: 76)),
            ("rect", .accessoryRectangular, CGSize(width: 172, height: 76)),
            ("inline", .accessoryInline, CGSize(width: 260, height: 26)),
        ]
        let teamSizes: [(String, WidgetFamily, CGSize)] = [
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("large", .systemLarge, CGSize(width: 364, height: 382)),
        ]
        for (tag, state) in [("live", live), ("asking", asking)] {
            for (name, family, size) in agentSizes {
                for pick in ["ray", "noodle", "stretch", "peeps"] where pick == "ray" || family == .systemSmall {
                    let e = await ChumsEntry.make(state, pick: pick, family: family, size: size)
                    shot(AgentWidgetView(entry: e, shownAs: family), size, family, dir.appendingPathComponent("agent-\(name)-\(tag)\(pick == "ray" ? "" : "-" + pick).png"))
                }
            }
            for (name, family, size) in teamSizes {
                let e = ChumsEntry(date: .now, state: state, pick: nil)
                shot(TeamWidgetView(entry: e, shownAs: family), size, family, dir.appendingPathComponent("team-\(name)-\(tag).png"), margins: true)
            }
        }
        hubLog("widget shots written: \(dir.path)")
    }

    private static func shot(_ view: some View, _ size: CGSize, _ family: WidgetFamily, _ url: URL, margins: Bool = false) {
        let home = [.systemSmall, .systemMedium, .systemLarge].contains(family)
        let framed = view
            .padding(home && margins ? 16 : 0)                                 // the Agent widget draws to its edges
            .frame(width: size.width, height: size.height)
            .background(home ? Color.black : Color(white: 0.22))             // the Lock Screen ones on a gray, to see them
            .clipShape(RoundedRectangle(cornerRadius: home ? 24 : 8, style: .continuous))
            .padding(12)
            .background(Color(white: 0.35))                                   // a wallpaper behind, so the black edge shows
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: framed)
        r.scale = 3
        if let data = r.uiImage?.pngData() { try? data.write(to: url) }
    }

    private static func hubLog(_ s: String) { print(s) }
}
#endif
