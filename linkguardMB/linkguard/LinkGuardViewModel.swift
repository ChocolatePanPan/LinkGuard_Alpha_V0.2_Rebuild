import Foundation
import SwiftUI
import Combine
import AVFoundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

struct AIServicePausedBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("AI服務暫停"))
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                if !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func aiPausedAppearance(_ isPaused: Bool) -> some View {
        self
            .grayscale(isPaused ? 1 : 0)
            .opacity(isPaused ? 0.55 : 1.0)
            .disabled(isPaused)
    }
}

/// LinkGuard 核心業務邏輯 ViewModel
/// 對應韌體 rescue.ino 的搜救端節點
@MainActor
class LinkGuardViewModel: ObservableObject {

    // MARK: - 發布狀態

    /// 自動產生並持久化裝置 ID（格式 RT-XXX），LoRa 連線後由韌體覆蓋
    private static func persistentNodeID() -> String {
        if let custom = UserDefaults.standard.string(forKey: "linkguard_custom_node_id"), !custom.isEmpty {
            return custom
        }
        let key = "linkguard_node_hex_id"
        if let saved = UserDefaults.standard.string(forKey: key) { return "RT-\(saved)" }
        let hex = String(format: "%03X", Int.random(in: 0...0xFFF))
        UserDefaults.standard.set(hex, forKey: key)
        return "RT-\(hex)"
    }

    /// 讀取持久化的部門碼，無則回傳預設 EMT
    private static func persistentDeptCode() -> String {
        UserDefaults.standard.string(forKey: "linkguard_dept_code") ?? "EMT"
    }

    /// 讀取持久化的使用者暱稱（顯示在 HQ 地圖 / 清單）
    private static func persistentUserNickname() -> String {
        UserDefaults.standard.string(forKey: "linkguard_user_nickname") ?? ""
    }

    /// App 啟動時間戳，用於運行時間顯示
    private let launcherStartTime = Date()

    /// 連線/回前景初期靜默期（秒）：收到的歷史同步訊息只記錄，不彈全螢幕警報
    private let startupGracePeriod: TimeInterval = 3.0
    private var alarmSuppressionUntil = Date().addingTimeInterval(3.0)
    /// 是否已過警報靜默期
    private var pastStartupGrace: Bool {
        Date() >= alarmSuppressionUntil
    }

    @Published var victims: [VictimNode]    = []
    @Published var sosRecords: [SOSRecord]  = []
    @Published var nodeStatus = RescueNodeStatus(
        nodeID: persistentNodeID(), deptCode: persistentDeptCode(), battery: 0, loraLevel: 4, isConnected: false, pairCode: "0000"
    )

    /// 使用者自訂暱稱（顯示在 HQ）
    @Published var userNickname: String = persistentUserNickname()

    @Published var isSimulating = false
    @Published var isWiFiCommandMode = false

    /// 運行時間（秒）— 從 launcherStartTime 計算，免去 Timer 喚醒
    var uptimeSeconds: Int {
        Int(Date().timeIntervalSince(launcherStartTime))
    }

    /// 觸發全螢幕 SOS 警報的受困者（非 nil 時顯示覆蓋層）
    @Published var latestSOSVictim: VictimNode?

    // 指揮中心命令
    @Published var commandOrders: [CommandOrder] = []
    @Published var latestCriticalCommand: CommandOrder?

    // BLE 狀態
    @Published var isBluetoothConnected = false
    @Published var bluetoothDeviceName: String?

    // 增援系統
    @Published var reinforcementRequests: [ReinforcementRequest] = []
    @Published var latestReinforcementRequest: ReinforcementRequest?

    // 團隊
    @Published var teamMembers: [TeamMember] = []

    // --- 新功能狀態 ---
    // 災害狀態（從 HQ 接收）
    @Published var disasterSite: DisasterSite?

    // 聊天訊息
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatDraft = ""
    /// 聊天已讀回條：messageID → 已讀裝置數
    @Published var chatReadCounts: [String: Int] = [:]

    // 人員配置（從 HQ 接收）
    @Published var personnelAssignments: [PersonnelAssignment] = []

    // PWS 警報（從 HQ 接收）
    @Published var pwsAlerts: [PWSAlert] = []

    // 會報（從 HQ 接收）
    @Published var briefings: [BriefingReport] = []

    // 個人通知
    @Published var personalNotifications: [PersonalNotification] = []
    @Published var unreadNotificationCount: Int = 0

    // 統一活動記錄（通知頁使用）
    @Published var activityLog: [ActivityLogEntry] = []

    // 快速狀態回報
    @Published var quickStatuses: [QuickStatus] = []

    // 省電：靜止偵測（GPS 動態降頻）
    private var lastReportedLocation: CLLocation?
    private var stationaryCount: Int = 0
    private var isStationaryMode = false
    private static let stationaryThresholdMeters: Double = 10.0
    private static let stationaryCountThreshold = 3

    // 省電：狀態差異上報
    private var lastReportedBattery: Int = -1
    private var lastReportedBLE: Bool? = nil
    private var lastReportedVictimCount: Int = -1
    private var lastReportedSOSCount: Int = -1

    // 任務指派（從 HQ 接收）
    @Published var tasks: [TaskAssignment] = []

    // 倒數計時器（從 HQ 接收）
    @Published var countdownTimers: [CountdownTimerModel] = []
    private var countdownRefreshTimer: Timer?

    // 危險標記
    @Published var hazardReports: [HazardReport] = []

    // 傷員回報橡
    @Published var decisions: [HQDecision] = []

    // 電台會報
    @Published var radioReports: [RadioReport] = []
    @Published var currentBroadcaster: String?
    /// 自動播放收到的電台音訊
    @Published var autoPlayRadio = true
    /// 正在播放的報告 ID
    @Published var playingReportId: String?
    private var radioAudioPlayer: AVAudioPlayer?
    // 照片回報
    @Published var photoReports: [PhotoReport] = []
    /// 資源狀態
    @Published var resourceStatus: ResourceStatus?
    /// 最新統計快照
    @Published var latestStats: [String: Any]?
    /// 文字廣播列表
    @Published var textBroadcasts: [TextBroadcast] = []
    /// 傷患預警列表
    @Published var patientWarnings: [PatientWarning] = []
    /// 本地傷患回報（持久化）
    @Published var localPatients: [PatientReport] = []
    /// HQ 下發的傷患編號配置
    @Published var patientIDConfig = PatientIDConfig()
    /// 最新翻譯結果
    @Published var latestTranslation: TranslationResult?
    @Published var isTranslating = false
    @Published var translationErrorMessage: String?
    /// 已讀狀態追蹤
    @Published var readStatuses: [String: (total: Int, readCount: Int)] = [:]
    /// 當前的緊急廣播
    @Published var urgentBroadcast: TextBroadcast?
    /// 當前的傷患預警
    @Published var activePatientWarning: PatientWarning?

    // MARK: - 計算屬性

    var onlineVictimCount: Int {
        victims.filter(\.isOnline).count
    }

    var sosVictimCount: Int {
        victims.filter { $0.isSOS && $0.isOnline }.count
    }

    var unacknowledgedSOSCount: Int {
        sosRecords.filter { !$0.isAcknowledged }.count
    }

    var unreadCommandCount: Int {
        commandOrders.filter { !$0.isRead }.count
    }

    var pendingReinforcementCount: Int {
        reinforcementRequests.filter { $0.status == .pending && !$0.isFromSelf }.count
    }

    var onlineTeamCount: Int {
        teamMembers.filter(\.isOnline).count
    }

    var uptimeText: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        let s = uptimeSeconds % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    var systemStatus: (text: String, color: Color) {
        if commandClient.isConnected { return (L("已連線 Mac HQ"), NV.green) }
        if sosVictimCount > 0 { return (L("SOS 警報中"), NV.danger) }
        return (L("未連線 Mac HQ"), .gray)
    }

    // MARK: - 依賴

    let bluetoothManager = BluetoothManager()
    private let simulation = SimulationEngine()
    private let commandEngine = SimulatedCommandEngine()
    let commandClient = CommandClient()

    /// 雙 AI 共識升級觸發發布者（由 TCP escalation_trigger 廣播觸發，由 RadioView 訂閱）
    let escalationTriggerPublisher = PassthroughSubject<[String: Any], Never>()

    /// 語音轉錄伺服器位址（取自 HQ 連線的實際 IP）
    var transcriptionServerHost: String {
        // 優先使用 TCP 連線解析出的真正 IP（Bonjour 連線時 serverName 可能是服務名稱）
        if let ip = commandClient.resolvedIP, !ip.isEmpty {
            var clean = ip
            // 安全清理：移除 zone ID 和 IPv4-mapped 前綴
            if let pct = clean.firstIndex(of: "%") {
                clean = String(clean[clean.startIndex..<pct])
            }
            if clean.hasPrefix("::ffff:") {
                clean = String(clean.dropFirst(7))
            }
            return clean
        }
        if let name = commandClient.serverName {
            return name.components(separatedBy: ":").first ?? "localhost"
        }
        return "localhost"
    }

