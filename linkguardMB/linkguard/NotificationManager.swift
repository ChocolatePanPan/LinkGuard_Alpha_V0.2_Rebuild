import UserNotifications
import Foundation

// MARK: - NotificationCategory

enum NotificationCategory: String {
    case threat   = "THREAT_ALERT"
    case warning  = "WARNING_ALERT"
    case info     = "INFO_ALERT"
}

// MARK: - NotificationManager

/// Manages local notifications for LinkGuard threat and status alerts.
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    override private init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Authorization

    /// Request notification permission from the user.
    /// - Parameter completion: Called on the main thread with the granted flag and any error.
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted, error)
            }
        }
    }

    /// Check the current notification authorization status.
    func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    // MARK: - Scheduling

    /// Schedule an immediate (1-second delay) notification.
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    ///   - category: The notification category. Defaults to `.info`.
    ///   - identifier: A unique identifier; defaults to a new UUID string.
    /// - Returns: The identifier used for the notification request.
    @discardableResult
    func scheduleNotification(title: String,
                              body: String,
                              category: NotificationCategory = .info,
                              identifier: String = UUID().uuidString) -> String {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("NotificationManager: Failed to schedule '\(identifier)' – \(error)")
            }
        }
        return identifier
    }

    /// Schedule a notification for a threat alert.
    @discardableResult
    func scheduleThreatAlert(title: String, body: String) -> String {
        scheduleNotification(title: title, body: body, category: .threat)
    }

    // MARK: - Cancellation

    /// Cancel a pending notification by identifier.
    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Cancel all pending notifications.
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }

    /// Remove all delivered notifications from Notification Centre.
    func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Badge

    /// Set the app icon badge count.
    /// - Parameter count: The badge count to display. Pass 0 to clear the badge.
    func setBadge(count: Int) {
#if os(iOS)
        center.setBadgeCount(count) { error in
            if let error {
                print("NotificationManager: Failed to set badge – \(error)")
            }
        }
#endif
    }

    // MARK: - Categories

    private func registerCategories() {
        let threatCategory = UNNotificationCategory(
            identifier: NotificationCategory.threat.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        let warningCategory = UNNotificationCategory(
            identifier: NotificationCategory.warning.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let infoCategory = UNNotificationCategory(
            identifier: NotificationCategory.info.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([threatCategory, warningCategory, infoCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        print("NotificationManager: User interacted with notification '\(identifier)'")
        completionHandler()
    }
}
