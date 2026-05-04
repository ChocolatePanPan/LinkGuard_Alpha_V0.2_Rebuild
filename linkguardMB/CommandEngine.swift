import Foundation
import Network
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - WiFi 雙向訊息協議

/// 包裝所有 WiFi 雙向通訊的訊息類型
struct WiFiMessage: Codable {
    let msgType: String     // "command", "status_report", "command_history"
    let deviceID: String    // 發送方裝置 ID（供 Python server 路由；Mac HQ 端可忽略）
    let payload: String     // JSON 編碼的 payload
}

/// 前線 App → 指揮中心：裝置狀態報告
struct FieldStatusReport: Codable {
    let deviceID: String
    let deptCode: String
    let battery: Int
    let bleConnected: Bool
    let victims: [VictimSummary]
    let teamMembers: [TeamSummary]
    let sosCount: Int
    let timestamp: Double
    /// 前線裝置自身作為救援人員的配置資訊
    let selfPersonnel: PersonnelAssignment?
}

struct VictimSummary: Codable, Identifiable {
    let id: String
    let heartRate: Int
    let battery: Int
    let rssi: Double
    let isSOS: Bool
    let isOnline: Bool
}

struct TeamSummary: Codable, Identifiable {
    let id: String
    let deptCode: String
    let battery: Int
    let rssi: Double
    let isOnline: Bool
    let victimCount: Int
}

// MARK: - WiFi 命令協議（JSON 格式）

/// WiFi 傳輸用的命令結構（Codable，iOS/Android 共用格式）
struct WiFiCommand: Codable, Identifiable {
    let id: String
    let type: String        // search, standby, support, report, evacuation
    let priority: Int       // 0=routine, 1=urgent, 2=critical
    let title: String
    let detail: String
    let sender: String
    let timestamp: Double   // Unix timestamp (seconds)

    /// 轉換為 App 內部的 CommandOrder
    func toCommandOrder() -> CommandOrder {
        let cmdType = CommandType.fromKey(type) ?? .statusReport
        let cmdPri = CommandPriority(rawValue: priority) ?? .routine
        return CommandOrder(
            id: UUID(uuidString: id) ?? UUID(),
            type: cmdType,
            priority: cmdPri,
            title: title,
            detail: detail,
            sender: sender,
            time: Date(timeIntervalSince1970: timestamp),
            isRead: false
        )
    }
}

// MARK: - WiFi 命令伺服器（Mac / iPad 指揮中心用）

/// 在 Mac / iPad 上運行的 HTTP 命令伺服器
/// 前線裝置（iPhone / Android）透過 WiFi 連線接收命令
class CommandServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var sentCommands: [WiFiCommand] = []

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 8930
    private let queue = DispatchQueue(label: "com.linkguard.cmdserver")

    /// 啟動命令伺服器（Bonjour 自動廣播）
    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                print("[CMD-Server] Invalid port: \(port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
            listener?.service = NWListener.Service(name: "LinkGuard-Field", type: "_linkguard-field._tcp")

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[CMD-Server] Ready on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.isRunning = false
                        print("[CMD-Server] Failed: \(error)")
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("[CMD-Server] Start failed: \(error)")
        }
    }

    /// 停止伺服器
    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }

    /// 廣播命令給所有前線裝置
    func broadcastCommand(_ command: WiFiCommand) {
        DispatchQueue.main.async {
            self.sentCommands.insert(command, at: 0)
            if self.sentCommands.count > 100 {
                self.sentCommands = Array(self.sentCommands.prefix(100))
            }
        }

        guard let data = try? JSONEncoder().encode(command) else { return }
        // 加上換行作為訊息分隔符
        let message = data + Data([0x0A])

        queue.async { [weak self] in
            guard let self else { return }
            // 清理已斷線的連線
            // NWError 不正確支援 ==，使用 pattern match 判斷 .failed/.cancelled
            self.connections.removeAll { conn in
                if case .failed = conn.state { return true }
                if case .cancelled = conn.state { return true }
                return false
            }
            DispatchQueue.main.async { self.connectedClients = self.connections.count }

            for conn in self.connections {
                conn.send(content: message, completion: .contentProcessed { error in
                    if let error {
                        print("[CMD-Server] Send failed: \(error)")
                    }
                })
            }
            print("[CMD-Server] Broadcast to \(self.connections.count) clients: \(command.title)")
        }
    }

    /// 建立新命令並廣播
    func sendCommand(type: String, priority: Int, title: String, detail: String, sender: String = "HQ-Alpha") {
        let cmd = WiFiCommand(
            id: UUID().uuidString,
            type: type,
            priority: priority,
            title: title,
            detail: detail,
            sender: sender,
            timestamp: Date().timeIntervalSince1970
        )
        broadcastCommand(cmd)
    }

    // MARK: - 連線處理

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[CMD-Server] Client connected")
                self.queue.async {
                    self.connections.append(connection)
                    DispatchQueue.main.async { self.connectedClients = self.connections.count }
                }
                // 送出歷史命令（最近 10 筆）
                self.sendHistory(to: connection)
                self.receiveData(from: connection)
            case .failed, .cancelled:
                print("[CMD-Server] Client disconnected")
                self.queue.async {
                    self.connections.removeAll { $0 === connection }
                    DispatchQueue.main.async { self.connectedClients = self.connections.count }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func sendHistory(to connection: NWConnection) {
        let recent = Array(sentCommands.prefix(10))
        guard !recent.isEmpty, let data = try? JSONEncoder().encode(recent) else { return }
        let message = data + Data([0x0A])
        connection.send(content: message, completion: .contentProcessed { _ in })
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            if error != nil { return }
            // 目前前線端不需要回傳資料，但保持接收迴圈以偵測斷線
            self?.receiveData(from: connection)
        }
    }
}

