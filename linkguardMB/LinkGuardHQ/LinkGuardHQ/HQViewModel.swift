import Foundation
import SwiftUI
import Combine
import AVFoundation

/// 指揮中心核心 ViewModel
@MainActor
class HQViewModel: ObservableObject {

    // MARK: - 角色模式

    enum HQRole: String, CaseIterable {
        case server = "Mac 指揮中心"
        case peer   = "副指揮連接"
    }
    #if os(iOS)
    @Published var hqRole: HQRole = .peer
    #else
    @Published var hqRole: HQRole = .server
    #endif

    // MARK: - 發布狀態

    @Published var server = HQCommandServer()
    let peerClient = HQPeerClient()
    @Published var bluetoothManager = HQBluetoothManager()
    @Published var loraReceivedCommands: [HQLoRaReceivedCommand] = []
    @Published var backendBridge = HQBackendBridge()
    #if os(macOS)
    /// 內建 Python 後端管理員 (sidecar)
    @Published var backendSupervisor = BackendSupervisor()
    #endif
    /// 後端模式 (embedded / remote / bonjour) — 透過 AppStorage 持久化
    @AppStorage("hq.backendMode") var backendModeRaw: String = BackendMode.embedded.rawValue
    var backendMode: BackendMode {
        get { BackendMode(rawValue: backendModeRaw) ?? .embedded }
        set { backendModeRaw = newValue.rawValue }
    }
    @Published var speechServer = HQSpeechServer()
    @Published var photoServer = HQPhotoServer()
    @Published var udpAudioServer = UDPAudioServer()
    @Published var audioStreamServer = AudioStreamServer()

    // 命令表單
    @Published var selectedType: CommandType = .searchArea
    @Published var selectedPriority: CommandPriority = .routine
    @Published var commandTitle = ""
    @Published var commandDetail = ""
    @Published var senderName = "HQ-Alpha"

    // 命令歷史
    @Published var commandHistory: [CommandOrder] = []

    // Beta-only features
    @Published var photoAlerts: [[String: Any]] = []
    @Published var latestResourceUpdate: [String: Any]?
    @Published var latestStatsUpdate: [String: Any]?
    @Published var textBroadcasts: [HQTextBroadcast] = []
    @Published var patientWarnings: [HQPatientWarning] = []
    @Published var readStatuses: [String: (total: Int, readCount: Int)] = [:]
    @Published var latestTranslation: HQTranslationResult?
    @Published var activeSOSAlerts: [SOSAlert] = []
    @Published var showSOSOverlay = false
    @Published var peerBackendConnected = false

    // --- 新功能狀態 ---
    // 聚合狀態 (與 iOS 保持邏輯一致)
    var systemStatus: (text: String, color: Color) {
        if server.isRunning { return ("指揮中心運行中", NV.green) }
        if peerClient.isConnected { return ("已連線指揮中心", NV.green) }
        if sosCount > 0 { return ("SOS 警報中", NV.danger) }
        return ("指揮中心已停止", .gray)
    }

    // 災害狀態
    @Published var disasterSite: DisasterSite? = DisasterSite()

    // 聊天訊息
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatDraft = ""
    /// 聊天已讀回條：messageID → 已讀裝置數
    @Published var chatReadCounts: [String: Int] = [:]

    // 人員配置
    @Published var personnelAssignments: [PersonnelAssignment] = []

    // PWS 警報
    @Published var pwsAlerts: [PWSAlert] = []

    // 會報
    @Published var briefings: [BriefingReport] = []

    // 個人通知
    @Published var personalNotifications: [PersonalNotification] = []

    // 事件日誌
    @Published var timelineEvents: [TimelineEvent] = []

    // 快速狀態回報（來自前線）
    @Published var quickStatuses: [QuickStatus] = []

    // 任務指派
    @Published var tasks: [TaskAssignment] = []

    // 倒數計時器
    @Published var countdownTimers: [CountdownTimerModel] = []

    // 危險標記（來自前線）
    @Published var hazardReports: [HazardReport] = []

    // 增援請求
    @Published var reinforcementRequests: [ReinforcementRequest] = []

    // 傷員回報
    @Published var patientReports: [PatientReport] = []

    // AI 副駕駛指令提案執行/忽略狀態（HITL）
    @Published var executedProposalIDs: Set<String> = []
    @Published var ignoredProposalIDs: Set<String> = []

    // 電台會報
    @Published var radioReports: [HQRadioReport] = []
    @Published var currentBroadcaster: String?

    // PADOS 多裝置定向指揮
    enum TargetMode: String, CaseIterable {
        case broadcast = "廣播全體"
        case selected = "選擇裝置"
    }
    @Published var targetMode: TargetMode = .broadcast
    @Published var selectedTargetDeviceIDs: Set<String> = []

    /// 傳入 server 的目標裝置 ID 陣列；廣播模式回傳 nil
    var effectiveTargetIDs: [String]? {
        targetMode == .broadcast ? nil : Array(selectedTargetDeviceIDs)
    }

    // 聚合統計（peer 模式下使用伺服器同步資料）
    var connectedCount: Int {
        hqRole == .peer ? (peerClient.serverStatus?.onlineFieldUnitCount ?? 0) : server.onlineFieldUnitCount
    }
    var totalVictimCount: Int {
        hqRole == .peer ? (peerClient.serverStatus?.totalVictimCount ?? 0) : server.allVictims.count
    }
    var onlineVictimCount: Int {
        hqRole == .peer ? (peerClient.serverStatus?.onlineVictimCount ?? 0) : server.onlineVictimCount
    }
    var sosCount: Int {
        hqRole == .peer ? (peerClient.serverStatus?.sosCount ?? 0) : server.totalSOSCount
    }
    var teamCount: Int {
        hqRole == .peer ? (peerClient.serverStatus?.teamCount ?? 0) : server.allTeamMembers.count
    }
    var peerFieldUnitCount: Int {
        peerClient.serverStatus?.fieldUnitCount ?? 0
    }
    var isBackendConnected: Bool {
        #if os(macOS)
        if hqRole == .server, backendMode == .embedded {
            return backendBridge.isConnected || embeddedBackendHasStarted
        }
        #endif
        return hqRole == .peer ? peerBackendConnected : backendBridge.isConnected
    }

