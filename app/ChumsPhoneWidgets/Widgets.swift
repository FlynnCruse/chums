import AppIntents
import SwiftUI
import WidgetKit

// Chums on the Home Screen, the Lock Screen and in Control Center. All black; the agents' faces; amber when one needs
// you. A tap opens Chums on that agent; Allow and Deny answer an approval without opening it; Talk (and the Control,
// which the Action Button can run) opens Chums already listening.

@main
struct ChumsWidgets: WidgetBundle {
    var body: some Widget {
        AgentWidget()
        TeamWidget()
        TalkControl()
    }
}

struct AgentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChumsEntry { ChumsEntry(date: .now, state: WidgetHub.sample, pick: nil) }
    func snapshot(for config: PickAgent, in context: Context) async -> ChumsEntry {
        let s = context.isPreview ? WidgetHub.sample : (await WidgetHub.state() ?? WidgetHub.sample)
        return await ChumsEntry.make(s, pick: config.agent?.id, family: context.family, size: context.displaySize)
    }
    func timeline(for config: PickAgent, in context: Context) async -> Timeline<ChumsEntry> {
        let s = await WidgetHub.state()
        // sooner while something's happening; the app refreshes them too whenever it sees a change
        let busy = s?.agents.contains { $0.needs || $0.status == "working" } ?? false
        let e = await ChumsEntry.make(s, pick: config.agent?.id, family: context.family, size: context.displaySize)
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(busy ? 300 : 900)))
    }
}

struct TeamProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChumsEntry { ChumsEntry(date: .now, state: WidgetHub.sample, pick: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ChumsEntry) -> Void) {
        Task { completion(ChumsEntry(date: .now, state: context.isPreview ? WidgetHub.sample : (await WidgetHub.state() ?? WidgetHub.sample), pick: nil)) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChumsEntry>) -> Void) {
        Task {
            let s = await WidgetHub.state()
            let busy = s?.agents.contains { $0.needs || $0.status == "working" } ?? false
            completion(Timeline(entries: [ChumsEntry(date: .now, state: s, pick: nil)], policy: .after(.now.addingTimeInterval(busy ? 300 : 900))))
        }
    }
}

// MARK: one agent

struct AgentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "chums.agent", intent: PickAgent.self, provider: AgentProvider()) { e in
            AgentWidgetView(entry: e).containerBackground(.black, for: .widget)
        }
        .contentMarginsDisabled()                                   // the watch's screen goes to the edges
        .configurationDisplayName("Agent")
        .description("One agent: what it's doing, Allow or Deny what it asks, and Talk.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: every agent

struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "chums.team", provider: TeamProvider()) { e in
            TeamWidgetView(entry: e).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Agents")
        .description("Every agent at a glance; a tap opens one. What needs you comes first.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

// MARK: the Control: Control Center, the Lock Screen, the Action Button

struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "chums.talk") {
            ControlWidgetButton(action: TalkToAgent()) {
                Label("Talk to Chums", systemImage: "waveform")
            }
        }
        .displayName("Talk to Chums")
        .description("Opens Chums listening to the agent you talk to.")
    }
}