    var isAIServicePaused: Bool {
        commandClient.hqServerStatus?.aiServicePaused == true
    }

    var aiServicePauseMessage: String {
        guard isAIServicePaused else { return "" }
        if let reason = commandClient.hqServerStatus?.aiServicePauseReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return L(reason)
        }
        return L("後台電腦已進入省電模式")
    }

    var isFieldAIAvailable: Bool {
        !isAIServicePaused && !transcriptionServerHost.isEmpty && transcriptionServerHost != "localhost"
    }

    private var simulationTimer: Timer?
    private var commandTimer: Timer?
    private var hapticTimer: Timer?
    private var sosAutoDowngradeTimer: Timer?
    private var statusReportTimer: Timer?
    private var locationTimer: Timer?
    private let locationManager = CLLocationManager()
    private let locationDelegate = LocationDelegate()
    private var cancellables = Set<AnyCancellable>()

    // 離線/低電量通知追蹤
    private var previousOnlineStates: [String: Bool] = [:]
    private var lowBatteryNotified: Set<String> = []

    // MARK: - 初始化

    init() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        // 只轉發 commandClient 實際被 UI 使用的屬性變更（isConnected / serverName）
        // 避免 cascade objectWillChange 導致整個 TabView 頻繁重繪
        commandClient.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // 握手加速：TCP 連線成功後立即送出 status_report，HQ 最多延遲 0.5 秒即完成識別
        // 若等 30 秒 Timer 才第一次觸發，HQ 的 fieldUnits 會有 30 秒的空窗期
        commandClient.$isConnected
            .removeDuplicates()
            .filter { $0 }           // 只對 false → true 的變化觸發
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.suppressRealtimeAlarms()
                // 短暫延遲讓 resolvedIP 先完成填入
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.sendStatusReport()
                }
            }
            .store(in: &cancellables)
        commandClient.$serverName
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        commandClient.$hqServerStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        setupBLECallbacks()
        setupWiFiClient()
        setupAppLifecycleRecovery()
        NotificationManager.shared.requestAuthorization()
        if let saved: PatientIDConfig = PersistenceManager.shared.load(key: "patientIDConfig") {
            patientIDConfig = saved
        }
        // 載入本地傷患資料
        if let saved: [PatientReport] = PersistenceManager.shared.load(key: "localPatients") {
            localPatients = saved
        }
    }

    /// 取得電池電量：BLE 韌體值優先，否則用裝置自身電量
    private var effectiveBattery: Int {
        if nodeStatus.battery > 0 { return nodeStatus.battery }
        #if canImport(UIKit)
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Int(level * 100) : 0
        #else
        return 0
        #endif
    }

    deinit {
        simulationTimer?.invalidate()
        commandTimer?.invalidate()
        statusReportTimer?.invalidate()
        locationTimer?.invalidate()
        hapticTimer?.invalidate()
        sosAutoDowngradeTimer?.invalidate()
        countdownRefreshTimer?.invalidate()
        commandClient.stop()
    }

    // MARK: - BLE 回呼綁定

    private func setupBLECallbacks() {
        bluetoothManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isBluetoothConnected = connected
                self?.nodeStatus.isConnected = connected
            }
            .store(in: &cancellables)

        bluetoothManager.$connectedDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$bluetoothDeviceName)

        bluetoothManager.onStatusUpdate = { [weak self] response in
            self?.handleFirmwareUpdate(response)
        }

        bluetoothManager.onLoRaCommand = { [weak self] loraCmd in
            self?.handleLoRaCommand(loraCmd)
        }
    }

    // MARK: - WiFi 指揮中心連線

    private func setupWiFiClient() {
        commandClient.onCommand = { [weak self] wifiCmd in
            self?.handleWiFiCommand(wifiCmd)
        }
        commandClient.onChatMessage = { [weak self] chat in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.chatMessages.contains(where: { $0.id == chat.id }) {
                    self.chatMessages.append(chat)
                    if self.chatMessages.count > 200 {
                        self.chatMessages = Array(self.chatMessages.suffix(200))
                    }
                    // 自動送出已讀回條（非自己發送的訊息）
                    if chat.senderID != self.nodeStatus.nodeID {
                        self.commandClient.sendChatReadReceipt(messageIds: [chat.id])
                        self.appendActivity(kind: .receivedMessage,
                                            title: chat.senderName,
                                            detail: chat.content,
                                            timestamp: Date(timeIntervalSince1970: chat.timestamp))
                    }
                }
            }
        }
        commandClient.onChatReadStatus = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                if let msgId = json["message_id"] as? String,
                   let readCount = json["read_count"] as? Int {
                    self.chatReadCounts[msgId] = readCount
                }
            }
        }
        commandClient.onDisasterUpdate = { [weak self] site in
            DispatchQueue.main.async {
                guard let self else { return }
                self.disasterSite = site
                self.appendActivity(kind: .command, title: L("收到災情更新"), detail: site.buildingName)
            }
        }
        commandClient.onPatientIDConfig = { [weak self] config in
            DispatchQueue.main.async {
                self?.applyPatientIDConfig(config)
            }
        }
        commandClient.onPersonnelAssignment = { [weak self] assignments in
            DispatchQueue.main.async {
                guard let self else { return }
                self.personnelAssignments = assignments
                self.appendActivity(kind: .task, title: L("收到人員配置更新"), detail: L("%lld 筆", assignments.count))
            }
        }
        commandClient.onPWSAlert = { [weak self] alert in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pwsAlerts.insert(alert, at: 0)
                if self.pwsAlerts.count > 100 { self.pwsAlerts = Array(self.pwsAlerts.prefix(100)) }
                if alert.isActive && self.pastStartupGrace {
                    NotificationManager.shared.sendPWSAlertNotification(alert: alert)
                }
                self.appendActivity(kind: .pwsAlert, title: alert.title, detail: alert.content)
            }
        }
        commandClient.onBriefing = { [weak self] briefing in
            DispatchQueue.main.async {
                guard let self else { return }
                self.briefings.insert(briefing, at: 0)
                if self.briefings.count > 50 { self.briefings = Array(self.briefings.prefix(50)) }
                self.appendActivity(kind: .briefing, title: briefing.title, detail: "by \(briefing.author)")
            }
        }
        commandClient.onEscalationTrigger = { [weak self] json in
            DispatchQueue.main.async {
                self?.escalationTriggerPublisher.send(json)
            }
        }
        commandClient.onPersonalNotification = { [weak self] notification in
            DispatchQueue.main.async {
                guard let self else { return }
                var isNewNotification = false
                if let index = self.personalNotifications.firstIndex(where: { $0.id == notification.id }) {
                    self.personalNotifications[index] = notification
                } else {
                    isNewNotification = true
                    self.personalNotifications.insert(notification, at: 0)
                    self.unreadNotificationCount += 1
                }
                if self.personalNotifications.count > 100 { self.personalNotifications = Array(self.personalNotifications.prefix(100)) }
                if isNewNotification && self.pastStartupGrace {
                    NotificationManager.shared.sendPersonalNotification(notification)
                }
                self.appendActivity(
                    kind: .personalNotification,
                    title: "\(L("指揮中心通知")): \(notification.title)",
                    detail: notification.content,
                    timestamp: Date(timeIntervalSince1970: notification.timestamp),
                    id: "personal-\(notification.id)"
                )
            }
        }
        commandClient.onQuickStatus = { [weak self] qs in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.quickStatuses.contains(where: { $0.id == qs.id }) {
                    self.quickStatuses.insert(qs, at: 0)
                    if self.quickStatuses.count > 100 { self.quickStatuses = Array(self.quickStatuses.prefix(100)) }
                }
            }
        }
        commandClient.onTaskAssignment = { [weak self] task in
            DispatchQueue.main.async {
                guard let self else { return }
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx] = task
                } else {
                    self.tasks.insert(task, at: 0)
                }
                self.appendActivity(kind: .task, title: L("收到任務指派"), detail: task.title)
            }
        }
        commandClient.onTimerSync = { [weak self] timer in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.countdownTimers.contains(where: { $0.id == timer.id }) {
                    self.countdownTimers.append(timer)
                    self.startCountdownRefresh()
                    self.appendActivity(kind: .timer, title: L("收到倒數計時"), detail: timer.title)
                }
            }
        }
        commandClient.onTimerCancel = { [weak self] timerID in
            DispatchQueue.main.async {
                self?.countdownTimers.removeAll { $0.id == timerID }
                self?.appendActivity(kind: .timer, title: L("倒數計時取消"), detail: timerID)
            }
        }
        commandClient.onHazardReport = { [weak self] hazard in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.hazardReports.contains(where: { $0.id == hazard.id }) {
                    self.hazardReports.insert(hazard, at: 0)
                    if self.hazardReports.count > 100 { self.hazardReports = Array(self.hazardReports.prefix(100)) }
                    self.appendActivity(kind: .hazard, title: L("危險標記"), detail: hazard.description)
                }
            }
        }
        commandClient.onReinforcementRequest = { [weak self] request in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.reinforcementRequests.contains(where: { $0.id == request.id }) {
                    self.reinforcementRequests.insert(request, at: 0)
                    if self.reinforcementRequests.count > 50 { self.reinforcementRequests = Array(self.reinforcementRequests.prefix(50)) }
                    self.handleIncomingReinforcement(from: request.fromTeam, message: request.message, location: request.location)
                }
            }
        }
        commandClient.onReinforcementReply = { [weak self] reply in
            DispatchQueue.main.async {
                guard let self else { return }
                if let idx = self.reinforcementRequests.firstIndex(where: { $0.id == reply.id }) {
                    self.reinforcementRequests[idx] = reply
                }
                self.appendActivity(kind: .reinforcement, title: L("收到增援回覆"), detail: "\(reply.fromTeam) · \(reply.status.rawValue)")
            }
        }
        commandClient.onDecision = { [weak self] decision in
            DispatchQueue.main.async {
                guard let self else { return }
                // 同 request_id 的後續更新 → in-place replace（避免重複堆疊轉介中/最終決策兩條 record）
                if let rid = decision.requestId, !rid.isEmpty,
                   let idx = self.decisions.firstIndex(where: { $0.requestId == rid }) {
                    self.decisions[idx] = decision
                } else {
                    self.decisions.insert(decision, at: 0)
                    if self.decisions.count > 100 {
                        self.decisions = Array(self.decisions.prefix(100))
                    }
                    // 只為新決策記錄活動（更新不重複記錄）
                    let summary = String(decision.decision.prefix(60))
                    self.appendActivity(kind: .hqDecision, title: L("HQ 決策"), detail: summary)
                }
                // 啟動靜默期內只記錄不推播
                guard self.pastStartupGrace == true else { return }
                // provisional / queued 狀態不推播通知（避免吵雜），最終決策才推
                if decision.provisional == false || decision.escalationStatus == "done" {
                    NotificationManager.shared.sendDecisionNotification(decision: decision)
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    #endif
                }
            }
        }
        commandClient.onReportSummary = { [weak self] summary in
            DispatchQueue.main.async {
                guard let self else { return }
                let report = RadioReport(
                    senderName: summary.senderName,
                    transcription: summary.transcription,
                    location: summary.locationDesc,
                    reportId: summary.reportId,
                    patientsCount: summary.patientsCount,
                    audioUrl: summary.audioUrl ?? "",
                    weather: summary.weather
                )
                self.radioReports.insert(report, at: 0)
                if self.radioReports.count > 50 { self.radioReports = Array(self.radioReports.prefix(50)) }
                self.appendActivity(kind: .briefing, title: L("收到電台會報"), detail: summary.transcription)

                // 自動播放收到的電台音訊（尊重 autoPlay 設定）
                if self.autoPlayRadio,
                   let audioUrlStr = summary.audioUrl, !audioUrlStr.isEmpty,
                   let audioURL = URL(string: audioUrlStr) {
                    // 不播放自己發送的音訊
                    if summary.senderName != self.nodeStatus.nodeID {
                        self.playRadioAudio(from: audioURL, reportId: report.reportId)
                    }
                }

                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            }
        }
        commandClient.onRadioControl = { [weak self] ctrl in
            DispatchQueue.main.async {
                self?.currentBroadcaster = ctrl.action == "start" ? ctrl.senderName : nil
            }
        }
        commandClient.onPhotoReport = { [weak self] photo in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.photoReports.contains(where: { $0.id == photo.id }) {
                    self.photoReports.insert(photo, at: 0)
                    if self.photoReports.count > 100 { self.photoReports = Array(self.photoReports.prefix(100)) }
                }
            }
        }
        // MARK: - 規範補齊：下行 msgType 回呼
        commandClient.onTextBroadcastRx = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let broadcastId = json["broadcast_id"] as? String ?? UUID().uuidString
                let message = json["message"] as? String ?? ""
                let senderName = json["sender_name"] as? String ?? ""
                let priority = json["priority"] as? String ?? "normal"
                let broadcast = TextBroadcast(
                    id: broadcastId,
                    broadcastId: broadcastId,
                    message: message,
                    senderName: senderName,
                    priority: priority,
                    timestamp: Date()
                )
                self.textBroadcasts.insert(broadcast, at: 0)
                if self.textBroadcasts.count > 100 { self.textBroadcasts = Array(self.textBroadcasts.prefix(100)) }
                if priority == "urgent" && self.pastStartupGrace {
                    self.urgentBroadcast = broadcast
                    NotificationManager.shared.sendUrgentBroadcastNotification(broadcast: broadcast)
                }
                self.appendActivity(kind: .broadcast, title: "\(senderName) \(L("廣播"))", detail: message)
                // 自動回覆已讀回條
                self.commandClient.sendMessageAck(messageId: broadcastId, messageType: "text_broadcast")
            }
        }
        commandClient.onReadStatus = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let broadcastId = json["broadcast_id"] as? String ?? ""
                let total = json["total"] as? Int ?? 0
                let readCount = json["read_count"] as? Int ?? 0
                self.readStatuses[broadcastId] = (total: total, readCount: readCount)
            }
        }
        commandClient.onSOSAlert = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let data = json["data"] as? [String: Any] ?? json
                let sosId = data["sos_id"] as? String ?? data["id"] as? String ?? ""
                let senderName = data["sender_name"] as? String ?? data["senderName"] as? String ?? L("未知")
                let deviceId = data["device_id"] as? String ?? data["deviceID"] as? String ?? ""
                let message = data["message"] as? String ?? data["msg"] as? String ?? ""
                let locationDescription = data["location_desc"] as? String
                    ?? data["locationDescription"] as? String
                    ?? data["location"] as? String
                    ?? ""
                let latitude = Self.doubleValue(from: data["lat"] ?? data["latitude"])
                let longitude = Self.doubleValue(from: data["lon"] ?? data["lng"] ?? data["longitude"])
                // 加入 SOS 記錄 
                let record = SOSRecord(
                    id: UUID(),
                    sosID: sosId,
                    victimID: deviceId.isEmpty ? senderName : deviceId,
                    senderName: senderName,
                    message: message,
                    locationDescription: locationDescription,
                    latitude: latitude,
                    longitude: longitude,
                    heartRate: 0,
                    rssi: 0,
                    distance: L("未知"),
                    battery: 0,
                    time: Date(),
                    isAcknowledged: false
                )
                self.sosRecords.insert(record, at: 0)
                if self.sosRecords.count > 100 { self.sosRecords = Array(self.sosRecords.prefix(100)) }
                self.appendActivity(kind: .sos, title: "SOS: \(senderName)", detail: message.isEmpty ? locationDescription : message)
                // 啟動靜默期內只記錄不彈警報，避免歷史同步灌爆
                guard self.pastStartupGrace else { return }
                // 建立臨時 VictimNode 觸發全螢幕 SOS 覆蓋
                let victim = VictimNode(
                    id: senderName,
                    heartRate: 0, battery: 0, rssi: 0, snr: 0,
                    isSOS: true, lastSeen: Date(), isOnline: true
                )
                self.triggerSOSNotification(for: victim)
            }
        }
        commandClient.onSOSCancelAlert = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let data = json["data"] as? [String: Any] ?? json
                let sosId = data["sos_id"] as? String ?? ""
                let deviceId = data["device_id"] as? String ?? data["deviceID"] as? String ?? ""
                // 標記對應 SOS 為已確認
                if let idx = self.sosRecords.firstIndex(where: {
                    (!$0.isAcknowledged) && (
                        (!sosId.isEmpty && $0.sosID == sosId) ||
                        (!deviceId.isEmpty && $0.victimID == deviceId) ||
                        (deviceId.isEmpty && !sosId.isEmpty && $0.victimID == sosId)
                    )
                }) {
                    self.sosRecords[idx].isAcknowledged = true
                }
                AlarmPlayer.shared.stopAlarm()
            }
        }
        commandClient.onPatientWarning = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let warning = PatientWarning(
                    patientId: json["patient_id"] as? String ?? "",
                    priority: json["priority"] as? String ?? json["triage_level"] as? String ?? "",
                    location: json["location"] as? String ?? "",
                    minutesSinceTriage: json["minutes_since_triage"] as? Int ?? 0,
                    warningLevel: json["warning_level"] as? String ?? "medium",
                    message: json["warning_message"] as? String ?? json["message"] as? String ?? "",
                    timestamp: Date()
                )
                self.patientWarnings.insert(warning, at: 0)
                if self.patientWarnings.count > 100 { self.patientWarnings = Array(self.patientWarnings.prefix(100)) }
                self.appendActivity(kind: .patientWarning, title: "\(L("收到傷患預警")): \(warning.patientId)", detail: warning.message)
                // 啟動靜默期內只記錄不彈警報
                guard self.pastStartupGrace else { return }
                self.activePatientWarning = warning
                NotificationManager.shared.sendPatientWarningNotification(warning: warning)
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                #endif
            }
        }
        commandClient.onStatsUpdate = { [weak self] json in
            DispatchQueue.main.async {
                self?.latestStats = json
            }
        }
        commandClient.onResourceUpdate = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data = try? JSONSerialization.data(withJSONObject: json),
                   let resource = try? JSONDecoder().decode(ResourceStatus.self, from: data) {
                    self.resourceStatus = resource
                }
            }
        }
        commandClient.onTranslateResult = { [weak self] json in
            DispatchQueue.main.async {
                guard let self else { return }
                let payload = json["data"] as? [String: Any] ?? json
                let translated = payload["translated"] as? String ?? payload["result"] as? String ?? ""
                let engine = payload["engine"] as? String ?? ""
                if translated.isEmpty || engine == "local_fallback" || translated.hasPrefix("[LOCAL ") || translated.hasPrefix("[本地翻譯]") {
                    return
                }
                let result = TranslationResult(
                    original: payload["original"] as? String ?? payload["text"] as? String ?? "",
                    translated: translated,
                    detectedLang: payload["detected_lang"] as? String ?? payload["source_lang"] as? String ?? "auto",
                    targetLang: payload["target_lang"] as? String ?? "en"
                )
                self.latestTranslation = result
                self.isTranslating = false
            }
        }
        // 自動搜尋指揮中心
        commandClient.startBrowsing()

        // 定期回報狀態給指揮中心（每 30 秒，省電優化：含差異上報）
        statusReportTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendStatusReport()
            }
        }

        // 定期回報 GPS 位置（每 30 秒，省電優化：降精度+靜止偵測）
        locationDelegate.onLocationUpdate = { [weak self] in
            Task { @MainActor in
                guard let self, self.isStationaryMode else { return }
                self.sendLocationUpdate()
            }
        }
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.startUpdatingLocation()
        locationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendLocationUpdate()
            }
        }
    }

    private func setupAppLifecycleRecovery() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.prepareForForegroundResume()
                self?.resumeRealtimeConnectionsAfterForeground()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sendStatusReport()
            }
            .store(in: &cancellables)
        #endif
    }

    private func suppressRealtimeAlarms(for duration: TimeInterval? = nil) {
        let until = Date().addingTimeInterval(duration ?? startupGracePeriod)
        if until > alarmSuppressionUntil {
            alarmSuppressionUntil = until
        }
    }

    private func prepareForForegroundResume() {
        suppressRealtimeAlarms()
        clearTransientAlarmPresentations()
    }

    private func clearTransientAlarmPresentations() {
        sosAutoDowngradeTimer?.invalidate()
        sosAutoDowngradeTimer = nil
        latestSOSVictim = nil
        latestCriticalCommand = nil
        latestReinforcementRequest = nil
        urgentBroadcast = nil
        activePatientWarning = nil
        AlarmPlayer.shared.stopAlarm()
        stopCriticalHaptics()
    }

    private func resumeRealtimeConnectionsAfterForeground() {
        GlobalRadioListener.shared.activate()
        if !commandClient.isConnected {
            commandClient.startBrowsing()
        }
    }

    private func handleWiFiCommand(_ wifiCmd: WiFiCommand) {
        let order = wifiCmd.toCommandOrder()

        // 去重
        guard !commandOrders.contains(where: { $0.id == order.id }) else { return }

        commandOrders.insert(order, at: 0)
        if commandOrders.count > 100 { commandOrders = Array(commandOrders.prefix(100)) }
        appendActivity(kind: .command, title: "\(L("收到命令")): \(order.title)", detail: order.detail, timestamp: order.time)

        // 啟動靜默期內只記錄不彈警報
        guard pastStartupGrace else { return }
        NotificationManager.shared.sendCommandNotification(order: order)

        if order.priority == .critical {
            latestCriticalCommand = order
            AlarmPlayer.shared.playAlarm()
            startCriticalHaptics()
        }
    }

    /// 定期回報狀態給指揮中心（省電：差異上報，無變化則跳過）
    private func sendStatusReport() {
        guard commandClient.isConnected else { return }

        // 差異偵測：電量變化<5% && BLE 不變 && victims/SOS 不變 → 跳過
        let currentBattery = effectiveBattery
        let currentBLE = isBluetoothConnected
        let currentVictimCount = victims.count
        let currentSOSCount = sosVictimCount
        if lastReportedBattery >= 0,
           abs(currentBattery - lastReportedBattery) < 5,
           lastReportedBLE == currentBLE,
           lastReportedVictimCount == currentVictimCount,
           lastReportedSOSCount == currentSOSCount {
            return
        }
        lastReportedBattery = currentBattery
        lastReportedBLE = currentBLE
        lastReportedVictimCount = currentVictimCount
        lastReportedSOSCount = currentSOSCount

        let victimSummaries = victims.map { v in
            VictimSummary(id: v.id, heartRate: v.heartRate, battery: v.battery,
                          rssi: v.rssi, isSOS: v.isSOS, isOnline: v.isOnline)
        }
        let teamSummaries = teamMembers.map { t in
            TeamSummary(id: t.id, deptCode: t.deptCode, battery: t.battery,
                        rssi: t.rssi, isOnline: t.isOnline, victimCount: t.victimCount)
        }

        // 自身作為救援人員
        let trimmedNickname = userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let selfP = PersonnelAssignment(
            id: "field-\(nodeStatus.nodeID)",
            name: nodeStatus.nodeID,
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            assignedZone: "",
            assignedFloor: "",
            role: .rescue
        )

        let report = FieldStatusReport(
            deviceID: nodeStatus.nodeID,
            deptCode: nodeStatus.deptCode,
            battery: effectiveBattery,
            bleConnected: isBluetoothConnected,
            victims: victimSummaries,
            teamMembers: teamSummaries,
            sosCount: sosVictimCount,
            timestamp: Date().timeIntervalSince1970,
            selfPersonnel: selfP
        )

        commandClient.sendStatusReport(report)
    }

    /// 定期回報 GPS 位置（省電：靜止偵測，移動時 30s，靜止時 60s）
    private func sendLocationUpdate() {
        guard commandClient.isConnected,
              let loc = locationManager.location else { return }

        // 靜止偵測：與上次 < 10m → 計數+1，連續 3 次 → 降頻到 60s
        if let lastLoc = lastReportedLocation {
            let distance = loc.distance(from: lastLoc)
            if distance < Self.stationaryThresholdMeters {
                stationaryCount += 1
                if stationaryCount >= Self.stationaryCountThreshold {
                    // 靜止狀態：降頻 + 停止持續定位
                    if !isStationaryMode {
                        isStationaryMode = true
                        locationTimer?.invalidate()
                        locationManager.stopUpdatingLocation()
                        locationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                            Task { @MainActor in
                                self?.locationManager.requestLocation()
                                // didUpdateLocations 回呼會觸發 sendLocationUpdate()
                            }
                        }
                    }
                    return  // 靜止中不上報
                }
            } else {
                // 移動偵測：恢復 30s + 持續定位
                if isStationaryMode {
                    isStationaryMode = false
                    locationTimer?.invalidate()
                    locationManager.pausesLocationUpdatesAutomatically = true
                    locationManager.startUpdatingLocation()
                    locationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            self?.sendLocationUpdate()
                        }
                    }
                }
                stationaryCount = 0
            }
        }
        lastReportedLocation = loc
        #if canImport(UIKit)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? nodeStatus.nodeID
        #else
        let deviceID = nodeStatus.nodeID
        #endif
        commandClient.sendLocation(
            deviceID: deviceID,
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy,
            role: nodeStatus.deptCode,
            name: nodeStatus.nodeID,
            nickname: userNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func syncNFCTagWrite(patientId: String, payload: String, tagCapacity: Int, payloadLength: Int) {
        guard commandClient.isConnected else { return }
        let compactID = PatientIDConfig.extractCompactID(from: patientId) ?? patientId.uppercased().filter { $0.isLetter || $0.isNumber }
        let format = payload.components(separatedBy: "|").first ?? "NFC"
        let sender = userNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nodeStatus.nodeID
            : userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = NFCTagWriteRecord(
            id: UUID().uuidString,
            patientId: patientId,
            compactPatientId: compactID,
            format: format,
            payload: payload,
            tagCapacity: tagCapacity,
            payloadLength: payloadLength,
            deviceID: nodeStatus.nodeID,
            senderName: sender,
            timestamp: Date().timeIntervalSince1970
        )
        commandClient.sendNFCTagWritten(record)
        appendActivity(kind: .patientReport, title: L("NFC 標籤已同步 HQ"), detail: "\(format) · \(compactID)")
    }

    // MARK: - 電台音訊播放

    /// 下載並播放收到的電台音訊（供 UI 手動呼叫或自動播放）
    func playRadioAudio(from url: URL, reportId: String = "") {
        // 如果正在播放同一則，停止
        if playingReportId == reportId, radioAudioPlayer?.isPlaying == true {
            radioAudioPlayer?.stop()
            playingReportId = nil
            return
        }
        playingReportId = reportId
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    print("[ViewModel] ❌ Radio audio download failed")
                    playingReportId = nil
                    return
                }
                #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                #endif
                radioAudioPlayer = try AVAudioPlayer(data: data)
                radioAudioPlayer?.play()
                print("[ViewModel] ▶️ Playing radio audio (\(data.count) bytes)")
                // 播放結束後清除狀態
                let duration = radioAudioPlayer?.duration ?? 0
                if duration > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) { [weak self] in
                        if self?.playingReportId == reportId {
                            self?.playingReportId = nil
                        }
                    }
                }
            } catch {
                print("[ViewModel] ❌ Radio audio play error: \(error)")
                playingReportId = nil
            }
        }
    }

    /// 從 RadioReport 手動播放音訊
    func playReportAudio(_ report: RadioReport) {
        guard !report.audioUrl.isEmpty, let url = URL(string: report.audioUrl) else { return }
        playRadioAudio(from: url, reportId: report.reportId)
    }

    // MARK: - LoRa 指揮命令處理

    /// 處理從韌體 BLE 轉發的 LoRa 指揮命令
    private func handleLoRaCommand(_ loraCmd: FirmwareLoRaCommand) {
        // 防止重複（用 cmd_id 去重）
        let cmdUUID = UUID(uuidString: loraCmd.cmd_id) ?? UUID()
        guard !commandOrders.contains(where: { $0.id == cmdUUID }) else { return }

        let order = loraCmd.toCommandOrder()
        commandOrders.insert(order, at: 0)

        // 發送回執通知韌體
        bluetoothManager.sendCommandAck(loraCmd.cmd_id)

        // 本地通知（啟動靜默期內不推播）
        if pastStartupGrace {
            NotificationManager.shared.sendCommandNotification(order: order)
        }

        // Critical 命令：全螢幕覆蓋 + 持續震動 + 警報音
        // 只在 App 開啟後收到的新命令才彈出全螢幕通知，避免啟動時的歷史同步觸發
        if order.priority == .critical && pastStartupGrace {
            latestCriticalCommand = order
            DispatchQueue.main.async {
                AlarmPlayer.shared.playAlarm()
            }
            startCriticalHaptics()
        }
    }

    // MARK: - 韌體資料處理（BLE Notify 或 WiFi /up）

    private func handleFirmwareUpdate(_ response: FirmwareStatusResponse) {
        // 更新節點自身狀態
        if let id = response.id, !id.isEmpty {
            nodeStatus.nodeID = id
        }
        if let dept = response.dept, !dept.isEmpty {
            nodeStatus.deptCode = dept
        }
        nodeStatus.battery = response.bat
        if let vbat = response.vbat { nodeStatus.voltage = vbat }
        nodeStatus.loraLevel = response.lvl
        if let pair = response.pair {
            nodeStatus.pairCode = pair
        }

        // 更新受困者列表
        let now = Date()
        for fv in response.victims {
            // 從 RSSI 估算距離文字（Arduino 不再送 dist 以節省 BLE 頻寬）
            let distText: String = {
                let n = 2.7, A = -30.0
                let d = pow(10.0, (A - fv.rssi) / (10.0 * n))
                if d < 0.1  { return "<0.1m" }
                if d < 10   { return String(format: "%.1fm", d) }
                if d < 1000 { return "\(Int(d))m" }
                return String(format: "%.1fkm", d / 1000)
            }()
            if let idx = victims.firstIndex(where: { $0.id == fv.id }) {
                victims[idx].heartRate = fv.hr
                victims[idx].battery = fv.bat
                victims[idx].rssi = fv.rssi
                if let snr = fv.snr { victims[idx].snr = snr }
                victims[idx].isSOS = fv.sos
                // 新的 SOS 產生紀錄（過濾已確認過的受困者與近期紀錄）
                let alreadyKnownSOS = sosRecords.contains { 
                    $0.victimID == fv.id && ($0.isAcknowledged || now.timeIntervalSince($0.time) < 30)
                }
                
                if fv.sos && !alreadyKnownSOS {
                    let record = SOSRecord(
                        id: UUID(), victimID: fv.id, heartRate: fv.hr,
                        rssi: fv.rssi, distance: distText, battery: fv.bat,
                        time: now, isAcknowledged: false
                    )
                    sosRecords.insert(record, at: 0)
                    
                    // 只在 App 開啟後產生的新警報才彈出全螢幕通知
                    // 如果是在開啟 App 前就有的（同步過來的舊 SOS），則只記錄在名單但不跳通知
                    if pastStartupGrace {
                        triggerSOSNotification(for: victims[idx])
                    }
                }
            } else {
                // 新發現的受困者
                let victim = VictimNode(
                    id: fv.id, heartRate: fv.hr, battery: fv.bat,
                    rssi: fv.rssi, snr: fv.snr ?? 0, isSOS: fv.sos,
                    lastSeen: now, isOnline: fv.online
                )
                victims.append(victim)
                
                // 初次發現且為 SOS，同樣檢查是否已經有紀錄
                let alreadyKnownSOS = sosRecords.contains { $0.victimID == fv.id }
                
                if fv.sos && !alreadyKnownSOS {
                    let record = SOSRecord(
                        id: UUID(), victimID: fv.id, heartRate: fv.hr,
                        rssi: fv.rssi, distance: distText, battery: fv.bat,
                        time: now, isAcknowledged: false
                    )
                    sosRecords.insert(record, at: 0)
                    
                    if pastStartupGrace {
                        triggerSOSNotification(for: victim)
                    }
                }
            }
        }

        // 移除韌體已清除的受困者（120 秒超時）
        let firmwareIDs = Set(response.victims.map(\.id))
        victims.removeAll { !firmwareIDs.contains($0.id) }

        // 更新團隊成員（來自 BLE JSON 的 team 陣列）
        if let fwTeam = response.team {
            for ft in fwTeam {
                if let idx = teamMembers.firstIndex(where: { $0.id == ft.id }) {
                    teamMembers[idx].deptCode = ft.dept
                    teamMembers[idx].battery = ft.bat
                    teamMembers[idx].rssi = ft.rssi
                    teamMembers[idx].victimCount = ft.vc
                    teamMembers[idx].isOnline = ft.online
                    if ft.online { teamMembers[idx].lastSeen = now }
                } else {
                    teamMembers.append(TeamMember(
                        id: ft.id, deptCode: ft.dept, battery: ft.bat,
                        rssi: ft.rssi, lastSeen: now,
                        isOnline: ft.online, victimCount: ft.vc
                    ))
                }
            }
            // 移除韌體已清除的團隊節點
            let fwTeamIDs = Set(fwTeam.map(\.id))
            teamMembers.removeAll { !fwTeamIDs.contains($0.id) }
        }

        // 更新增援請求（來自 BLE JSON 的 rf 陣列）
        if let fwRF = response.rf {
            for fr in fwRF {
                // 檢查是否已存在（用 fromTeam + message 去重）
                if !reinforcementRequests.contains(where: {
                    $0.fromTeam == fr.from && $0.message == fr.msg
                }) {
                    handleIncomingReinforcement(from: fr.from, message: fr.msg, location: fr.loc)
                }
            }
        }
    }

    // MARK: - 模擬模式（Demo 用）

    func toggleSimulation() {
        isSimulating ? stopSimulation() : startSimulation()
    }

    func startSimulation() {
        isSimulating = true
        // 載入初始模擬資料
        if victims.isEmpty {
            victims = simulation.createInitialVictims()
            nodeStatus = simulation.createInitialNodeStatus()
            sosRecords = simulation.createInitialSOSRecords()
        }
        // 模擬團隊成員
        if teamMembers.isEmpty {
            teamMembers = [
                TeamMember(id: "RT-B7E-FD", deptCode: "FD", battery: 88, rssi: -62,
                           lastSeen: Date(), isOnline: true, victimCount: 3),
                TeamMember(id: "RT-C4A-EMT", deptCode: "EMT", battery: 72, rssi: -78,
                           lastSeen: Date(), isOnline: true, victimCount: 2),
                TeamMember(id: "RT-D91-PD", deptCode: "PD", battery: 45, rssi: -91,
                           lastSeen: Date().addingTimeInterval(-60), isOnline: false, victimCount: 0),
            ]
        }
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.simulationTick()
            }
        }
        startCommandEngine()
    }

    func stopSimulation() {
        isSimulating = false
        simulationTimer?.invalidate()
        simulationTimer = nil
        if !isWiFiCommandMode {
            stopCommandEngine()
        }
    }

    // MARK: - WiFi 命令模式（透過 NTP 時間同步，所有連同一 WiFi 的裝置自動收到相同命令）

    func toggleWiFiCommandMode() {
        isWiFiCommandMode ? stopWiFiCommandMode() : startWiFiCommandMode()
    }

    func startWiFiCommandMode() {
        isWiFiCommandMode = true
        if commandTimer == nil {
            startCommandEngine()
        }
    }

    func stopWiFiCommandMode() {
        isWiFiCommandMode = false
        if !isSimulating {
            stopCommandEngine()
        }
    }

    private static func doubleValue(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func simulationTick() {
        simulation.updateVictimSignals(&victims)
        simulation.updateVictimOnlineStatus(&victims)
        simulation.updateNodeStatus(&nodeStatus)

        // 離線/低電量通知
        for victim in victims {
            let wasOnline = previousOnlineStates[victim.id] ?? victim.isOnline
            if wasOnline && !victim.isOnline && pastStartupGrace {
                NotificationManager.shared.sendOfflineNotification(victimID: victim.id)
                appendActivity(kind: .deviceAlert, title: L("裝置離線"), detail: victim.id)
            }
            previousOnlineStates[victim.id] = victim.isOnline

            if victim.battery <= 15 && !lowBatteryNotified.contains(victim.id) {
                lowBatteryNotified.insert(victim.id)
                if pastStartupGrace {
                    NotificationManager.shared.sendLowBatteryNotification(
                        victimID: victim.id, battery: victim.battery
                    )
                    appendActivity(kind: .deviceAlert, title: L("低電量警告"), detail: "\(victim.id) · \(victim.battery)%")
                }
            }
        }

        if let newVictim = simulation.maybeDiscoverNewVictim(existing: victims) {
            victims.append(newVictim)
            if newVictim.isSOS {
                let record = SOSRecord(
                    id: UUID(), victimID: newVictim.id, heartRate: newVictim.heartRate,
                    rssi: newVictim.rssi, distance: newVictim.distanceText,
                    battery: newVictim.battery, time: Date(), isAcknowledged: false
                )
                sosRecords.insert(record, at: 0)
                appendActivity(kind: .sos, title: "SOS: \(newVictim.id)", detail: newVictim.distanceText)
                triggerSOSNotification(for: newVictim)
            }
        }

        if let sosRecord = simulation.maybeToggleSOS(&victims) {
            sosRecords.insert(sosRecord, at: 0)
            appendActivity(kind: .sos, title: "SOS: \(sosRecord.victimID)", detail: sosRecord.distance)
            if let v = victims.first(where: { $0.id == sosRecord.victimID }) {
                triggerSOSNotification(for: v)
            }
        }
    }

    // MARK: - 使用者操作

    /// 確認 SOS 紀錄
    func acknowledgeRecord(_ record: SOSRecord) {
        if let idx = sosRecords.firstIndex(where: { $0.id == record.id }) {
            sosRecords[idx].isAcknowledged = true
        }
    }

    /// 修改部門碼（持久化）
    func changeDeptCode(_ dept: String) {
        let d = dept.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard d.count >= 1, d.count <= 3 else { return }
        nodeStatus.deptCode = d
        UserDefaults.standard.set(d, forKey: "linkguard_dept_code")
        if isBluetoothConnected {
            bluetoothManager.sendDeptChange(d)
        }
    }

    /// 修改節點 ID（持久化）
    func changeNodeID(_ newID: String) {
        let id = newID.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 10 else { return }
        nodeStatus.nodeID = id
        UserDefaults.standard.set(id, forKey: "linkguard_custom_node_id")
    }

    /// 修改使用者暱稱（持久化，留空代表清除）
    func changeUserNickname(_ nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        userNickname = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: "linkguard_user_nickname")
        } else {
            UserDefaults.standard.set(trimmed, forKey: "linkguard_user_nickname")
        }
        // 重置上報基準，下一輪 status_report 會帶上新暱稱
        lastReportedBattery = -1
    }

    /// 修改 LoRa 檔位
    func changeLoRaLevel(_ level: Int) {
        let l = max(0, min(8, level))
        nodeStatus.loraLevel = l
        if isBluetoothConnected {
            bluetoothManager.sendLevelChange(l)
        }
    }

    /// 修改配對碼
    func changePairCode(_ code: String) {
        let c = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count >= 1, c.count <= 8 else { return }
        nodeStatus.pairCode = c
        if isBluetoothConnected {
            bluetoothManager.sendPairChange(c)
        }
    }

    /// 掃描藍牙裝置
    func scanForDevices() {
        bluetoothManager.startScanning()
    }

    /// 停止掃描
    func stopScanning() {
        bluetoothManager.stopScanning()
    }

    /// 連接指定裝置
    func connectToDevice(_ device: DiscoveredDevice) {
        bluetoothManager.connect(to: device)
    }

    /// 斷開連線
    func disconnectDevice() {
        bluetoothManager.disconnect()
    }

    // MARK: - 增援系統

    /// 發送增援請求（透過 BLE → LoRa 廣播）
    func sendReinforcementRequest(message: String, location: String) {
        let request = ReinforcementRequest(
            id: UUID(), fromTeam: nodeStatus.nodeID,
            message: message, location: location,
            time: Date(), status: .pending,
            respondedBy: [], isFromSelf: true
        )
        reinforcementRequests.insert(request, at: 0)
        appendActivity(kind: .reinforcement, title: L("已送出增援請求"), detail: message.isEmpty ? location : message)
        // WiFi 優先
        if commandClient.isConnected {
            commandClient.sendReinforcementRequest(request)
        }
        // BLE 備援
        if isBluetoothConnected {
            bluetoothManager.sendReinforcement(message: message, location: location)
        }
    }

    /// 回覆增援請求：加入
    func acceptReinforcement(_ request: ReinforcementRequest) {
        if let idx = reinforcementRequests.firstIndex(where: { $0.id == request.id }) {
            reinforcementRequests[idx].status = .accepted
            reinforcementRequests[idx].respondedBy.append(nodeStatus.nodeID)
            appendActivity(kind: .reinforcement, title: L("已接受增援請求"), detail: request.message)
            // WiFi 優先
            if commandClient.isConnected {
                commandClient.sendReinforcementReply(reinforcementRequests[idx])
            }
        }
        latestReinforcementRequest = nil
        // BLE 備援
        if isBluetoothConnected {
            bluetoothManager.sendReinforcementReply(to: request.fromTeam, accept: true)
        }
    }

    /// 回覆增援請求：拒絕
    func declineReinforcement(_ request: ReinforcementRequest) {
        if let idx = reinforcementRequests.firstIndex(where: { $0.id == request.id }) {
            reinforcementRequests[idx].status = .declined
            appendActivity(kind: .reinforcement, title: L("已拒絕增援請求"), detail: request.message)
            // WiFi 優先
            if commandClient.isConnected {
                commandClient.sendReinforcementReply(reinforcementRequests[idx])
            }
        }
        latestReinforcementRequest = nil
        // BLE 備援
        if isBluetoothConnected {
            bluetoothManager.sendReinforcementReply(to: request.fromTeam, accept: false)
        }
    }

    /// 收到增援請求（由 BLE 回呼觸發）
    func handleIncomingReinforcement(from team: String, message: String, location: String) {
        let request = ReinforcementRequest(
            id: UUID(), fromTeam: team,
            message: message, location: location,
            time: Date(), status: .pending,
            respondedBy: [], isFromSelf: false
        )
        reinforcementRequests.insert(request, at: 0)
        appendActivity(kind: .reinforcement, title: "\(L("收到增援請求")): \(team)", detail: message)
        // 啟動靜默期內只記錄不彈警報
        guard pastStartupGrace else { return }
        latestReinforcementRequest = request
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
        AlarmPlayer.shared.playAlarm()
    }

    /// 收到增援回覆
    func handleReinforcementReply(from team: String, accepted: Bool) {
        // 更新自己發出的增援請求
        if let idx = reinforcementRequests.firstIndex(where: {
            $0.isFromSelf && $0.status == .pending
        }) {
            reinforcementRequests[idx].respondedBy.append(team)
            if accepted {
                reinforcementRequests[idx].status = .accepted
            }
            appendActivity(kind: .reinforcement, title: L("收到增援回覆"), detail: "\(team) · \(accepted ? L("已接受") : L("已拒絕"))")
        }
    }

    /// 關閉增援警報覆蓋層
    func dismissReinforcementAlert() {
        latestReinforcementRequest = nil
        AlarmPlayer.shared.stopAlarm()
        stopCriticalHaptics()
    }

    // MARK: - 聊天

    func sendChat(_ text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let mentions = parseMentionsFromText(content)
        let chat = ChatMessage(
            senderID: nodeStatus.nodeID,
            senderName: "\(nodeStatus.deptCode)-\(nodeStatus.nodeID)",
            content: content,
            mentions: mentions
        )
        chatMessages.append(chat)
        commandClient.sendChatMessage(chat)
        chatDraft = ""
        appendActivity(kind: .sentMessage, title: "\(nodeStatus.deptCode)-\(nodeStatus.nodeID)", detail: content)
    }

    /// 解析訊息中的 @ 提及，對比 personnelAssignments / teamMembers 後回傳對應 id 列表
    private func parseMentionsFromText(_ text: String) -> [String] {
        guard text.contains("@") else { return [] }
        let pattern = "@([\\u{4e00}-\\u{9fa5}A-Za-z0-9_\\-]{1,20})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen: Set<String> = []
        var out: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let tok = nsText.substring(with: m.range(at: 1))
            let pid = resolveMentionToken(tok)
            if let p = pid, !seen.contains(p) {
                seen.insert(p)
                out.append(p)
            }
        }
        return out
    }

    private func resolveMentionToken(_ tok: String) -> String? {
        if let id = personnelAssignments.first(where: { $0.nickname == tok })?.id { return id }
        if let id = personnelAssignments.first(where: { $0.name == tok })?.id { return id }
        if let id = personnelAssignments.first(where: { $0.id == tok })?.id { return id }
        if tok.count >= 3,
           let id = personnelAssignments.first(where: { $0.id.hasSuffix(tok) })?.id { return id }
        if let id = teamMembers.first(where: { $0.nickname == tok })?.id { return id }
        if let id = teamMembers.first(where: { $0.id == tok })?.id { return id }
        if tok.count >= 3,
           let id = teamMembers.first(where: { $0.id.hasSuffix(tok) })?.id { return id }
        return nil
    }

    // MARK: - 通知管理

    func markNotificationAsRead(_ id: String) {
        if let idx = personalNotifications.firstIndex(where: { $0.id == id }) {
            personalNotifications[idx].isRead = true
            unreadNotificationCount = personalNotifications.filter { !$0.isRead }.count
        }
    }

    // MARK: - 統一活動記錄

    func appendActivity(kind: ActivityKind, title: String, detail: String, timestamp: Date = Date(), id: String = UUID().uuidString) {
        let entry = ActivityLogEntry(id: id, kind: kind, title: title, detail: detail, timestamp: timestamp)
        if let idx = activityLog.firstIndex(where: { $0.id == id }) {
            activityLog[idx] = entry
            return
        }
        activityLog.insert(entry, at: 0)
        if activityLog.count > 300 { activityLog = Array(activityLog.prefix(300)) }
    }

    // MARK: - 快速狀態回報

    func sendQuickStatus(_ type: QuickStatusType, zone: String = "", note: String = "") {
        let status = QuickStatus(
            type: type,
            senderID: nodeStatus.nodeID,
            senderName: "\(nodeStatus.deptCode)-\(nodeStatus.nodeID)",
            zone: zone,
            note: note
        )
        quickStatuses.insert(status, at: 0)
        commandClient.sendQuickStatus(status)
        appendActivity(kind: .quickStatus, title: L("已送出快速狀態"), detail: type.label)
    }

    // MARK: - 任務管理

    func updateTaskStatus(_ taskID: String, newStatus: TaskStatus) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].status = newStatus.rawValue
        commandClient.sendTaskUpdate(tasks[idx])
        appendActivity(kind: .task, title: L("已更新任務狀態"), detail: "\(tasks[idx].title) · \(newStatus.label)")
    }

    var activeTaskCount: Int { tasks.filter(\.isActive).count }

    // MARK: - HQ 遠端控制（iPad 連線 Mac HQ 時可發送指揮命令）

    /// 透過 HQ 發送快速命令（廣播給所有前線裝置）
    func sendHQQuickCommand(type: String, priority: Int, title: String, detail: String, sender: String) {
        let cmd = WiFiCommand(
            id: UUID().uuidString,
            type: type,
            priority: priority,
            title: title,
            detail: detail,
            sender: sender,
            timestamp: Date().timeIntervalSince1970
        )
        commandClient.sendHQCommand(cmd)
        appendActivity(kind: .command, title: "\(L("已送出命令")): \(title)", detail: detail)
    }

    /// 透過 HQ 啟動倒數計時器
    func startHQTimer(title: String, durationSeconds: Int) {
        let timer = CountdownTimerModel(title: title, durationSeconds: durationSeconds)
        countdownTimers.append(timer)
        startCountdownRefresh()
        commandClient.sendHQTimerStart(timer)
        appendActivity(kind: .timer, title: L("已啟動倒數計時"), detail: title)
    }

    /// 透過 HQ 取消倒數計時器
    func cancelHQTimer(_ timerID: String) {
        countdownTimers.removeAll { $0.id == timerID }
        commandClient.sendHQTimerCancel(timerID: timerID)
        appendActivity(kind: .timer, title: L("已取消倒數計時"), detail: timerID)
    }

    /// 透過 HQ 指派任務
    func assignHQTask(title: String, detail: String, assigneeID: String, assigneeName: String, zone: String) {
        let task = TaskAssignment(
            title: title, detail: detail,
            assigneeID: assigneeID.isEmpty ? "ALL" : assigneeID,
            assigneeName: assigneeName.isEmpty ? assigneeID : assigneeName,
            zone: zone
        )
        tasks.insert(task, at: 0)
        commandClient.sendHQTaskAssign(task)
        appendActivity(kind: .task, title: L("已送出任務指派"), detail: task.title)
    }

    // MARK: - 倒數計時器

    private func startCountdownRefresh() {
        countdownRefreshTimer?.invalidate()
        // 只在有活躍倒數時啟動，無倒數時停止以節省電力
        guard !countdownTimers.isEmpty else { return }
        countdownRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let expired = self.countdownTimers.filter(\.isExpired)
                if !expired.isEmpty {
                    for timer in expired {
                        self.appendActivity(kind: .timer, title: L("倒數計時結束"), detail: timer.title)
                        NotificationManager.shared.sendCommandNotification(
                            order: CommandOrder(
                                id: UUID(),
                                type: .standby, priority: .urgent,
                                title: "\(timer.title) 時間到",
                                detail: L("倒數計時已結束"),
                                sender: L("系統"),
                                time: Date(),
                                isRead: false
                            )
                        )
                    }
                    self.countdownTimers.removeAll(where: \.isExpired)
                }
                // 無剩餘倒數時自動停止 timer
                if self.countdownTimers.isEmpty {
                    self.countdownRefreshTimer?.invalidate()
                    self.countdownRefreshTimer = nil
                    return
                }
            }
        }
    }

    // MARK: - 危險標記

    func reportHazard(type: HazardType, description: String = "", zone: String = "", severity: HazardSeverity = .medium) {
        let report = HazardReport(
            hazardType: type,
            description: description,
            reporterID: nodeStatus.nodeID,
            reporterName: "\(nodeStatus.deptCode)-\(nodeStatus.nodeID)",
            zone: zone,
            severity: severity
        )
        hazardReports.insert(report, at: 0)
        commandClient.sendHazardReport(report)
        appendActivity(kind: .hazard, title: L("已送出危險標記"), detail: description.isEmpty ? zone : description)
    }

    func sendPatientReport(_ report: PatientReport) {
        #if canImport(UIKit)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? nodeStatus.nodeID
        #else
        let deviceID = nodeStatus.nodeID
        #endif
        commandClient.sendPatientReport(report, deviceID: deviceID)
        // 持久化到本地
        localPatients.append(report)
        PersistenceManager.shared.save(key: "localPatients", value: localPatients)
        appendActivity(kind: .patientReport, title: L("已送出傷患回報"), detail: report.name.isEmpty ? report.patientId : report.name)
    }

    var previewPatientID: String {
        patientIDConfig.displayID()
    }

    var previewPatientNFCURL: String {
        patientIDConfig.nfcURL()
    }

    func displayPatientID(from text: String) -> String? {
        patientIDConfig.displayID(from: text)
    }

    func patientNFCURL(for patientID: String) -> String {
        patientIDConfig.nfcURL(for: patientID)
    }

    func reserveNextPatientID() -> String {
        let serial = max(1, patientIDConfig.nextPatientSerial)
        let id = patientIDConfig.displayID(serial: serial)
        patientIDConfig.nextPatientSerial = serial + 1
        PersistenceManager.shared.save(key: "patientIDConfig", value: patientIDConfig)
        return id
    }

    private func applyPatientIDConfig(_ incomingConfig: PatientIDConfig) {
        var config = incomingConfig
        if config.displayPrefix == patientIDConfig.displayPrefix {
            config.nextPatientSerial = max(config.nextPatientSerial, patientIDConfig.nextPatientSerial)
        }
        let changed = config != patientIDConfig
        patientIDConfig = config
        PersistenceManager.shared.save(key: "patientIDConfig", value: patientIDConfig)
        if changed {
            appendActivity(kind: .command, title: L("收到傷患編號配置"), detail: patientIDConfig.displayPrefix)
        }
    }

    // MARK: - 交班摘要

    func generateHandoverSummary() -> String {
        var lines: [String] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d HH:mm"

        lines.append("[交班摘要] — \(fmt.string(from: Date()))")
        lines.append("━━━━━━━━━━━━━━━━━━━━")
        lines.append("")

        // 節點資訊
        lines.append("[節點] \(nodeStatus.deptCode)-\(nodeStatus.nodeID)")
        lines.append("[電量] \(nodeStatus.battery)%")
        lines.append("[運行] \(uptimeText)")
        lines.append("")

        // 受困者
        lines.append("[受困者] \(victims.count) 人（\(onlineVictimCount) 在線）")
        let sosV = victims.filter { $0.isSOS && $0.isOnline }
        if !sosV.isEmpty {
            lines.append("[SOS] \(sosV.map(\.id).joined(separator: ", "))")
        }
        lines.append("")

        // 未確認 SOS
        let unackSOS = sosRecords.filter { !$0.isAcknowledged }
        if !unackSOS.isEmpty {
            lines.append("[警告] 未確認 SOS：\(unackSOS.count) 筆")
        }

        // 未讀命令
        let unreadCmds = commandOrders.filter { !$0.isRead }
        if !unreadCmds.isEmpty {
            lines.append("[命令] 未讀：\(unreadCmds.count) 筆")
        }

        // 進行中任務
        let activeTasks = tasks.filter(\.isActive)
        if !activeTasks.isEmpty {
            lines.append("")
            lines.append(L("[任務] 進行中："))
            for task in activeTasks {
                lines.append("  • [\(task.taskStatus.label)] \(task.title)")
            }
        }

        // 危險區域
        if !hazardReports.isEmpty {
            lines.append("")
            lines.append(L("[危險] 已知危險："))
            for h in hazardReports.prefix(5) {
                let label = h.hazard?.rawValue ?? h.hazardType
                lines.append("  • [\(h.severityLevel.label)] \(label) — \(h.zone.isEmpty ? L("未指定區域") : h.zone)")
            }
        }

        // 團隊
        if !teamMembers.isEmpty {
            lines.append("")
            lines.append("[人員] 團隊成員：\(teamMembers.count) 人（\(teamMembers.filter(\.isOnline).count) 在線）")
        }

        // 活躍計時器
        let activeTimers = countdownTimers.filter { !$0.isExpired }
        if !activeTimers.isEmpty {
            lines.append("")
            lines.append(L("[計時] 進行中："))
            for t in activeTimers {
                lines.append("  • \(t.title)：剩餘 \(t.remainingText)")
            }
        }

        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━")
        return lines.joined(separator: "\n")
    }

    // MARK: - 觸覺回饋

    private func triggerSOSNotification(for victim: VictimNode? = nil) {
        guard pastStartupGrace else { return }
        if let victim {
            latestSOSVictim = victim
            AlarmPlayer.shared.playSOSAlarm()
            NotificationManager.shared.sendSOSNotification(
                victimID: victim.id,
                heartRate: victim.heartRate,
                distance: victim.distanceText
            )
            // 30秒後自動降級（全螢幕 → 關閉 overlay，SOS 仍在列表中）
            sosAutoDowngradeTimer?.invalidate()
            sosAutoDowngradeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.latestSOSVictim = nil
                    AlarmPlayer.shared.stopAlarm()
                    self?.stopCriticalHaptics()
                }
            }
        }
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    /// 使用者確認全螢幕 SOS 警報
    func dismissSOSAlert() {
        sosAutoDowngradeTimer?.invalidate()
        sosAutoDowngradeTimer = nil
        if let victim = latestSOSVictim {
            // 自動 acknowledge 對應的最新 SOS Record
            if let idx = sosRecords.firstIndex(where: {
                $0.victimID == victim.id && !$0.isAcknowledged
            }) {
                sosRecords[idx].isAcknowledged = true
            }
        }
        latestSOSVictim = nil
        AlarmPlayer.shared.stopAlarm()
        stopCriticalHaptics()
    }

    func requestTranslation(text: String, sourceLang: String = "auto", targetLang: String = "en") {
        guard commandClient.isConnected, !text.isEmpty else { return }
        commandClient.sendTranslateRequest(text: text, sourceLang: sourceLang, targetLang: targetLang)
    }

    /// 關閉緊急廣播彈窗
    func dismissUrgentBroadcast() {
        urgentBroadcast = nil
    }

    /// 關閉傷患預警高優先度彈窗
    func dismissPatientWarning() {
        activePatientWarning = nil
    }

    // MARK: - SOS 上行（規範補齊）

    /// 目前是否處於 SOS 狀態
    @Published var isSOSActive = false
    /// 目前 SOS 的 ID
    private var currentSOSId: String?

    /// 發送 SOS 緊急呼叫（上行到 Mac HQ → Windows）
    func sendSOS() {
        guard commandClient.isConnected else { return }
        let sosId = "SOS-\(nodeStatus.nodeID)-\(Int(Date().timeIntervalSince1970))"
        currentSOSId = sosId
        isSOSActive = true
        commandClient.sendSOS(senderName: nodeStatus.nodeID)
        appendActivity(kind: .sos, title: L("已送出 SOS"), detail: nodeStatus.nodeID)
    }

    /// 取消 SOS
    func cancelSOS() {
        guard commandClient.isConnected, let sosId = currentSOSId else { return }
        commandClient.sendSOSCancel(sosId: sosId)
        isSOSActive = false
        currentSOSId = nil
        appendActivity(kind: .sos, title: L("已取消 SOS"), detail: sosId)
    }

    /// 發送傷患惡化預警（上行到 Mac HQ → Windows）
    func sendPatientWarning(patientId: String, warningType: String, message: String) {
        guard commandClient.isConnected else { return }
        commandClient.sendPatientWarning(patientId: patientId, warningType: warningType, message: message)
        appendActivity(kind: .patientWarning, title: "\(L("已送出傷患預警")): \(patientId)", detail: message)
    }

    // MARK: - 指揮中心命令引擎（NTP 時間同步）

    /// 已處理過的 slot 索引（避免重複觸發）
    private var processedSlots: Set<Int> = []

    private func startCommandEngine() {
        // 立即排程到下一個 slot
        scheduleNextSlot()
    }

    private func stopCommandEngine() {
        commandTimer?.invalidate()
        commandTimer = nil
    }

    private func scheduleNextSlot() {
        let fireDate = commandEngine.nextSlotFireDate()
        let delay = max(0.1, fireDate.timeIntervalSinceNow)

        commandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fireSlot()
                self?.scheduleNextSlot()
            }
        }
    }

    private func fireSlot() {
        let slot = commandEngine.currentSlotIndex()
        guard !processedSlots.contains(slot) else { return }
        processedSlots.insert(slot)

        // 避免記憶體無限增長，只保留最近 100 個
        if processedSlots.count > 100 {
            let oldest = processedSlots.sorted().prefix(processedSlots.count - 50)
            processedSlots.subtract(oldest)
        }

        let wifiCmd = commandEngine.generateCommand(forSlot: slot)
        let order = wifiCmd.toCommandOrder()
        commandOrders.insert(order, at: 0)
        appendActivity(kind: .command, title: "\(L("本機命令")): \(order.title)", detail: order.detail, timestamp: order.time)

        // 發送本地通知
        NotificationManager.shared.sendCommandNotification(order: order)

        // Critical 命令：全螢幕覆蓋層 + 持續震動 + 警報音
        if order.priority == .critical {
            latestCriticalCommand = order
            DispatchQueue.main.async {
                AlarmPlayer.shared.playAlarm()
            }
            startCriticalHaptics()
        }
    }

    /// 使用者確認全螢幕命令警報
    func dismissCommandAlert() {
        if let cmd = latestCriticalCommand {
            if let idx = commandOrders.firstIndex(where: { $0.id == cmd.id }) {
                commandOrders[idx].isRead = true
            }
        }
        latestCriticalCommand = nil
        AlarmPlayer.shared.stopAlarm()
        stopCriticalHaptics()
    }

    /// 標記命令為已讀
    func markCommandAsRead(_ order: CommandOrder) {
        if let idx = commandOrders.firstIndex(where: { $0.id == order.id }) {
            commandOrders[idx].isRead = true
        }
    }

    /// 標記所有命令為已讀
    func markAllCommandsAsRead() {
        for i in commandOrders.indices {
            commandOrders[i].isRead = true
        }
    }

    // MARK: - 持續震動（Critical 命令）

    private func startCriticalHaptics() {
        #if os(iOS)
        stopCriticalHaptics() // 確保先清理舊的 Timer
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            let g = UINotificationFeedbackGenerator()
            g.notificationOccurred(.error)
        }
        #endif
    }

    private func stopCriticalHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }
}

// MARK: - CLLocationManager Delegate（requestLocation 必須）

private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocationUpdate: (() -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocationUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationDelegate] 定位失敗: \(error.localizedDescription)")
    }
}
