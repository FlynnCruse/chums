import AppIntents
import Foundation
import WidgetKit

// What the widgets, the Control and Siri can do: pick an agent, answer an approval, open Chums listening. In the app and
// in the widget extension both (the app adds Siri's "Ask", PhoneShortcuts.swift).

struct AgentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Agent"
    static let defaultQuery = AgentQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AgentQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AgentEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [AgentEntity] { await all() }
    private func all() async -> [AgentEntity] {
        let agents = await WidgetHub.state()?.agents ?? WidgetHub.sample.agents
        return agents.map { AgentEntity(id: $0.id, name: $0.name) }
    }
}

/// Which agent a widget shows: one you pick, or the one you last talked to.
struct PickAgent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Agent"
    static let description = IntentDescription("The agent this widget shows. Without one, it shows the agent you last talked to.")
    @Parameter(title: "Agent") var agent: AgentEntity?
    init() {}
}

/// Allow or deny what an agent asks, right from the widget.
struct AnswerApproval: AppIntent {
    static let title: LocalizedStringResource = "Answer an approval"
    static let isDiscoverable = false
    @Parameter(title: "Request") var requestId: String
    @Parameter(title: "Allow") var allow: Bool
    init() {}
    init(_ requestId: String, allow: Bool) { self.requestId = requestId; self.allow = allow }
    func perform() async throws -> some IntentResult {
        _ = await WidgetHub.verdict(requestId, allow: allow)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Opens Chums listening to an agent (the Control, the Action Button, a widget's Talk, Siri).
struct TalkToAgent: AppIntent {
    static let title: LocalizedStringResource = "Talk to an agent"
    static let description = IntentDescription("Opens Chums already listening: say what you want, then tap send.")
    @Parameter(title: "Agent") var agent: AgentEntity?
    init() {}
    init(agent: AgentEntity?) { self.agent = agent }
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "chums://talk" + (agent.map { "/\($0.id)" } ?? ""))!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
