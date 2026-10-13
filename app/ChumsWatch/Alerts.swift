import UserNotifications
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// When Chums isn't in front (after a crown press, say), what needs you arrives as a notification: watchOS taps your
/// wrist and shows it over the watch face, and tapping it opens Chums. While Chums is in front, even dimmed, the
/// notification is dropped: the character and Chums's own haptics do the job. Local notifications need no push
/// service, so they work with a free developer account.
@MainActor
enum Alerts {
    private static let delegate = Delegate()

    static func setUp() {
        let c = UNUserNotificationCenter.current()
        c.delegate = delegate
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
#if os(watchOS)
        guard WKApplication.shared().applicationState != .active else { return }
#else
        guard UIApplication.shared.applicationState != .active else { return }
#endif
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "chums"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        /// Chums is in front but dimmed. With keyring mode running, Chums taps your wrist itself, so the notification
        /// would be a second tap; without it Chums can't tap you, so the notification shows and sounds.
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
#if os(watchOS)
            await MainActor.run { KeepOn.shared.running } ? [] : [.banner, .sound]
#else
            [.banner, .sound]
#endif
        }
    }
}