// MARK: - WiFi 命令接收器（iPhone / Android 前線裝置用）

/// iPhone 前線裝置：透過 Bonjour 自動發現指揮中心，接收 WiFi 命令
/// HQ 伺服器狀態快照（前線裝置接收用）
struct HQServerStatus: Codable {
    var audioStreamRunning: Bool?
    var udpServerRunning: Bool?
    var speechServerRunning: Bool?
    var photoServerRunning: Bool?
    var backendConnected: Bool?
    var aiServicePaused: Bool?
    var aiServicePauseReason: String?
}

class CommandClient: ObservableObject {
    @Published var isConnected = false
    @Published var serverName: String?
    /// 連線中的 HQ 實際 IP（用於 UDP 等需要直接 IP 的場景）
    @Published var resolvedIP: String?
    /// HQ 伺服器狀態（串流伺服器、UDP 等）
    @Published var hqServerStatus: HQServerStatus?

    /// 收到新命令的回呼
    var onCommand: ((WiFiCommand) -> Void)?
    /// 收到聊天訊息的回呼
    var onChatMessage: ((ChatMessage) -> Void)?
    /// 收到災害狀態更新
    var onDisasterUpdate: ((DisasterSite) -> Void)?
    /// 收到人員配置
    var onPersonnelAssignment: (([PersonnelAssignment]) -> Void)?
    /// 收到 PWS 警報
    var onPWSAlert: ((PWSAlert) -> Void)?
    /// 收到會報
    var onBriefing: ((BriefingReport) -> Void)?
    /// 收到個人通知
    var onPersonalNotification: ((PersonalNotification) -> Void)?
    var onQuickStatus: ((QuickStatus) -> Void)?
    var onTaskAssignment: ((TaskAssignment) -> Void)?
    var onTimerSync: ((CountdownTimerModel) -> Void)?
    var onTimerCancel: ((String) -> Void)?
    var onHazardReport: ((HazardReport) -> Void)?
    /// 收到增援請求（其他前線裝置透過 HQ 中繼）
    var onReinforcementRequest: ((ReinforcementRequest) -> Void)?
    /// 收到增援回覆
    var onReinforcementReply: ((ReinforcementRequest) -> Void)?
    /// 收到 HQ 指揮決策
    var onDecision: ((HQDecision) -> Void)?
    /// 收到會報摘要
    var onReportSummary: ((RadioReportSummary) -> Void)?
    /// 收到電台控制（PTT 開始/結束）
    var onRadioControl: ((RadioControlPayload) -> Void)?
    /// 收到照片回報
    var onPhotoReport: ((PhotoReport) -> Void)?
    /// 收到文字廣播中繼
    var onTextBroadcastRx: (([String: Any]) -> Void)?
    /// 收到已讀狀態更新
    var onReadStatus: (([String: Any]) -> Void)?
    /// 收到聊天已讀狀態更新
    var onChatReadStatus: (([String: Any]) -> Void)?
    /// 收到 SOS 警報（其他裝置發出）
    var onSOSAlert: (([String: Any]) -> Void)?
    /// 收到 SOS 取消警報
    var onSOSCancelAlert: (([String: Any]) -> Void)?
    /// 收到傷患惡化預警
    var onPatientWarning: (([String: Any]) -> Void)?
    /// 收到統計更新
    var onStatsUpdate: (([String: Any]) -> Void)?
    /// 收到資源更新
    var onResourceUpdate: (([String: Any]) -> Void)?
    /// 收到翻譯結果
    var onTranslateResult: (([String: Any]) -> Void)?
    /// 收到雙 AI 共識升級觸發（由後端廣播）
    var onEscalationTrigger: (([String: Any]) -> Void)?
    /// 收到通話邀請
    var onCallInvite: ((CallInvite) -> Void)?
    /// 收到通話回覆
    var onCallResponse: ((CallResponse) -> Void)?
    /// 收到通話結束
    var onCallEnd: ((CallEnd) -> Void)?

