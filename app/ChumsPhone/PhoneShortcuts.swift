import AppIntents
import Foundation

/// Siri and Shortcuts: "Ask Chums" sends what you say to an agent and reads its answer back; "Talk to Chums" opens
/// the app listening.
struct AskAgent: AppIntent {
    static let title: LocalizedStringResource = "Ask an agent"
    static let description = IntentDescription("Sends a message to one of your Chums agents and reads its answer.")
    @Parameter(title: "Agent") var agent: AgentEntity
    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true)) var message: String

    static var parameterSummary: some ParameterSummary { Summary("Ask \(\.$agent) \(\.$message)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let t0 = Date().timeIntervalSince1970 * 1000
        guard await WidgetHub.say(message, agent: agent.id) else {
            return .result(value: "", dialog: "I can't reach your Mac.")
        }
        if let reply = await WidgetHub.reply(agent: agent.id, after: t0, timeout: 45) {
            return .result(value: reply, dialog: "\(reply)")
        }
        return .result(value: "", dialog: "\(agent.name) is still working on it. The answer will be in Chums.")
    }
}

struct PhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAgent(), phrases: ["Ask \(.applicationName)", "Ask \(\.$agent) in \(.applicationName)"],
                    shortTitle: "Ask an agent", systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: TalkToAgent(), phrases: ["Talk to \(.applicationName)", "Talk to \(\.$agent) in \(.applicationName)"],
                    shortTitle: "Talk to an agent", systemImageName: "waveform")
    }
}
