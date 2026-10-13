import SwiftUI
import WidgetKit

/// Chums on the iPhone: the same agents as the watch, through the same hub. One screen per agent (HomeView): its
/// conversation with the character as its last row, the other agents in a panel from the left, a box to type, talk or
/// send photos and files. Widgets, Lock Screen widgets, a Control (Control Center, the Action Button) and Siri reach it
/// too (ChumsPhoneWidgets, PhoneIntents).
@main
struct ChumsPhoneApp: App {
    @State private var hub = HubClient()
    @Environment(\.scenePhase) private var phase

    init() { CharacterKind.migrate() }

    var body: some Scene {
        WindowGroup {
            HomeView(hub: hub)
                .preferredColorScheme(.dark)
                .onChange(of: phase, initial: true) { old, p in
                    // a system alert or Control Center over it (inactive) keeps it listening; only the background stops it
                    if p == .active { hub.start() } else if p == .background { hub.stop() }
                    // what the widgets show is what the app last saw
                    if p != .active { WidgetCenter.shared.reloadAllTimelines() }
                    if old != p { hub.event("phone: app \(p == .active ? "active" : p == .inactive ? "inactive" : "background")") }
                }
        }
    }
}

/// What a link from a widget, the Control or Siri asks for: chums://agent/<id> shows that agent, chums://talk[/<id>]
/// also starts listening.
enum PhoneLink: Equatable {
    case agent(String), talk(String?)
    init?(_ url: URL) {
        guard url.scheme == "chums" else { return nil }
        let id = url.pathComponents.dropFirst().first
        switch url.host {
        case "agent": guard let id else { return nil }; self = .agent(id)
        case "talk": self = .talk(id)
        default: return nil
        }
    }
}