    private var browsers: [NWBrowser] = []
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.linkguard.cmdclient")
    private var receivedIDs: Set<String> = []
    private var dataBuffer = Data()
    private var pingTimer: Timer?
    private var hasAttemptedAutoConnect = false

    /// 手動連線到指定 IP:Port
    func connectToIP(_ host: String, port: UInt16) {
        stop()
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("[CMD-Client] Invalid port: \(port)")
            return
        }
        let endpoint = NWEndpoint.hostPort(host: nwHost, port: nwPort)
        DispatchQueue.main.async { self.serverName = "\(host):\(port)"; self.resolvedIP = host }
        connectTo(endpoint)
    }

    /// 開始搜尋指揮中心（Bonjour 自動發現）
    func startBrowsing() {
        stop()
        hasAttemptedAutoConnect = false

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        // 只搜尋 HQ 類型服務，避免連到其他前線裝置
        // _linkguard-hq._tcp = Mac HQ, _linkguardpy._tcp = Windows tcp_server
        let serviceTypes = ["_linkguard-hq._tcp", "_linkguardpy._tcp"]
        browsers = serviceTypes.map { type in
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)
            b.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[CMD-Client] Browser ready: \(type)")
                case .failed(let error):
                    print("[CMD-Client] Browser failed (\(type)): \(error)")
                default:
                    break
                }
            }
            b.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                print("[CMD-Client] Browse results (\(type)): \(results.count)")
                guard !self.hasAttemptedAutoConnect else { return }

                // 過濾掉前線裝置（Field）的服務，只連 HQ
                let hqResults = results.filter { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return !name.contains("Field")
                    }
                    return true
                }
                guard let result = hqResults.first else { return }

                self.hasAttemptedAutoConnect = true
                let name: String
                switch result.endpoint {
                case .service(let n, _, _, _):
                    name = n
                default:
                    name = "指揮中心"
                }
                DispatchQueue.main.async { self.serverName = name }
                self.connectTo(result.endpoint)
            }
            return b
        }

        browsers.forEach { $0.start(queue: queue) }
        print("[CMD-Client] Bonjour searching for HQ...")
    }

    /// 停止搜尋並斷線
    func stop() {
        pingTimer?.invalidate()
        pingTimer = nil
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        connection?.cancel()
        connection = nil
        hasAttemptedAutoConnect = false
        DispatchQueue.main.async {
            self.isConnected = false
            self.serverName = nil
            self.resolvedIP = nil
            self.hqServerStatus = nil
        }
    }

    // MARK: - 連線

    private func connectTo(_ endpoint: NWEndpoint) {
        // 避免重複連線
        if connection?.state == .ready { return }
        connection?.cancel()

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        // 強制 IPv4：URLSession 無法正確處理 IPv6 link-local zone ID
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    // 從 TCP 連線取得真正的遠端 IPv4（Bonjour 解析後）
                    if let path = self?.connection?.currentPath,
                       let remote = path.remoteEndpoint,
                       case .hostPort(let host, _) = remote {
                        var ip = "\(host)"
                        // 清理 IPv6 zone ID（如 fe80::1%en0 → fe80::1）
                        if let pct = ip.firstIndex(of: "%") {
                            ip = String(ip[ip.startIndex..<pct])
                        }
                        // 清理 IPv4-mapped IPv6（如 ::ffff:192.168.1.100 → 192.168.1.100）
                        if ip.hasPrefix("::ffff:") {
                            ip = String(ip.dropFirst(7))
                        }
                        self?.resolvedIP = ip
                        print("[CMD-Client] Resolved HQ IP: \(ip)")
                    }
                    print("[CMD-Client] Connected to server")
                    self?.startReceiving()
                    self?.startPing()
                case .failed(let error):
                    self?.isConnected = false
                    print("[CMD-Client] Connection failed: \(error)")
                    // 自動重連
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.connectTo(endpoint)
                    }
                case .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        connection?.start(queue: queue)
    }

    private let maxBufferSize = 1_048_576  // 1MB 上限，防止 OOM

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.dataBuffer.append(data)
                // 防止無界限增長導致 OOM
                if self.dataBuffer.count > self.maxBufferSize {
                    print("[CMD-Client] Buffer overflow (\(self.dataBuffer.count) bytes), clearing")
                    self.dataBuffer.removeAll()
                } else {
                    self.processBuffer()
                }
            }
            if isComplete || error != nil {
                DispatchQueue.main.async { self.isConnected = false }
                return
            }
            self.startReceiving()
        }
    }

    private func processBuffer() {
        while let newlineIndex = dataBuffer.firstIndex(of: 0x0A) {
            let messageData = dataBuffer[dataBuffer.startIndex..<newlineIndex]
            dataBuffer = Data(dataBuffer[dataBuffer.index(after: newlineIndex)...])

            guard !messageData.isEmpty else { continue }

            // 嘗試解析為 WiFiMessage（新協議）
            if let msg = try? JSONDecoder().decode(WiFiMessage.self, from: Data(messageData)) {
                handleWiFiMessage(msg)
            }
            // 向下相容：嘗試解析為單一命令
            else if let cmd = try? JSONDecoder().decode(WiFiCommand.self, from: Data(messageData)) {
                handleCommand(cmd)
            }
            // 嘗試解析為命令陣列（歷史命令）
            else if let cmds = try? JSONDecoder().decode([WiFiCommand].self, from: Data(messageData)) {
                for cmd in cmds { handleCommand(cmd) }
            }
        }
    }

    private func handleWiFiMessage(_ msg: WiFiMessage) {
        guard let payloadData = msg.payload.data(using: .utf8) else { return }

        switch msg.msgType {
        case "command":
            if let cmd = try? JSONDecoder().decode(WiFiCommand.self, from: payloadData) {
                handleCommand(cmd)
            }
        case "chat_message":
            if let chat = try? JSONDecoder().decode(ChatMessage.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onChatMessage?(chat) }
            }
        case "disaster_update":
            if let site = try? JSONDecoder().decode(DisasterSite.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onDisasterUpdate?(site) }
            }
        case "personnel_assignment":
            if let assignments = try? JSONDecoder().decode([PersonnelAssignment].self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onPersonnelAssignment?(assignments) }
            }
        case "pws_alert":
            if let alert = try? JSONDecoder().decode(PWSAlert.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onPWSAlert?(alert) }
            }
        case "briefing":
            if let briefing = try? JSONDecoder().decode(BriefingReport.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onBriefing?(briefing) }
            }
        case "personal_notification":
            if let notif = try? JSONDecoder().decode(PersonalNotification.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onPersonalNotification?(notif) }
            }
        case "quick_status":
            if let qs = try? JSONDecoder().decode(QuickStatus.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onQuickStatus?(qs) }
            }
        case "task_assignment":
            if let task = try? JSONDecoder().decode(TaskAssignment.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onTaskAssignment?(task) }
            }
        case "timer_sync":
            if let timer = try? JSONDecoder().decode(CountdownTimerModel.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onTimerSync?(timer) }
            }
        case "timer_cancel":
            if let idObj = try? JSONDecoder().decode([String: String].self, from: payloadData),
               let timerID = idObj["id"] {
                DispatchQueue.main.async { [weak self] in self?.onTimerCancel?(timerID) }
            }
        case "hazard_report":
            if let hazard = try? JSONDecoder().decode(HazardReport.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onHazardReport?(hazard) }
            }
        case "reinforcement_request":
            if let p = try? JSONDecoder().decode(ReinforcementWirePayload.self, from: payloadData) {
                let statusMap: [String: ReinforcementStatus] = [
                    "待回覆": .pending, "已加入": .accepted, "已拒絕": .declined, "已過期": .expired,
                    "pending": .pending, "joined": .accepted, "accepted": .accepted,
                    "rejected": .declined, "declined": .declined, "expired": .expired
                ]
                let request = ReinforcementRequest(
                    id: UUID(uuidString: p.id) ?? UUID(),
                    fromTeam: p.fromTeam, message: p.message,
                    location: p.location,
                    time: Date(timeIntervalSince1970: p.timestamp),
                    status: statusMap[p.status] ?? .pending,
                    respondedBy: p.respondedBy
                )
                DispatchQueue.main.async { [weak self] in self?.onReinforcementRequest?(request) }
            }
        case "reinforcement_reply":
            if let p = try? JSONDecoder().decode(ReinforcementWirePayload.self, from: payloadData) {
                let statusMap: [String: ReinforcementStatus] = [
                    "待回覆": .pending, "已加入": .accepted, "已拒絕": .declined, "已過期": .expired,
                    "pending": .pending, "joined": .accepted, "accepted": .accepted,
                    "rejected": .declined, "declined": .declined, "expired": .expired
                ]
                let request = ReinforcementRequest(
                    id: UUID(uuidString: p.id) ?? UUID(),
                    fromTeam: p.fromTeam, message: p.message,
                    location: p.location,
                    time: Date(timeIntervalSince1970: p.timestamp),
                    status: statusMap[p.status] ?? .pending,
                    respondedBy: p.respondedBy
                )
                DispatchQueue.main.async { [weak self] in self?.onReinforcementReply?(request) }
            }
        case "decision", "decision_update":
            if let decoded = try? JSONDecoder().decode(HQDecisionPayload.self, from: payloadData) {
                let hqDecision = HQDecision(
                    decision: decoded.decision,
                    patients: decoded.patients,
                    timestamp: decoded.timestamp ?? ISO8601DateFormatter().string(from: Date()),
                    trigger: decoded.trigger ?? "manual",
                    weather: decoded.weather,
                    model: decoded.model ?? "",
                    escalated: decoded.escalated ?? false,
                    requestId: decoded.request_id,
                    provisional: decoded.provisional ?? false,
                    escalationStatus: decoded.escalation_status,
                    queuePosition: decoded.queue_position,
                    estimatedWaitSec: decoded.estimated_wait_sec,
                    smallModelTimeMs: decoded.small_model_time_ms,
                    largeModelTimeMs: decoded.large_model_time_ms,
                    escalationError: decoded.error
                )
                DispatchQueue.main.async { [weak self] in self?.onDecision?(hqDecision) }
            }
        case "report_summary":
            if let summary = try? JSONDecoder().decode(RadioReportSummary.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onReportSummary?(summary) }
            }
        case "radio_control":
            if let ctrl = try? JSONDecoder().decode(RadioControlPayload.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onRadioControl?(ctrl) }
            }
        case "call_invite":
            if let invite = try? JSONDecoder().decode(CallInvite.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onCallInvite?(invite) }
            }
        case "call_response":
            if let response = try? JSONDecoder().decode(CallResponse.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onCallResponse?(response) }
            }
        case "call_end":
            if let end = try? JSONDecoder().decode(CallEnd.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.onCallEnd?(end) }
            }
        case "photo_alert":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let data = json["data"] as? [String: Any] ?? json
                let photoId = data["photo_id"] as? String ?? UUID().uuidString
                let report = PhotoReport(
                    id: photoId,
                    senderName: data["sender_name"] as? String ?? "",
                    lat: data["lat"] as? Double ?? 0,
                    lon: data["lon"] as? Double ?? 0,
                    locationDesc: data["location_desc"] as? String ?? "",
                    caption: data["caption"] as? String ?? "",
                    thumbnailURL: data["thumbnail_url"] as? String ?? "",
                    fullURL: data["full_url"] as? String ?? "",
                    timestamp: ISO8601DateFormatter().date(from: data["timestamp"] as? String ?? "") ?? Date(),
                    mediaType: data["media_type"] as? String ?? "photo"
                )
                DispatchQueue.main.async { [weak self] in self?.onPhotoReport?(report) }
            }
        case "pong":
            break // 心跳回覆，無需處理
        // MARK: - 規範補齊：下行 msgType 接收
        case "text_broadcast_rx":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onTextBroadcastRx?(json) }
            }
        case "escalation_trigger":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onEscalationTrigger?(json) }
            }
        case "read_status":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onReadStatus?(json) }
            }
        case "chat_read_status":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onChatReadStatus?(json) }
            }
        case "sos_alert":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onSOSAlert?(json) }
            }
        case "sos_cancel_alert":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onSOSCancelAlert?(json) }
            }
        case "patient_warning":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onPatientWarning?(json) }
            }
        case "stats_update":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onStatsUpdate?(json) }
            }
        case "resource_update":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onResourceUpdate?(json) }
            }
        case "translate_result":
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onTranslateResult?(json) }
            }
        case "server_status":
            if let status = try? JSONDecoder().decode(HQServerStatus.self, from: payloadData) {
                DispatchQueue.main.async { [weak self] in self?.hqServerStatus = status }
            }
        default:
            break
        }
    }

    private func handleCommand(_ cmd: WiFiCommand) {
        guard !receivedIDs.contains(cmd.id) else { return }
        receivedIDs.insert(cmd.id)

        // 限制記憶體（超過 200 時裁剪，避免累積到 500）
        if receivedIDs.count > 200 {
            receivedIDs = Set(receivedIDs.suffix(100))
        }

        DispatchQueue.main.async { [weak self] in
            self?.onCommand?(cmd)
        }
    }

    // MARK: - 發送狀態報告給指揮中心

    func sendStatusReport(_ report: FieldStatusReport) {
        sendWiFiMessage(msgType: "status_report", payload: report)
    }

    /// 發送聊天訊息到 HQ（由 HQ 中繼轉發）
    func sendChatMessage(_ chat: ChatMessage) {
        sendWiFiMessage(msgType: "chat_message", payload: chat)
    }

    func sendQuickStatus(_ status: QuickStatus) {
        sendWiFiMessage(msgType: "quick_status", payload: status)
    }

    func sendTaskUpdate(_ task: TaskAssignment) {
        sendWiFiMessage(msgType: "task_update", payload: task)
    }

    func sendHazardReport(_ report: HazardReport) {
        sendWiFiMessage(msgType: "hazard_report", payload: report)
    }

    func sendReinforcementRequest(_ request: ReinforcementRequest) {
        let payload = ReinforcementWirePayload(
            id: request.id.uuidString, fromTeam: request.fromTeam,
            message: request.message, location: request.location,
            timestamp: request.time.timeIntervalSince1970,
            status: request.status.rawValue, respondedBy: request.respondedBy
        )
        sendWiFiMessage(msgType: "reinforcement_request", payload: payload)
    }

    func sendReinforcementReply(_ request: ReinforcementRequest) {
        let payload = ReinforcementWirePayload(
            id: request.id.uuidString, fromTeam: request.fromTeam,
            message: request.message, location: request.location,
            timestamp: request.time.timeIntervalSince1970,
            status: request.status.rawValue, respondedBy: request.respondedBy
        )
        sendWiFiMessage(msgType: "reinforcement_reply", payload: payload)
    }

    func sendRadioStart(senderName: String) {
        sendWiFiMessage(msgType: "radio_control", payload: RadioControlPayload(action: "start", senderName: senderName))
    }

    func sendRadioStop(senderName: String) {
        sendWiFiMessage(msgType: "radio_control", payload: RadioControlPayload(action: "stop", senderName: senderName))
    }

    func sendCallInvite(_ invite: CallInvite) {
        sendWiFiMessage(msgType: "call_invite", payload: invite)
    }

    func sendCallResponse(_ response: CallResponse) {
        sendWiFiMessage(msgType: "call_response", payload: response)
    }

    func sendCallEnd(_ end: CallEnd) {
        sendWiFiMessage(msgType: "call_end", payload: end)
    }

    func sendPatientReport(_ report: PatientReport, deviceID: String) {
        // 規範 3.1：傷員回報封包格式
        struct GPSData: Encodable {
            let lat: Double
            let lon: Double
        }
        struct PatientData: Encodable {
            let id: String
            let national_id: String
            let name: String
            let birth_date: String
            let age: Int?
            let breathing_rate: Int
            let capillary_refill: Double
            let can_follow_commands: Bool
            let location: String
            let gps: GPSData?
            let notes: String
            let device_id: String
        }
        let gps: GPSData? = {
            if let lat = report.gpsLat, let lon = report.gpsLon {
                return GPSData(lat: lat, lon: lon)
            }
            return nil
        }()
        let payload = PatientData(
            id: report.patientId,
            national_id: report.nationalId,
            name: report.name,
            birth_date: report.birthDate,
            age: report.age,
            breathing_rate: report.breathingRate,
            capillary_refill: report.capillaryRefill,
            can_follow_commands: report.canFollowCommands,
            location: report.location,
            gps: gps,
            notes: report.notes,
            device_id: deviceID
        )
        sendWiFiMessage(msgType: "patient", payload: payload)
    }

    /// 規範 5.1：GPS 位置更新
    func sendLocation(deviceID: String, lat: Double, lon: Double, accuracy: Double,
                      role: String, name: String, nickname: String? = nil) {
        struct LocationData: Encodable {
            let lat: Double
            let lon: Double
            let accuracy: Double
            let role: String
            let name: String
            let device_id: String
            let nickname: String?
        }
        let payload = LocationData(
            lat: lat, lon: lon, accuracy: accuracy,
            role: role, name: name, device_id: deviceID,
            nickname: nickname?.isEmpty == false ? nickname : nil
        )
        sendWiFiMessage(msgType: "location", payload: payload)
    }

    private func sendWiFiMessage<T: Encodable>(msgType: String, payload: T) {
        guard let conn = connection, conn.state == .ready else { return }
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }

        let msg = WiFiMessage(msgType: msgType, deviceID: currentDeviceID, payload: payloadJSON)
        guard let data = try? JSONEncoder().encode(msg) else { return }
        let message = data + Data([0x0A])

        conn.send(content: message, completion: .contentProcessed { error in
            if let error { print("[CMD-Client] Send \(msgType) failed: \(error)") }
        })
    }

    // MARK: - 原始 JSON 發送（SOS / 照片等 — 包裝為 WiFiMessage）

    func sendRawJSON(_ payload: [String: Any]) {
        guard let conn = connection, conn.state == .ready else { return }
        // 取出 type 作為 msgType，整個 payload 序列化為 payload 字串
        let msgType = payload["type"] as? String ?? "unknown"
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }
        let msg = WiFiMessage(msgType: msgType, deviceID: currentDeviceID, payload: payloadJSON)
        guard let data = try? JSONEncoder().encode(msg) else { return }
        let message = data + Data([0x0A])
        conn.send(content: message, completion: .contentProcessed { error in
            if let error { print("[CMD-Client] SendRaw \(msgType) failed: \(error)") }
        })
    }

    private var currentDeviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "device_id") { return stored }
        #if canImport(UIKit)
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString { return vendorID }
        #endif
        return "unknown"
    }

    /// 發送 SOS 緊急呼叫
    func sendSOS(senderName: String) {
        sendRawJSON([
            "type": "sos",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "sender_name": senderName,
                "device_id": currentDeviceID,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ] as [String: Any],
        ])
    }

    /// 取消 SOS
    func sendSOSCancel(sosId: String) {
        sendRawJSON([
            "type": "sos_cancel",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "sos_id": sosId,
                "device_id": currentDeviceID,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ] as [String: Any],
        ])
    }

    /// 發送傷患惡化預警
    func sendPatientWarning(patientId: String, warningType: String, message: String) {
        sendRawJSON([
            "type": "patient_warning",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "patient_id": patientId,
                "warning_type": warningType,
                "message": message,
                "device_id": currentDeviceID,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ] as [String: Any],
        ])
    }

    /// 發送已讀回條
    func sendMessageAck(messageId: String, messageType: String) {
        sendRawJSON([
            "type": "message_ack",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "message_id": messageId,
                "message_type": messageType,
            ] as [String: Any],
        ])
    }

    /// 發送聊天已讀回條
    func sendChatReadReceipt(messageIds: [String]) {
        guard !messageIds.isEmpty else { return }
        sendRawJSON([
            "type": "chat_read_receipt",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "message_ids": messageIds,
                "device_id": currentDeviceID,
            ] as [String: Any],
        ])
    }

    /// 發送文字廣播（指揮官專用）
    func sendTextBroadcast(message: String, senderName: String, priority: String) {
        sendRawJSON([
            "type": "text_broadcast",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "message": message,
                "sender_name": senderName,
                "priority": priority,
            ] as [String: Any],
        ])
    }

    /// 發送翻譯請求
    func sendTranslateRequest(text: String, sourceLang: String, targetLang: String) {
        sendRawJSON([
            "type": "translate_request",
            "device_id": currentDeviceID,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "text": text,
                "source_lang": sourceLang,
                "target_lang": targetLang,
                "context": "medical",
            ] as [String: Any],
        ])
    }

    // MARK: - HQ 遠端控制（iPad 連線 Mac HQ 時，透過 hq_* msgType 下達指令）

    /// 透過 HQ 廣播命令（hq_command → HQ 中繼廣播給所有前線裝置）
    func sendHQCommand(_ cmd: WiFiCommand) {
        sendWiFiMessage(msgType: "hq_command", payload: cmd)
    }

    /// 透過 HQ 啟動計時器
    func sendHQTimerStart(_ timer: CountdownTimerModel) {
        sendWiFiMessage(msgType: "hq_timer_start", payload: timer)
    }

    /// 透過 HQ 取消計時器
    func sendHQTimerCancel(timerID: String) {
        sendWiFiMessage(msgType: "hq_timer_cancel", payload: ["id": timerID])
    }

    /// 透過 HQ 指派任務
    func sendHQTaskAssign(_ task: TaskAssignment) {
        sendWiFiMessage(msgType: "hq_task_assign", payload: task)
    }

    // MARK: - Ping 心跳

    private func startPing() {
        pingTimer?.invalidate()
        // 立即發送第一次 ping，使 HQ 盡快完成握手（不等 30 秒）
        sendWiFiMessage(msgType: "ping", payload: ["ts": Date().timeIntervalSince1970])
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendWiFiMessage(msgType: "ping", payload: ["ts": Date().timeIntervalSince1970])
        }
    }
}

