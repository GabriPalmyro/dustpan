import UserNotifications

/// Thin wrapper over UNUserNotificationCenter. Clicking a notification opens the main window.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    var onOpen: (@MainActor () -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Reusing the id replaces a stale alert instead of stacking a new one.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