    /// 實際可達的後端 host（peer 模式下取主 HQ 透過 peerClient 同步來的 host）。
    /// AI 對話／指令審批等需要直接 HTTP 呼後端的 UI 一律使用這個屬性。
    var effectiveBackendHost: String {
        if hqRole == .peer {
            return peerClient.serverStatus?.backendHost ?? ""
        }
        #if os(macOS)
        if backendMode == .embedded { return "127.0.0.1" }
        #endif
        return backendBridge.backendHost
    }

    #if os(macOS)
    private var embeddedBackendHasStarted: Bool {
        backendSupervisor.services.contains { $0.status != .stopped }
    }
    #endif

    // MARK: - 受困者總覽（含優先級、處置狀態）

    /// 使用者設定的優先級 & 備註（key = victimID）
    @Published var victimPriorities: [String: VictimPriority] = [:]
    @Published var victimNotes: [String: String] = [:]
    @Published var victimStatuses: [String: VictimStatus] = [:]
    @Published var victimDescriptions: [String: String] = [:]
    @Published var victimTriageReasons: [String: String] = [:]
    private var autoTriageManagedVictimIDs: Set<String> = []

    /// 電台音訊本地播放器
    private var radioAudioPlayer: AVAudioPlayer?

    /// 聚合所有受困者（含各裝置 VictimSummary + 傷患回報 PatientReport），附帶優先級 & 處置狀態
    var allVictimRecords: [HQVictimRecord] {
        var seen = Set<String>()
        var records: [HQVictimRecord] = []

        // 1) 從各前線裝置的 VictimSummary 建立
        for unit in server.fieldUnits {
            for v in unit.victims where !seen.contains(v.id) {
                seen.insert(v.id)
                let report = patientReports.first { $0.patientId == v.id }
                records.append(HQVictimRecord(
                    id: v.id,
                    heartRate: v.heartRate,
                    battery: v.battery,
                    rssi: v.rssi,
                    isSOS: v.isSOS,
                    isOnline: v.isOnline,
                    sourceDeviceID: unit.deviceID,
                    sourceDeptCode: unit.deptCode,
                    priority: victimPriorities[v.id] ?? .unset,
                    status: victimStatuses[v.id] ?? .pending,
                    note: victimNotes[v.id] ?? "",
                    description: victimDescriptions[v.id] ?? "",
                    patientName: report?.name ?? "",
                    location: report?.location ?? "",
                    hasPatientReport: report != nil
                ))
            }
        }

        // 2) 從 PatientReport 補入尚未出現的傷患（其他裝置上傳的回報）
        for report in patientReports where !seen.contains(report.patientId) {
            seen.insert(report.patientId)
            records.append(HQVictimRecord(
                id: report.patientId,
                heartRate: 0,
                battery: 0,
                rssi: 0,
                isSOS: false,
                isOnline: false,
                sourceDeviceID: "傷患回報",
                sourceDeptCode: "",
                priority: victimPriorities[report.patientId] ?? .unset,
                status: victimStatuses[report.patientId] ?? .pending,
                note: victimNotes[report.patientId] ?? "",
                description: victimDescriptions[report.patientId] ?? report.notes,
                patientName: report.name,
                location: report.location,
                hasPatientReport: true
            ))
        }

        return records
    }

    func setVictimPriority(_ victimID: String, _ priority: VictimPriority) {
        // 使用者手動覆寫後，不再由自動 START 檢傷持續覆蓋。
        autoTriageManagedVictimIDs.remove(victimID)
        victimPriorities[victimID] = priority
    }

    func setVictimNote(_ victimID: String, _ note: String) {
        victimNotes[victimID] = note
    }

    func setVictimStatus(_ victimID: String, _ status: VictimStatus) {
        victimStatuses[victimID] = status
    }

    func setVictimDescription(_ victimID: String, _ desc: String) {
        victimDescriptions[victimID] = desc
    }

    /// 人員總覽：合併 PersonnelAssignment + TeamSummary
    var allTeamOverview: [(id: String, deptCode: String, battery: Int, rssi: Double, isOnline: Bool, victimCount: Int, sourceDevice: String)] {
        var seen = Set<String>()
        var result: [(id: String, deptCode: String, battery: Int, rssi: Double, isOnline: Bool, victimCount: Int, sourceDevice: String)] = []
        for unit in server.fieldUnits {
            for t in unit.teamMembers where !seen.contains(t.id) {
                seen.insert(t.id)
                result.append((id: t.id, deptCode: t.deptCode, battery: t.battery, rssi: t.rssi, isOnline: t.isOnline, victimCount: t.victimCount, sourceDevice: unit.deviceID))
            }
        }
        return result
    }

    private var cancellables = Set<AnyCancellable>()
    /// peer 模式的 Combine 綁定（切換角色時重置）
    private var peerCancellables = Set<AnyCancellable>()
    private var whisperObserver: NSObjectProtocol?

    // MARK: - 初始化