/// WiFi 傳輸用增援訊息格式（匹配 HQ Codable 結構）
private struct ReinforcementWirePayload: Codable {
    let id: String
    let fromTeam: String
    let message: String
    let location: String
    let timestamp: Double
    let status: String
    let respondedBy: [String]
}

// MARK: - 模擬命令引擎（Demo Fallback）

/// 當沒有 WiFi 指揮中心時，用 NTP 時間同步產生模擬命令
class SimulatedCommandEngine {

    static let slotDuration: TimeInterval = 20

    private let senders = ["HQ-Alpha", "HQ-Bravo", "CMD-Central", "OPS-South"]

    private let templates: [(type: String, title: String, detail: String, priority: Int)] = [
        ("search",     "搜索 B 區 3F",        "請前往 B 區 3 樓西側走廊進行生命跡象掃描", 0),
        ("search",     "緊急搜索 A 區地下室",   "偵測到微弱訊號，立即前往 A 區 B1 確認", 1),
        ("search",     "擴大搜索範圍至 C 區",   "C 區尚未覆蓋，請擴展掃描", 0),
        ("standby",    "原地待命",             "目前區域安全評估中，請暫停搜索等待指示", 0),
        ("standby",    "暫停推進",             "結構工程師正在評估建物穩定性，所有隊伍原地待命", 1),
        ("support",    "請求醫療支援",          "B 區發現傷者，需要 EMT 支援", 1),
        ("support",    "請求重型設備",          "C 區入口被堵，需要破壞工具", 0),
        ("support",    "緊急增援",             "A 區發現多名受困者，人力不足請立即增援", 2),
        ("report",     "回報搜索進度",          "請各隊伍回報目前搜索完成百分比", 0),
        ("report",     "回報人員狀態",          "請確認隊員健康狀況與裝備電量", 0),
        ("evacuation", "立即撤離",             "偵測到餘震風險，所有人員立即撤離至安全區", 2),
        ("evacuation", "部分撤離 D 區",        "D 區結構不穩，該區人員撤離至集合點", 1),
        ("evacuation", "撤離準備",             "預計 10 分鐘後進行全面撤離，請做好準備", 0),
    ]

