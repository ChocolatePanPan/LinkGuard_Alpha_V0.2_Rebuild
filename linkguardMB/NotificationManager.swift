import Foundation
import UserNotifications

/// 本地通知管理器（macOS + iOS）
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_LINKGUARD",
            title: "打開 LinkGuard",
            options: [.foreground]
        )
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: "SOS_ALERT", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "PWS_ALERT", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "URGENT_BROADCAST", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "PATIENT_WARNING", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "PERSONAL_NOTIFICATION", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "DEVICE_OFFLINE", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "LOW_BATTERY", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "COMMAND_ORDER", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "DECISION", actions: [openAction], intentIdentifiers: [], options: [.customDismissAction])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    // MARK: - 權限請求

    /// 應在 App 啟動時呼叫
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("[NotificationManager] 授權失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 發送通知

    /// SOS 求救通知（時效性）
    func sendSOSNotification(victimID: String, heartRate: Int, distance: String) {
        let content = UNMutableNotificationContent()
        content.title = "SOS 求救警報"
        content.subtitle = victimID
        content.body = "心率: \(heartRate > 0 ? "\(heartRate) bpm" : "-- bpm") · 距離: ~\(distance)"
        // SOS 使用與撤離命令不同的系統提示音（非 critical）
        content.sound = .default
        content.categoryIdentifier = "SOS_ALERT"
        content.userInfo = ["victim_id": victimID, "route": "sos"]
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        schedule(content: content, id: "sos-\(victimID)-\(Date().timeIntervalSince1970)")
    }

    /// PWS 災防警報
    func sendPWSAlertNotification(alert: PWSAlert) {
        let content = UNMutableNotificationContent()
        content.title = "PWS 警報：\(alert.title)"
        content.subtitle = alert.severity.label
        content.body = alert.content
        content.sound = alert.severity >= .severe ? .defaultCritical : .default
        content.categoryIdentifier = "PWS_ALERT"
        content.userInfo = ["alert_id": alert.id, "route": "notifications"]
        setTimeSensitive(content)
        schedule(content: content, id: "pws-\(alert.id)")
    }

    /// HQ 緊急文字廣播
    func sendUrgentBroadcastNotification(broadcast: TextBroadcast) {
        let content = UNMutableNotificationContent()
        content.title = "HQ 緊急廣播"
        content.subtitle = broadcast.senderName
        content.body = broadcast.message
        content.sound = .defaultCritical
        content.categoryIdentifier = "URGENT_BROADCAST"
        content.userInfo = ["broadcast_id": broadcast.broadcastId, "route": "notifications"]
        setTimeSensitive(content)
        schedule(content: content, id: "broadcast-\(broadcast.broadcastId)")
    }

    /// 傷患惡化預警
    func sendPatientWarningNotification(warning: PatientWarning) {
        let content = UNMutableNotificationContent()
        content.title = "傷患預警：\(warning.patientId)"
        content.subtitle = warning.location
        content.body = warning.message.isEmpty ? "傷患狀態需要立即確認" : warning.message
        content.sound = warning.warningLevel == "high" ? .defaultCritical : .default
        content.categoryIdentifier = "PATIENT_WARNING"
        content.userInfo = ["patient_id": warning.patientId, "route": "notifications"]
        setTimeSensitive(content)
        schedule(content: content, id: "patient-warning-\(warning.patientId)-\(Date().timeIntervalSince1970)")
    }

    /// 個人通知
    func sendPersonalNotification(_ notification: PersonalNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = "LinkGuard"
        content.body = notification.content
        content.sound = .default
        content.categoryIdentifier = "PERSONAL_NOTIFICATION"
        content.userInfo = ["notification_id": notification.id, "route": "notifications"]
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .active
        }
        schedule(content: content, id: "personal-\(notification.id)")
    }

    /// 裝置離線通知
    func sendOfflineNotification(victimID: String) {
        let content = UNMutableNotificationContent()
        content.title = "裝置離線"
        content.body = "\(victimID) 已失去訊號連線"
        content.sound = .default
        content.categoryIdentifier = "DEVICE_OFFLINE"
        content.userInfo = ["victim_id": victimID, "route": "victims"]
        schedule(content: content, id: "offline-\(victimID)-\(Date().timeIntervalSince1970)")
    }

    /// 低電量通知
    func sendLowBatteryNotification(victimID: String, battery: Int) {
        let content = UNMutableNotificationContent()
        content.title = "低電量警告"
        content.body = "\(victimID) 電量僅剩 \(battery)%"
        content.sound = .default
        content.categoryIdentifier = "LOW_BATTERY"
        content.userInfo = ["victim_id": victimID, "route": "victims"]
        schedule(content: content, id: "battery-\(victimID)-\(Date().timeIntervalSince1970)")
    }

    /// 指揮中心命令通知（時效性）
    func sendCommandNotification(order: CommandOrder) {
        let content = UNMutableNotificationContent()
        content.title = "指揮中心：\(order.priority.label)"
        content.subtitle = order.title
        content.body = order.detail
        content.sound = order.priority == .critical ? .defaultCritical : .default
        content.categoryIdentifier = "COMMAND_ORDER"
        content.userInfo = ["command_id": order.id.uuidString, "route": "decision"]
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = order.priority == .critical ? .timeSensitive : .active
        }
        schedule(content: content, id: "cmd-\(order.id.uuidString)")
    }

    /// 指揮決策通知（時效性）
    func sendDecisionNotification(decision: HQDecision) {
        let content = UNMutableNotificationContent()
        content.title = "指揮決策"
        content.body = decision.decision
        content.sound = .defaultCritical
        content.categoryIdentifier = "DECISION"
        content.userInfo = ["decision_id": decision.id.uuidString, "route": "decision"]
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        schedule(content: content, id: "decision-\(decision.id.uuidString)")
    }

    // MARK: - 排程通知（即時觸發）

    private func schedule(content: UNMutableNotificationContent, id: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func setTimeSensitive(_ content: UNMutableNotificationContent) {
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
    }

    
    
    // MARK: - 前景時也顯示通知

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let route = content.userInfo["route"] as? String ?? route(for: content.categoryIdentifier)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .linkGuardNotificationRouteRequested,
                object: nil,
                userInfo: [
                    "route": route,
                    "title": content.title,
                    "subtitle": content.subtitle,
                    "body": content.body,
                    "categoryIdentifier": content.categoryIdentifier
                ]
            )
        }
        completionHandler()
    }

    private func route(for categoryIdentifier: String) -> String {
        switch categoryIdentifier {
        case "SOS_ALERT": return "sos"
        case "COMMAND_ORDER", "DECISION": return "decision"
        case "DEVICE_OFFLINE", "LOW_BATTERY": return "victims"
        default: return "notifications"
        }
    }
}

extension Notification.Name {
    static let linkGuardNotificationRouteRequested = Notification.Name("linkGuardNotificationRouteRequested")
}
