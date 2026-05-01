import Foundation
import UserNotifications

/// 本地通知管理器（macOS + iOS）
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
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
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        schedule(content: content, id: "sos-\(victimID)-\(Date().timeIntervalSince1970)")
    }

    /// 裝置離線通知
    func sendOfflineNotification(victimID: String) {
        let content = UNMutableNotificationContent()
        content.title = "裝置離線"
        content.body = "\(victimID) 已失去訊號連線"
        content.sound = .default
        content.categoryIdentifier = "DEVICE_OFFLINE"
        schedule(content: content, id: "offline-\(victimID)-\(Date().timeIntervalSince1970)")
    }

    /// 低電量通知
    func sendLowBatteryNotification(victimID: String, battery: Int) {
        let content = UNMutableNotificationContent()
        content.title = "低電量警告"
        content.body = "\(victimID) 電量僅剩 \(battery)%"
        content.sound = .default
        content.categoryIdentifier = "LOW_BATTERY"
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

    
    
    // MARK: - 前景時也顯示通知

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