    func currentSlotIndex() -> Int {
        Int(Date().timeIntervalSince1970 / Self.slotDuration)
    }

    func nextSlotFireDate() -> Date {
        let now = Date().timeIntervalSince1970
        let next = (floor(now / Self.slotDuration) + 1) * Self.slotDuration
        return Date(timeIntervalSince1970: next)
    }

    func generateCommand(forSlot slot: Int) -> WiFiCommand {
        var state = UInt64(bitPattern: Int64(slot) &* 2654435761)
        func nextRNG() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        let t = templates[Int(nextRNG() % UInt64(templates.count))]
        let s = senders[Int(nextRNG() % UInt64(senders.count))]

        let h = nextRNG()
        let l = nextRNG()
        let bytes = withUnsafeBytes(of: h) { Array($0) } + withUnsafeBytes(of: l) { Array($0) }
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                                bytes[4], bytes[5], bytes[6], bytes[7],
                                bytes[8], bytes[9], bytes[10], bytes[11],
                                bytes[12], bytes[13], bytes[14], bytes[15]))

        return WiFiCommand(
            id: uuid.uuidString,
            type: t.type,
            priority: t.priority,
            title: t.title,
            detail: t.detail,
            sender: s,
            timestamp: Double(slot) * Self.slotDuration
        )
    }
}