    init() {
        // Mac-only 主路徑：所有後端/AI 功能預設指向此 Mac 的 sidecar。
        server.backendBridge = backendBridge
        backendBridge.server = server

        // 初始化雙重語音辨識（WhisperKit + Apple Speech）— 僅 server 模式需要
        if hqRole == .server {
            Task {
                await initializeWhisperWithRetry()
            }
        }

        // LGAP TCP 串流音訊 → 轉發到 UDPAudioServer 語音辨識管線
        audioStreamServer.onPCMDataReceived = { [weak self] pcmData, senderID in
            self?.udpAudioServer.feedAudioForRecognition(audioData: pcmData, deviceID: senderID)
        }

        // 語音辨識伺服器：收到音訊檔後立即本地播放
        speechServer.onAudioFileReady = { [weak self] fileURL, senderName in
            guard let self else { return }
            self.playReceivedRadioAudio(url: fileURL, sender: senderName)
        }

        // 語音辨識伺服器：辨識完成後記錄於 HQ + 廣播摘要給前線
        speechServer.onTranscriptionComplete = { [weak self] result in
            guard let self else { return }
            // 1. 建立 HQRadioReport 顯示在 HQ
            let report = HQRadioReport(
                senderName: result.senderName,
                transcription: result.transcription,
                locationDesc: result.locationDesc,
                reportId: result.reportId,
                patientsCount: 0,
                weatherSnapshot: result.weatherSnapshot,
                sourceType: result.sourceType
            )
            self.radioReports.insert(report, at: 0)
            // 2. 廣播摘要給所有前線裝置（含 audioUrl 供下載播放）
            let localIP = self.speechServer.getLocalIP()
            let audioUrl = "http://\(localIP):8003/audio/\(result.reportId)"
            let summary = RadioReportSummary(
                reportId: result.reportId,
                senderName: result.senderName,
                transcription: result.transcription,
                timestamp: Date().timeIntervalSince1970,
                locationDesc: result.locationDesc,
                patientsCount: 0,
                audioUrl: audioUrl
            )
            self.server.broadcastReportSummary(summary)
            let logTitle = result.sourceType == .briefing
                ? L("固定會報：%@", result.senderName)
                : L("即時廣播：%@", result.senderName)
            self.logEvent(type: .briefing, title: logTitle,
                          detail: result.transcription.prefix(50) + "...")
        }
        // 照片伺服器回呼（須先設定再啟動）
        photoServer.onPhotoReceived = { [weak self] photoAlert in
            guard let self else { return }
            self.server.photoAlerts.insert(photoAlert, at: 0)
            let sender = photoAlert["sender_name"] as? String ?? ""
            let photoId = photoAlert["photo_id"] as? String ?? ""
            self.server.appendTimelineEvent(TimelineEvent(
                eventType: .briefing,
                title: L("照片回報：%@", photoId),
                detail: L("來自 %@（本地接收）", sender),
                source: "local-photo-server"
            ))
            // 廣播給所有前線裝置
            self.server.relayBackendJSON(msgType: "photo_alert", data: photoAlert)
        }
        // 只在 server 模式下啟動本地伺服器
        if hqRole == .server {
            speechServer.start()
            audioStreamServer.start()
            photoServer.start()
            server.startLocalStatsTimer()
        } else {
            // iPad peer 預設模式：自動開始搜尋 Mac HQ
            setupPeerBindings()
            peerClient.startBrowsing()
        }

        // 監聽 server 發出的命令，同步到歷史
        server.$sentCommands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cmds in
                self?.commandHistory = cmds.map { $0.toCommandOrder() }
            }
            .store(in: &cancellables)

        // 監聯 server 上的聊天訊息
        server.$chatMessages
            .receive(on: DispatchQueue.main)
            .assign(to: &$chatMessages)

        // 監聽聊天已讀計數
        server.$chatReadCounts
            .receive(on: DispatchQueue.main)
            .assign(to: &$chatReadCounts)

        // 監聽災害狀態
        server.$disasterSite
            .receive(on: DispatchQueue.main)
            .assign(to: &$disasterSite)

        // 監聽人員配置
        server.$personnelAssignments
            .receive(on: DispatchQueue.main)
            .assign(to: &$personnelAssignments)

        // 監聽 PWS 警報
        server.$pwsAlerts
            .receive(on: DispatchQueue.main)
            .assign(to: &$pwsAlerts)

        // 監聽會報
        server.$briefings
            .receive(on: DispatchQueue.main)
            .assign(to: &$briefings)

        // 監聽個人通知
        server.$personalNotifications
            .receive(on: DispatchQueue.main)
            .assign(to: &$personalNotifications)

        // 監聽事件日誌
        server.$timelineEvents
            .receive(on: DispatchQueue.main)
            .assign(to: &$timelineEvents)

        // 監聽快速狀態回報
        server.$quickStatuses
            .receive(on: DispatchQueue.main)
            .assign(to: &$quickStatuses)

        // 監聽任務
        server.$tasks
            .receive(on: DispatchQueue.main)
            .assign(to: &$tasks)

        // 監聽倒數計時器
        server.$countdownTimers
            .receive(on: DispatchQueue.main)
            .assign(to: &$countdownTimers)

        // 監聽危險標記
        server.$hazardReports
            .receive(on: DispatchQueue.main)
            .assign(to: &$hazardReports)

        // 監聽增援請求
        server.$reinforcementRequests
            .receive(on: DispatchQueue.main)
            .assign(to: &$reinforcementRequests)

        // 監聽傷員回報（Mac 本地 START 檢傷）
        server.$patientReports
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reports in
                guard let self else { return }
                self.patientReports = reports
                self.applyLocalSTARTTriage(from: reports)
            }
            .store(in: &cancellables)

        // 監聽電台會報
        server.$radioReports
            .receive(on: DispatchQueue.main)
            .assign(to: &$radioReports)

        server.$currentBroadcaster
            .merge(with: udpAudioServer.$activeBroadcaster)
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentBroadcaster)

        // Beta-only bindings
        server.$photoAlerts
            .receive(on: DispatchQueue.main)
            .assign(to: &$photoAlerts)
        server.$latestResourceUpdate
            .receive(on: DispatchQueue.main)
            .assign(to: &$latestResourceUpdate)
        server.$latestStatsUpdate
            .receive(on: DispatchQueue.main)
            .assign(to: &$latestStatsUpdate)
        server.$textBroadcasts
            .receive(on: DispatchQueue.main)
            .assign(to: &$textBroadcasts)
        server.$patientWarnings
            .receive(on: DispatchQueue.main)
            .assign(to: &$patientWarnings)
        server.$readStatuses
            .receive(on: DispatchQueue.main)
            .assign(to: &$readStatuses)
        server.$latestTranslation
            .receive(on: DispatchQueue.main)
            .assign(to: &$latestTranslation)

        // 監聽 SOS 即時警報
        server.$activeSOSAlerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alerts in
                self?.activeSOSAlerts = alerts
                if !alerts.isEmpty {
                    self?.showSOSOverlay = true
                }
            }
            .store(in: &cancellables)

        // 監聽 HQ LoRa BLE 收到的命令
        bluetoothManager.onLoRaCommand = { [weak self] cmd in
            self?.loraReceivedCommands.insert(cmd, at: 0)
            if self?.loraReceivedCommands.count ?? 0 > 50 {
                self?.loraReceivedCommands.removeLast()
            }
        }

        // UDP 音訊伺服器：Whisper 轉錄完成回呼
        whisperObserver = NotificationCenter.default.addObserver(
            forName: .whisperTranscriptionReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let text = userInfo["text"] as? String,
                  let deviceID = userInfo["device_id"] as? String else { return }
            let report = HQRadioReport(
                senderName: deviceID,
                transcription: text,
                locationDesc: "",
                reportId: UUID().uuidString,
                patientsCount: 0,
                weatherSnapshot: "",
                sourceType: .live
            )
            self.radioReports.insert(report, at: 0)
            let wLocalIP = self.speechServer.getLocalIP()
            let wAudioUrl = "http://\(wLocalIP):8003/audio/\(report.reportId)"
            self.server.broadcastReportSummary(RadioReportSummary(
                reportId: report.reportId,
                senderName: deviceID,
                transcription: text,
                timestamp: Date().timeIntervalSince1970,
                locationDesc: "",
                patientsCount: 0,
                audioUrl: wAudioUrl
            ))
            self.logEvent(type: .briefing, title: "Whisper 轉錄：\(deviceID)",
                          detail: String(text.prefix(50)) + "...")
        }

        // UDP activeBroadcaster 已透過上方 merge(with:) 合併，不需重複綁定
    }

    // MARK: - WhisperKit 初始化（含重試）

    /// WhisperKit 初始化狀態，供 UI 顯示
    @Published var whisperStatus: String = "未初始化"

    /// 帶重試的 WhisperKit 初始化（最多嘗試 3 次，每次間隔遞增）
    private func initializeWhisperWithRetry(maxAttempts: Int = 3) async {
        for attempt in 1...maxAttempts {
            await MainActor.run { whisperStatus = "WhisperKit 載入中 (嘗試 \(attempt)/\(maxAttempts))…" }
            await udpAudioServer.initialize()
            if udpAudioServer.whisperReady {
                await MainActor.run {
                    speechServer.whisperKit = udpAudioServer.whisperKit
                    whisperStatus = "WhisperKit 就緒"
                }
                print("[HQ] ✅ WhisperKit 初始化成功 (嘗試 \(attempt))")
                return
            }
            print("[HQ] ⚠️ WhisperKit 初始化失敗 (嘗試 \(attempt)/\(maxAttempts))")
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt * 3_000_000_000)) // 3s, 6s
            }
        }
        // 全部失敗 — 仍可使用 Apple Speech 做即時辨識
        await MainActor.run {
            whisperStatus = "WhisperKit 未就緒（僅 Apple Speech）"
        }
        print("[HQ] ❌ WhisperKit 最終初始化失敗，退入 Apple Speech 模式")
    }

    // MARK: - 電台音訊本地播放

    /// 收到前線 PTT 音訊檔後立即本地播放
    private func playReceivedRadioAudio(url: URL, sender: String) {
        guard udpAudioServer.isLocalPlaybackEnabled else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(udpAudioServer.playbackVolume)
            player.prepareToPlay()
            player.play()
            radioAudioPlayer = player   // 保持強參考直到播放完畢
            print("[Radio] 🔊 本地播放 \(sender) 的電台音訊 (\(url.lastPathComponent))")
        } catch {
            print("[Radio] ❌ 本地播放失敗: \(error)")
        }
    }

    // MARK: - 文字廣播 / 傷患預警

    /// 指揮中心主動發送文字廣播
    func sendTextBroadcast(message: String, priority: String = "normal") {
        server.sendTextBroadcast(message: message, priority: priority)
    }

    /// 清除傷患預警
    func dismissPatientWarning(_ id: UUID) {
        patientWarnings.removeAll { $0.id == id }
    }

    /// 確認 SOS 警報（關閉彈窗，但保留列表記錄）
    func acknowledgeSOSOverlay() {
        showSOSOverlay = false
    }

    /// 清除單一 SOS 警報
    func dismissSOSAlert(_ sosId: String) {
        if let alert = activeSOSAlerts.first(where: { $0.id == sosId }) {
            server.markSOSDeviceDismissed(alert.deviceID)
        }
        activeSOSAlerts.removeAll { $0.id == sosId }
        server.activeSOSAlerts.removeAll { $0.id == sosId }
        if activeSOSAlerts.isEmpty { showSOSOverlay = false }
    }

    // MARK: - 角色切換

    func switchRole(_ role: HQRole) {
        guard hqRole != role else { return }
        hqRole = role
        if role == .server {
            // 停止 peer 模式
            peerCancellables.removeAll()
            peerClient.disconnect()
            peerClient.stopBrowsing()
            // 初始化 WhisperKit（若尚未載入）
            if !udpAudioServer.whisperReady {
                Task {
                    await initializeWhisperWithRetry()
                }
            }
            // 啟動所有本地伺服器
            startAllLocalServers()
        } else {
            // 停止所有本地伺服器，啟動 peer 瀏覽
            stopAllLocalServers()
            setupPeerBindings()
            peerClient.startBrowsing()
        }
    }

    private func setupPeerBindings() {
        peerCancellables.removeAll()

        peerClient.$sentCommands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cmds in self?.commandHistory = cmds.map { $0.toCommandOrder() } }
            .store(in: &peerCancellables)

        peerClient.$chatMessages
            .receive(on: DispatchQueue.main)
            .assign(to: &$chatMessages)

        peerClient.$disasterSite
            .receive(on: DispatchQueue.main)
            .assign(to: &$disasterSite)

        peerClient.$personnelAssignments
            .receive(on: DispatchQueue.main)
            .assign(to: &$personnelAssignments)

        peerClient.$pwsAlerts
            .receive(on: DispatchQueue.main)
            .assign(to: &$pwsAlerts)

        peerClient.$briefings
            .receive(on: DispatchQueue.main)
            .assign(to: &$briefings)

        peerClient.$personalNotifications
            .receive(on: DispatchQueue.main)
            .assign(to: &$personalNotifications)

        peerClient.$tasks
            .receive(on: DispatchQueue.main)
            .assign(to: &$tasks)

        peerClient.$countdownTimers
            .receive(on: DispatchQueue.main)
            .assign(to: &$countdownTimers)

        peerClient.$hazardReports
            .receive(on: DispatchQueue.main)
            .assign(to: &$hazardReports)

        peerClient.$reinforcementRequests
            .receive(on: DispatchQueue.main)
            .assign(to: &$reinforcementRequests)

        peerClient.$activeSOSAlerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alerts in
                self?.activeSOSAlerts = alerts
                if !alerts.isEmpty {
                    self?.showSOSOverlay = true
                }
            }
            .store(in: &peerCancellables)

        peerClient.$radioReports
            .receive(on: DispatchQueue.main)
            .assign(to: &$radioReports)

        peerClient.$currentBroadcaster
            .receive(on: DispatchQueue.main)
            .sink { [weak self] broadcaster in
                self?.currentBroadcaster = broadcaster
                self?.audioStreamServer.isPlaying = broadcaster != nil
                self?.audioStreamServer.currentSender = broadcaster
            }
            .store(in: &peerCancellables)

        peerClient.$serverStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.peerBackendConnected = status?.backendConnected ?? false
                guard let status else { return }
                // 同步音訊伺服器狀態
                self.udpAudioServer.isRunning = status.udpServerRunning ?? false
                self.audioStreamServer.isRunning = status.audioStreamRunning ?? false
                // 同步即時轉錄資料
                if let live = status.liveTranscriptions {
                    self.udpAudioServer.liveTranscriptions = live
                }
                if let finals = status.finalTranscriptions {
                    self.udpAudioServer.finalTranscriptions = finals
                }
                if let states = status.transcriptionStates {
                    self.udpAudioServer.transcriptionStates = states.compactMapValues { str in
                        switch str {
                        case "listening": return .listening
                        case "processing": return .processing
                        case "done": return .done
                        default: return .idle
                        }
                    }
                }
                if let count = status.udpConnectedClientCount {
                    self.udpAudioServer.connectedClientCount = count
                }
                if let playing = status.audioStreamIsPlaying {
                    self.audioStreamServer.isPlaying = playing
                }
                if let sender = status.audioStreamCurrentSender {
                    self.audioStreamServer.currentSender = sender
                }
            }
            .store(in: &peerCancellables)
    }

    // MARK: - 伺服器控制

    /// 啟動指揮伺服器（TCP 命令 + UDP 音訊 + 音訊轉發）
    func startServer() {
        guard hqRole == .server else { return }
        startAllLocalServers()
    }
    func stopServer() {
        stopAllLocalServers()
    }

    /// 啟動所有本地伺服器（server 模式專用）
    private func startAllLocalServers() {
        #if os(macOS)
        ensureMacLocalBackend()
        #endif
        server.statusSnapshotProvider = { [weak self] in
            self?.buildServerStatusSnapshot() ?? HQServerStatusSnapshot(
                speechServerRunning: false, speechProcessedCount: 0,
                photoServerRunning: false, photoReceivedCount: 0,
                backendConnected: false, backendHost: "",
                audioStreamRunning: false, udpServerRunning: false,
                fieldUnitCount: 0, onlineFieldUnitCount: 0,
                totalVictimCount: 0, onlineVictimCount: 0,
                sosCount: 0, teamCount: 0, fieldUnits: []
            )
        }
        server.start()
        udpAudioServer.startListening()
        audioStreamServer.start()
        speechServer.start()
        photoServer.start()
        server.startLocalStatsTimer()
    }

    #if os(macOS)
    /// Ensures every backend/AI feature uses the Mac-local Python sidecar.
    func ensureMacLocalBackend() {
        guard hqRole == .server, backendMode == .embedded else { return }
        server.backendBridge = backendBridge
        backendBridge.server = server

        if backendSupervisor.services.allSatisfy({ $0.status == .stopped }) {
            backendSupervisor.startAll()
        }

        if backendBridge.backendHost != "127.0.0.1" || (!backendBridge.isConnected && !backendBridge.isConnecting) {
            backendBridge.connect(host: "127.0.0.1", port: 9000)
        }
    }
    #endif

    /// 建立伺服器狀態快照（供 peer 同步）
    private func buildServerStatusSnapshot() -> HQServerStatusSnapshot {
        HQServerStatusSnapshot(
            speechServerRunning: speechServer.isRunning,
            speechProcessedCount: speechServer.processedCount,
            photoServerRunning: photoServer.isRunning,
            photoReceivedCount: photoServer.receivedCount,
            backendConnected: backendBridge.isConnected,
            backendHost: backendBridge.backendHost,
            audioStreamRunning: audioStreamServer.isRunning,
            udpServerRunning: udpAudioServer.isRunning,
            liveTranscriptions: udpAudioServer.liveTranscriptions,
            finalTranscriptions: udpAudioServer.finalTranscriptions,
            transcriptionStates: udpAudioServer.transcriptionStates.mapValues { state in
                switch state {
                case .idle: return "idle"
                case .listening: return "listening"
                case .processing: return "processing"
                case .done: return "done"
                }
            },
            audioStreamIsPlaying: audioStreamServer.isPlaying,
            audioStreamCurrentSender: audioStreamServer.currentSender,
            udpConnectedClientCount: udpAudioServer.connectedClientCount,
            fieldUnitCount: server.fieldUnits.count,
            onlineFieldUnitCount: server.onlineFieldUnitCount,
            totalVictimCount: server.allVictims.count,
            onlineVictimCount: server.onlineVictimCount,
            sosCount: server.totalSOSCount,
            teamCount: server.allTeamMembers.count,
            fieldUnits: server.fieldUnits.map { unit in
                FieldUnitSummary(
                    id: unit.id, deviceID: unit.deviceID,
                    deptCode: unit.deptCode, battery: unit.battery,
                    bleConnected: unit.bleConnected,
                    victimCount: unit.victims.count,
                    teamCount: unit.teamMembers.count,
                    sosCount: unit.sosCount,
                    lastUpdate: unit.lastUpdate.timeIntervalSince1970,
                    isOnline: unit.isOnline
                )
            }
        )
    }

    /// 停止所有本地伺服器
    private func stopAllLocalServers() {
        server.stop()
        udpAudioServer.stopListening()
        audioStreamServer.stop()
        speechServer.stop()
        photoServer.stop()
    }

    func toggleServer() {
        if hqRole == .peer { return }
        server.isRunning ? stopServer() : startServer()
    }

    // MARK: - 發送命令

    func sendCustomCommand() {
        let t = commandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = commandDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        let cmd = WiFiCommand(
            id: UUID().uuidString,
            type: selectedType.key,
            priority: selectedPriority.rawValue,
            title: t, detail: d.isEmpty ? t : d,
            sender: senderName,
            timestamp: Date().timeIntervalSince1970
        )

        if hqRole == .peer {
            peerClient.sendCommand(cmd)
        } else {
            server.sendCommand(
                type: cmd.type, priority: cmd.priority,
                title: cmd.title, detail: cmd.detail,
                sender: cmd.sender, targetDeviceIDs: effectiveTargetIDs
            )
            // 同時透過 HQ LoRa 廣播命令
            if bluetoothManager.isConnected {
                bluetoothManager.sendCommand(
                    cmdId: cmd.id,
                    type: cmd.type,
                    priority: cmd.priority,
                    title: cmd.title,
                    detail: cmd.detail
                )
            }
        }

        logEvent(type: .command, title: L("發送命令：%@", t), detail: d.isEmpty ? t : d)
        commandTitle = ""
        commandDetail = ""
    }

    func sendQuickCommand(_ template: QuickCommand) {
        let localizedTitle = L(template.title)
        let localizedDetail = L(template.detail)
        if hqRole == .peer {
            let cmd = WiFiCommand(
                id: UUID().uuidString,
                type: template.type,
                priority: template.priority,
                title: localizedTitle,
                detail: localizedDetail,
                sender: senderName,
                timestamp: Date().timeIntervalSince1970
            )
            peerClient.sendCommand(cmd)
        } else {
            server.sendCommand(
                type: template.type,
                priority: template.priority,
                title: localizedTitle,
                detail: localizedDetail,
                sender: senderName,
                targetDeviceIDs: effectiveTargetIDs
            )

            if bluetoothManager.isConnected {
                bluetoothManager.sendCommand(
                    cmdId: UUID().uuidString,
                    type: template.type,
                    priority: template.priority,
                    title: localizedTitle,
                    detail: localizedDetail
                )
            }
        }
        logEvent(type: .command, title: L("快速命令：%@", localizedTitle), detail: localizedDetail)
    }

    var canSendCommand: Bool {
        (hqRole == .server ? server.isRunning : peerClient.isConnected)
            && !commandTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// HQ 是否可操作（伺服器模式已啟動 或 副指揮已連線）
    var isHQActive: Bool {
        hqRole == .server ? server.isRunning : peerClient.isConnected
    }

    // MARK: - 聊天

    func sendChat(_ text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let mentions = parseMentionsFromText(content)
        let chat = ChatMessage(senderID: "HQ", senderName: senderName, content: content, mentions: mentions)
        if hqRole == .peer {
            peerClient.sendChat(chat)
        } else {
            server.sendChatFromHQ(chat)
        }
        chatDraft = ""
        logEvent(type: .chat, title: L("HQ 發送訊息"), detail: content)
    }

    /// 從訊息文字解析 @ 提及，對比 personnelAssignments 後回傳對應 id 列表
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
            let hit = personnelAssignments.first { $0.nickname == tok }
                ?? personnelAssignments.first { $0.name == tok }
                ?? personnelAssignments.first { $0.id == tok }
                ?? personnelAssignments.first { $0.id.hasSuffix(tok) && tok.count >= 3 }
            if let h = hit, !seen.contains(h.id) {
                seen.insert(h.id)
                out.append(h.id)
            }
        }
        return out
    }

    // MARK: - 災害狀態

    func updateDisasterSite(_ site: DisasterSite) {
        disasterSite = site
        server.disasterSite = site
        server.broadcastDisasterUpdate(site, targetDeviceIDs: effectiveTargetIDs)
        logEvent(type: .disaster, title: L("更新災害狀態"), detail: "\(site.buildingName) · \(site.collapseType.label)")
    }

    func addRescueZone(_ zone: RescueZone) {
        disasterSite?.zones.append(zone)
        if let site = disasterSite {
            server.disasterSite = site
            server.broadcastDisasterUpdate(site)
        }
    }

    func updateFloorStatus(_ floor: FloorStatus) {
        if let idx = disasterSite?.floors.firstIndex(where: { $0.id == floor.id }) {
            disasterSite?.floors[idx] = floor
        } else {
            disasterSite?.floors.append(floor)
        }
        if let site = disasterSite {
            server.disasterSite = site
            server.broadcastDisasterUpdate(site)
        }
    }

    // MARK: - 人員配置

    func assignPersonnel(_ assignment: PersonnelAssignment) {
        if let idx = personnelAssignments.firstIndex(where: { $0.id == assignment.id }) {
            personnelAssignments[idx] = assignment
        } else {
            personnelAssignments.append(assignment)
        }
        server.personnelAssignments = personnelAssignments
        server.broadcastPersonnelAssignment(personnelAssignments, targetDeviceIDs: effectiveTargetIDs)
        logEvent(type: .personnel, title: L("配置人員：%@", assignment.name), detail: "\(assignment.role.label) → \(assignment.assignedZone.isEmpty ? L("未指定") : assignment.assignedZone)")
    }

    func removePersonnelAssignment(_ id: String) {
        guard !id.hasPrefix("field-") else { return } // 前線自動同步的人員不可刪除
        let name = personnelAssignments.first(where: { $0.id == id })?.name ?? id
        personnelAssignments.removeAll { $0.id == id }
        server.personnelAssignments = personnelAssignments
        logEvent(type: .personnel, title: L("移除人員：%@", name))
    }

    // MARK: - PWS 警報

    func addPWSAlert(_ alert: PWSAlert) {
        pwsAlerts.insert(alert, at: 0)
        server.pwsAlerts = pwsAlerts
        server.broadcastPWSAlert(alert, targetDeviceIDs: effectiveTargetIDs)
        logEvent(type: .pwsAlert, title: L("發布警報：%@", alert.title), detail: "\(alert.alertType.label) · \(alert.severity.label)")
    }

    func deactivatePWSAlert(_ id: String) {
        if let idx = pwsAlerts.firstIndex(where: { $0.id == id }) {
            let title = pwsAlerts[idx].title
            pwsAlerts[idx].isActive = false
            server.pwsAlerts = pwsAlerts
            logEvent(type: .pwsAlert, title: L("解除警報：%@", title))
        }
    }

    // MARK: - 會報

    func addBriefing(_ report: BriefingReport) {
        briefings.insert(report, at: 0)
        server.briefings = briefings
        server.broadcastBriefing(report, targetDeviceIDs: effectiveTargetIDs)
        logEvent(type: .briefing, title: L("新增會報：%@", report.title), detail: report.type.label)
    }

    // MARK: - 個人通知

    func sendNotification(_ notification: PersonalNotification) {
        personalNotifications.insert(notification, at: 0)
        server.personalNotifications = personalNotifications
        server.sendPersonalNotification(notification)
        logEvent(type: .notification, title: L("發送通知：%@", notification.title), detail: "→ \(notification.targetDeviceID)")
    }

    // MARK: - 任務指派

    func assignTask(_ task: TaskAssignment) {
        tasks.insert(task, at: 0)
        if hqRole == .peer {
            peerClient.assignTask(task)
        } else {
            server.tasks = tasks
            server.broadcastTaskAssignment(task, targetDeviceIDs: effectiveTargetIDs)
        }
        logEvent(type: .command, title: L("指派任務：%@", task.title), detail: "→ \(task.assigneeName)")
    }

    func cancelTask(_ taskID: String) {
        if let idx = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[idx].status = TaskStatus.cancelled.rawValue
            server.tasks = tasks
        }
    }

    var activeTaskCount: Int { tasks.filter(\.isActive).count }

    // MARK: - 倒數計時器

    func startTimer(title: String, durationSeconds: Int, isBroadcast: Bool = true, targetDeviceID: String = "") {
        let timer = CountdownTimerModel(title: title, durationSeconds: durationSeconds, isBroadcast: isBroadcast, targetDeviceID: targetDeviceID)
        countdownTimers.append(timer)
        if hqRole == .peer {
            peerClient.startTimer(timer)
        } else {
            server.countdownTimers = countdownTimers
            server.broadcastTimerSync(timer, targetDeviceIDs: effectiveTargetIDs)
        }
        logEvent(type: .command, title: L("啟動計時器：%@", title), detail: L("%lld 分鐘", durationSeconds / 60))
    }

    func cancelTimer(_ timerID: String) {
        countdownTimers.removeAll { $0.id == timerID }
        if hqRole == .peer {
            peerClient.cancelTimer(timerID)
        } else {
            server.countdownTimers = countdownTimers
            server.broadcastTimerCancel(timerID, targetDeviceIDs: effectiveTargetIDs)
        }
        logEvent(type: .command, title: L("取消計時器"))
    }

    // MARK: - 增援請求

    func approveReinforcement(_ request: ReinforcementRequest) {
        if let idx = reinforcementRequests.firstIndex(where: { $0.id == request.id }) {
            reinforcementRequests[idx].status = .accepted
            reinforcementRequests[idx].respondedBy.append("HQ")
            server.reinforcementRequests = reinforcementRequests
            server.broadcastReinforcementResponse(reinforcementRequests[idx])
            logEvent(type: .command, title: L("批准增援：%@", request.fromTeam), detail: request.message)
        }
    }

    func declineReinforcement(_ request: ReinforcementRequest) {
        if let idx = reinforcementRequests.firstIndex(where: { $0.id == request.id }) {
            reinforcementRequests[idx].status = .declined
            reinforcementRequests[idx].respondedBy.append("HQ")
            server.reinforcementRequests = reinforcementRequests
            server.broadcastReinforcementResponse(reinforcementRequests[idx])
            logEvent(type: .command, title: L("拒絕增援：%@", request.fromTeam), detail: request.message)
        }
    }

    var pendingReinforcementCount: Int { reinforcementRequests.filter { $0.status == .pending }.count }

    // MARK: - 指揮決策

    func sendDecision(decision: String, patients: [PatientDecisionEntry]) {
        // 從後台取得氣象快照
        let weather: HQWeatherSnapshot? = {
            guard let w = backendBridge.backendWeather else { return nil }
            return HQWeatherSnapshot(temp: w.temperature, humidity: w.humidity, wind: w.windSpeed, rainfall: w.rainfall)
        }()
        let payload = HQDecisionPayload(
            decision: decision,
            patients: patients,
            trigger: "manual",
            weather: weather,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        if hqRole == .peer {
            peerClient.sendDecision(payload)
        } else {
            server.broadcastDecision(payload, targetDeviceIDs: effectiveTargetIDs)
        }
        logEvent(type: .command, title: L("發送決策"), detail: decision)
    }

    private func applyLocalSTARTTriage(from reports: [PatientReport]) {
        for report in reports {
            let triage = localStartTriage(report)
            victimTriageReasons[report.patientId] = triage.reason

            let current = victimPriorities[report.patientId] ?? .unset
            if autoTriageManagedVictimIDs.contains(report.patientId) || current == .unset {
                victimPriorities[report.patientId] = triage.priority
                autoTriageManagedVictimIDs.insert(report.patientId)
            }

            if (victimNotes[report.patientId] ?? "").isEmpty {
                victimNotes[report.patientId] = triage.reason
            }
        }
    }

    private func localStartTriage(_ report: PatientReport) -> (priority: VictimPriority, reason: String) {
        if report.breathingRate == -1 {
            return (.low, "START 黑色：無呼吸（優先維持現場記錄）")
        }
        if report.breathingRate > 30 {
            return (.critical, "START 紅色：呼吸大於 30 次/分")
        }
        if report.capillaryRefill > 2 || report.capillaryRefill == -1 {
            return (.critical, "START 紅色：微血管回填 > 2 秒或無橈動脈脈搏")
        }
        if !report.canFollowCommands {
            return (.critical, "START 紅色：無法遵從指令")
        }
        return (.low, "START 綠色：三項檢查正常")
    }

    /// 向後台 AI 請求生成決策建議
    func requestAIDecision(context: String = "") {
        if hqRole == .peer {
            peerClient.requestAIDecision(context: context)
        } else {
            #if os(macOS)
            ensureMacLocalBackend()
            if backendMode == .embedded, !backendBridge.isConnected {
                backendBridge.isRequestingAI = true
                backendBridge.lastError = nil
                Task { [weak self] in
                    guard let self else { return }
                    for _ in 0..<40 {
                        if self.backendBridge.isConnected {
                            self.backendBridge.requestAIDecision(context: context)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                    self.backendBridge.isRequestingAI = false
                    self.backendBridge.lastError = "本機 TCP 後端尚未連線（127.0.0.1:9000），請在後端服務頁確認 TCP Aggregator 已啟動"
                }
                return
            }
            #endif
            backendBridge.requestAIDecision(context: context)
        }
        logEvent(type: .command, title: L("請求 AI 決策"), detail: context.isEmpty ? L("（無額外情境）") : context.prefix(60) + "...")
    }

    // MARK: - AI 副駕駛指令提案（HITL）

    /// 指揮官審批 AI 提案，透過 HQCommandServer 廣播指令
    func executeAIProposal(_ proposal: AIProposal) {
        guard !executedProposalIDs.contains(proposal.id),
              !ignoredProposalIDs.contains(proposal.id) else { return }

        let targets = proposal.targets.isEmpty ? nil : proposal.targets
        server.sendCommand(
            type: proposal.type,
            priority: proposal.priority,
            title: proposal.title,
            detail: proposal.detail,
            sender: "AI 副駕駛（HQ 審批）",
            targetDeviceIDs: targets
        )
        executedProposalIDs.insert(proposal.id)
        logEvent(
            type: .command,
            title: "AI 指令已執行：\(proposal.title)",
            detail: proposal.rationale.isEmpty ? proposal.detail : proposal.rationale,
            source: "AI 副駕駛"
        )
        ackProposalToBackend(proposal.id)
    }

    /// 指揮官選擇忽略 AI 提案
    func ignoreAIProposal(_ proposal: AIProposal) {
        guard !executedProposalIDs.contains(proposal.id) else { return }
        ignoredProposalIDs.insert(proposal.id)
        logEvent(
            type: .command,
            title: "AI 指令已忽略：\(proposal.title)",
            detail: proposal.rationale,
            source: "AI 副駕駛"
        )
    }

    /// 背景通知後端「此提案已被執行」（觀測點，不影響 UI）
    private func ackProposalToBackend(_ proposalID: String) {
        let host = effectiveBackendHost
        guard !host.isEmpty,
              let url = makeBackendURL(host: host, port: 8001, path: "/command/ack") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command_id": proposalID])
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // MARK: - 事件日誌

    func logEvent(type: TimelineEventType, title: String, detail: String = "", source: String = "HQ") {
        server.appendTimelineEvent(TimelineEvent(eventType: type, title: title, detail: detail, source: source))
    }

    func clearTimeline() {
        server.timelineEvents.removeAll()
    }
}

// MARK: - 快速命令模板

struct QuickCommand: Identifiable {
    let id = UUID()
    let type: String
    let priority: Int
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

let quickCommands: [QuickCommand] = [
    QuickCommand(type: "search", priority: 0, title: "開始搜索",
                 detail: "請全體搜索隊伍開始展開各分區搜索作業",
                 icon: "magnifyingglass", color: NV.info),
    QuickCommand(type: "standby", priority: 0, title: "原地待命",
                 detail: "暫停所有作業，等待進一步指令",
                 icon: "pause.circle.fill", color: NV.warning),
    QuickCommand(type: "evacuation", priority: 2, title: "全員撤離",
                 detail: "發布撤離命令，所有人員立即撤離至集結點",
                 icon: "arrow.uturn.backward.circle.fill", color: NV.danger),
    QuickCommand(type: "report", priority: 0, title: "回報現況",
                 detail: "各隊伍請回報目前人員位置及搜索進度",
                 icon: "doc.text.fill", color: NV.command),
    QuickCommand(type: "support", priority: 1, title: "請求醫療支援",
                 detail: "需要醫療人員至指定地點進行傷患處理",
                 icon: "cross.fill", color: NV.danger),
    QuickCommand(type: "support", priority: 1, title: "請求重機具",
                 detail: "需要吊車或破碎機至現場協助排除障礙",
                 icon: "wrench.and.screwdriver.fill", color: NV.reinforce),
    QuickCommand(type: "rotate", priority: 0, title: "輪替休息",
                 detail: "外圍待命隊接手，前線隊伍後撤休息補水",
                 icon: "arrow.2.squarepath", color: NV.team),
    QuickCommand(type: "assembly", priority: 0, title: "集合點報",
                 detail: "全體人員至集結點集合進行人員清點",
                 icon: "person.3.sequence.fill", color: NV.green),
    QuickCommand(type: "hazard", priority: 1, title: "危險警告",
                 detail: "偵測到結構不穩/瓦斯外洩，請注意安全",
                 icon: "exclamationmark.shield.fill", color: NV.danger),
    QuickCommand(type: "comm_check", priority: 0, title: "通訊測試",
                 detail: "各隊伍確認通訊是否正常，依序回報",
                 icon: "antenna.radiowaves.left.and.right", color: NV.info),
]


extension Notification.Name {
    static let whisperTranscriptionReceived = Notification.Name("whisperTranscriptionReceived")
}
