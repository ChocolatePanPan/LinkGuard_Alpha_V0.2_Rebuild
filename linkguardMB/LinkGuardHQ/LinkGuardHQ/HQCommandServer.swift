import Foundation
import Network
import Combine

// MARK: - HQ 命令伺服器（TCP + Bonjour）

/// 指揮中心 WiFi 命令伺服器
/// 前線裝置（iPhone / Android）透過 Bonjour 自動發現並連線
class HQCommandServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var sentCommands: [WiFiCommand] = []
    @Published var fieldUnits: [ConnectedFieldUnit] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var disasterSite: DisasterSite?
    @Published var personnelAssignments: [PersonnelAssignment] = []
    @Published var pwsAlerts: [PWSAlert] = []
    @Published var briefings: [BriefingReport] = []
    @Published var personalNotifications: [PersonalNotification] = []
    @Published var timelineEvents: [TimelineEvent] = []
    @Published var quickStatuses: [QuickStatus] = []
    @Published var statusUpdateSequence: Int = 0
    @Published var tasks: [TaskAssignment] = []
    @Published var countdownTimers: [CountdownTimerModel] = []
    @Published var hazardReports: [HazardReport] = []
    @Published var reinforcementRequests: [ReinforcementRequest] = []
    @Published var patientReports: [PatientReport] = []
    @Published var patientIDConfig = PatientIDConfig()
    @Published var radioReports: [HQRadioReport] = []
    @Published var currentBroadcaster: String?
    @Published var callInvites: [CallInvite] = []
    @Published var activeCallSession: CallSession?
    // Beta-only features
    @Published var photoAlerts: [[String: Any]] = []
    @Published var latestResourceUpdate: [String: Any]?
    @Published var latestStatsUpdate: [String: Any]?
    @Published var textBroadcasts: [HQTextBroadcast] = []
    @Published var patientWarnings: [HQPatientWarning] = []
    @Published var readStatuses: [String: (total: Int, readCount: Int)] = [:]
    @Published var latestTranslation: HQTranslationResult?
    @Published var activeSOSAlerts: [SOSAlert] = []
    /// 前線裝置 GPS 位置 {deviceID: {lat, lon, accuracy, role, name, timestamp}}
    @Published var deviceLocations: [String: [String: Any]] = [:]
    /// 已連線的 HQ 同伴裝置（其他指揮中心）
    @Published var hqPeers: [HQPeerInfo] = []

    /// 收到聊天訊息的回呼（UI 可監聯）
    var onChatReceived: ((ChatMessage) -> Void)?
    /// 收到傷員回報的回呼
    var onPatientReport: ((PatientReport) -> Void)?
    /// 後台橋接器（收到前線資料時自動轉發）
    var backendBridge: HQBackendBridge?
    /// 狀態快照提供者（由 ViewModel 設定，定期發送給 HQ peer）
    var statusSnapshotProvider: (() -> HQServerStatusSnapshot)?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var connectionIDMap: [ObjectIdentifier: String] = [:]
    /// connID → deviceID 對應表（用於個人通知路由）
    private var connDeviceMap: [String: String] = [:]
    /// 已分類為 HQ peer 的 connID 集合
    private var peerConnIDs = Set<String>()
    
    /// Global tracking of known victims
    private var knownVictimIds = Set<String>()
    /// 已讀回條追蹤器：broadcastId -> {"total": N, "readers": [deviceId, ...]}
    private var messageReadTracker: [String: (total: Int, readers: Set<String>)] = [:]
    /// 聊天已讀追蹤器：messageID -> 已讀裝置 Set
    private var chatReadTracker: [String: Set<String>] = [:]
    /// 聊天已讀計數（@Published，供 UI 訂閱）
    @Published var chatReadCounts: [String: Int] = [:]
    /// 已被使用者關閉的 SOS 裝置 ID，防止重複觸發
    private var dismissedSOSDeviceIDs = Set<String>()
    private var callInviteIndex: [String: CallInvite] = [:]

    // MARK: - UDP 音訊中繼
    private var udpAudioListener: NWListener?
    /// 從 UDP 封包直接發現的 field device IP（不依賴 TCP）
    private var knownUDPDeviceIPs: Set<String> = []
    /// IP → 向外的 UDP 連線，重複使用
    private var udpRelayOutgoing: [String: NWConnection] = [:]
    private let udpListenPort: UInt16 = 9001   // Field 發送到此 port
    private let udpRelayPort: UInt16 = 9002    // HQ 中繼到 Field 接收的 port
    private let udpMagic: UInt32 = 0x4C474244 // "LGBD"
    private var udpPacketCount: Int = 0

    /// 從 NWConnection 取得遠端 IP（多重 fallback）
    private func extractIP(from connection: NWConnection) -> String? {
        if let remote = connection.currentPath?.remoteEndpoint,
           case .hostPort(let host, _) = remote {
            return normalizeIP("\(host)")
        }
        if case .hostPort(let host, _) = connection.endpoint {
            return normalizeIP("\(host)")
        }
        return nil
    }

    /// 去除 IP 中的 %interface 後綴（例如 "fe80::1%en0" → "fe80::1"，"192.168.1.5" 不變）
    private func normalizeIP(_ raw: String) -> String {
        raw.components(separatedBy: "%").first ?? raw
    }
    
    private let port: UInt16 = 8930
    private let queue = DispatchQueue(label: "com.linkguard.hqserver")
    /// 連線活性追蹤：connID → 最後收到資料的時間
    private var lastActivity: [String: Date] = [:]
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatInterval: TimeInterval = 15   // 每 15 秒檢查
    private let connectionTimeout: TimeInterval = 45   // 45 秒無活動視為斷線

    // MARK: - 啟動 / 停止

    func start() {
        guard !isRunning, listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = false

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                print("[HQ-Server] ❌ Invalid port: \(port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
            listener?.service = NWListener.Service(name: "LinkGuard-HQ", type: "_linkguard-hq._tcp")

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[HQ-Server] Ready on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.isRunning = false
                        print("[HQ-Server] Failed: \(error)")
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
            startHeartbeat()
            // UDP 音訊中繼已由獨立的 UDPAudioServer 處理
            // startUDPRelay()
        } catch {
            print("[HQ-Server] Start failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // UDP 音訊中繼已由獨立的 UDPAudioServer 處理
        // stopUDPRelay()
        stopHeartbeat()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        connectionIDMap.removeAll()
        lastActivity.removeAll()
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
            self.fieldUnits.removeAll()
            self.hqPeers.removeAll()
        }
    }

    // MARK: - 連線活性心跳

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.checkConnections() }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func checkConnections() {
        let now = Date()
        // 發送 ping 給所有連線
        if let pingData = encodeWiFiMessage(msgType: "ping", payload: ["ts": now.timeIntervalSince1970]) {
            for conn in connections {
                conn.send(content: pingData, completion: .contentProcessed { _ in })
            }
        }
        // 發送伺服器狀態快照給所有連線（HQ peer + 前線裝置）
        if !connections.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self, let snapshot = self.statusSnapshotProvider?() else { return }
                self.queue.async {
                    if let data = self.encodeWiFiMessage(msgType: "server_status", payload: snapshot) {
                        for conn in self.connections {
                            conn.send(content: data, completion: .contentProcessed { _ in })
                        }
                    }
                }
            }
        }
        // 清除超時連線
        let stale = lastActivity.filter { now.timeIntervalSince($0.value) > connectionTimeout }
        for (connID, _) in stale {
            print("[HQ-Server] Connection timeout, removing \(connID)")
            if let conn = connections.first(where: { connectionIDMap[ObjectIdentifier($0)] == connID }) {
                conn.cancel()
            }
        }
    }

    // MARK: - 發送命令

    /// 建立並廣播命令
    func sendCommand(type: String, priority: Int, title: String, detail: String, sender: String = "HQ-Alpha", targetDeviceIDs: [String]? = nil) {
        let cmd = WiFiCommand(
            id: UUID().uuidString,
            type: type, priority: priority,
            title: title, detail: detail,
            sender: sender,
            timestamp: Date().timeIntervalSince1970
        )
        broadcastCommand(cmd, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播命令給所有前線裝置（或指定裝置）
    func broadcastCommand(_ command: WiFiCommand, targetDeviceIDs: [String]? = nil) {
        DispatchQueue.main.async {
            self.sentCommands.insert(command, at: 0)
            if self.sentCommands.count > 100 {
                self.sentCommands = Array(self.sentCommands.prefix(100))
            }
        }

        guard let data = encodeWiFiMessage(msgType: "command", payload: command) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    // MARK: - 連線管理

    private func handleConnection(_ connection: NWConnection) {
        let connID = UUID().uuidString

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[HQ-Server] Client connected (\(connID))")
                self.queue.async {
                    self.connections.append(connection)
                    self.connectionIDMap[ObjectIdentifier(connection)] = connID
                    self.lastActivity[connID] = Date()
                    // 記錄裝置 IP（供 UDP 音訊中繼使用，備用）
                    if let ip = self.extractIP(from: connection) {
                        self.knownUDPDeviceIPs.insert(ip)
                        print("[HQ-Server] Device IP recorded: \(ip) (\(connID))")
                    } else {
                        print("[HQ-Server] ⚠️ 無法從 TCP 取得裝置 IP (\(connID)), endpoint=\(connection.endpoint)")
                        // 延遲重試（path 可能尚未建立）
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            if let ip = self?.extractIP(from: connection) {
                                self?.queue.async {
                                    self?.knownUDPDeviceIPs.insert(ip)
                                    print("[HQ-Server] Device IP recorded (delayed): \(ip) (\(connID))")
                                }
                            }
                        }
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.connectedClients = self.connections.count
                    }
                }
                self.sendHistory(to: connection)
                self.sendCurrentState(to: connection)
                self.receiveData(from: connection, connID: connID)
            case .failed, .cancelled:
                print("[HQ-Server] Client disconnected (\(connID))")
                self.queue.async {
                    let disconnectedDeviceID = self.connDeviceMap[connID]
                    // 清理 UDP 中繼（不再清 knownUDPDeviceIPs，讓它自然保留）
                    self.connections.removeAll { $0 === connection }
                    self.connectionIDMap.removeValue(forKey: ObjectIdentifier(connection))
                    self.connDeviceMap.removeValue(forKey: connID)
                    self.receiveBuffers.removeValue(forKey: connID)
                    self.lastActivity.removeValue(forKey: connID)
                    self.peerConnIDs.remove(connID)
                    DispatchQueue.main.async {
                        self.connectedClients = self.connections.count
                        self.fieldUnits.removeAll { $0.id == connID }
                        self.hqPeers.removeAll { $0.id == connID }
                        self.deviceLocations = self.deviceLocations.filter { key, value in
                            let locationConnID = value["conn_id"] as? String
                            return key != disconnectedDeviceID && locationConnID != connID
                        }
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func sendHistory(to connection: NWConnection) {
        // sentCommands 是 @Published 屬性，必須在 main thread 讀取，
        // 避免從 Network background queue 直接存取造成 data race。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let recent = Array(self.sentCommands.prefix(10))
            guard !recent.isEmpty else { return }
            // 序列化後切回 network queue 發送，不在 main thread 阻塞 I/O
            self.queue.async {
                for cmd in recent {
                    guard let cmdData = try? JSONEncoder().encode(cmd),
                          let cmdJSON = String(data: cmdData, encoding: .utf8) else { continue }
                    let msg = WiFiMessage(msgType: "command", payload: cmdJSON)
                    guard let data = try? JSONEncoder().encode(msg) else { continue }
                    let message = data + Data([0x0A])
                    connection.send(content: message, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    private func receiveData(from connection: NWConnection, connID: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.queue.async { self.lastActivity[connID] = Date() }
                self.processReceivedData(data, connID: connID)
            }
            if isComplete || error != nil {
                // 遠端關閉連線 → 主動取消以觸發 stateUpdateHandler .cancelled
                connection.cancel()
                return
            }
            self.receiveData(from: connection, connID: connID)
        }
    }

    private var receiveBuffers: [String: Data] = [:]

    private func processReceivedData(_ data: Data, connID: String) {
        var buffer = receiveBuffers[connID, default: Data()]
        buffer.append(data)

        // 防止惡意或錯誤的客戶端發送無換行大量數據
        if buffer.count > 65536 {
            print("[HQ-Server] Buffer overflow for \(connID), clearing")
            receiveBuffers.removeValue(forKey: connID)
            return
        }

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let messageData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard !messageData.isEmpty else { continue }

            if let msg = try? JSONDecoder().decode(WiFiMessage.self, from: Data(messageData)) {
                Task { @MainActor in
                    self.handleWiFiMessage(msg, connID: connID)
                }
            } else {
                // 嘗試用 do-catch 取得詳細錯誤
                do {
                    _ = try JSONDecoder().decode(WiFiMessage.self, from: Data(messageData))
                } catch {
                    print("[HQ-Server] JSON decode failed for message (\(messageData.count) bytes) from \(connID): \(error.localizedDescription)")
                }
            }
        }

        receiveBuffers[connID] = buffer
    }

    @MainActor private func handleWiFiMessage(_ msg: WiFiMessage, connID: String) {
        if let sourceDeviceID = msg.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceDeviceID.isEmpty {
            queue.async { [weak self] in
                self?.connDeviceMap[connID] = sourceDeviceID
            }
        }

        switch msg.msgType {

        case "hello":
            guard let payloadData = msg.payload.data(using: .utf8) else {
                print("[HQ-Server] hello: payload encoding failed from \(connID)")
                return
            }
            guard let hello = try? JSONDecoder().decode(HQHelloPayload.self, from: payloadData) else {
                print("[HQ-Server] hello: decode failed from \(connID), payload=\(msg.payload.prefix(200))")
                return
            }

            if hello.role == "hq_peer" {
                queue.async { [weak self] in self?.peerConnIDs.insert(connID) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard !self.hqPeers.contains(where: { $0.id == connID }) else { return }
                    self.hqPeers.append(HQPeerInfo(
                        id: connID, peerID: hello.id,
                        peerName: hello.name, connectedAt: Date()
                    ))
                    print("[HQ-Server] HQ peer connected: \(hello.name) (\(hello.id))")
                }
                // 把目前狀態推送給新 peer
                if let conn = connections.first(where: { connectionIDMap[ObjectIdentifier($0)] == connID }) {
                    sendHistory(to: conn)
                    sendCurrentState(to: conn)
                }
            }
            return

        case "hq_command":
            // 來自 HQ peer 的命令 → 執行並廣播給所有前線裝置
            guard let payloadData = msg.payload.data(using: .utf8),
                  let cmd = try? JSONDecoder().decode(WiFiCommand.self, from: payloadData)
            else { return }
            broadcastCommand(cmd)
            DispatchQueue.main.async { [weak self] in
                self?.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "HQ 同伴命令：\(cmd.title)",
                    detail: cmd.detail, source: cmd.sender
                ))
            }
            return

        case "hq_timer_start":
            // 來自 HQ peer 的計時器啟動 → 廣播給所有前線裝置
            guard let payloadData = msg.payload.data(using: .utf8),
                  let timer = try? JSONDecoder().decode(CountdownTimerModel.self, from: payloadData)
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.countdownTimers.append(timer)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "HQ 同伴啟動計時器：\(timer.title)",
                    detail: "\(timer.durationSeconds / 60) 分鐘",
                    source: connID
                ))
            }
            broadcastTimerSync(timer)
            return

        case "hq_timer_cancel":
            // 來自 HQ peer 的計時器取消 → 廣播給所有前線裝置
            guard let payloadData = msg.payload.data(using: .utf8),
                  let idObj = try? JSONDecoder().decode([String: String].self, from: payloadData),
                  let timerID = idObj["id"]
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.countdownTimers.removeAll { $0.id == timerID }
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "HQ 同伴取消計時器",
                    detail: "ID: \(timerID.prefix(8))",
                    source: connID
                ))
            }
            broadcastTimerCancel(timerID)
            return

        case "hq_task_assign":
            // 來自 HQ peer 的任務指派 → 廣播給所有前線裝置
            guard let payloadData = msg.payload.data(using: .utf8),
                  let task = try? JSONDecoder().decode(TaskAssignment.self, from: payloadData)
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tasks.insert(task, at: 0)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "HQ 同伴指派任務：\(task.title)",
                    detail: "→ \(task.assigneeName)",
                    source: connID
                ))
            }
            broadcastTaskAssignment(task)
            return

        case "hq_decision":
            // 來自 HQ peer 的指揮決策 → 廣播給所有前線裝置
            guard let payloadData = msg.payload.data(using: .utf8),
                  let decision = try? JSONDecoder().decode(HQDecisionPayload.self, from: payloadData)
            else { return }
            broadcastDecision(decision)
            DispatchQueue.main.async { [weak self] in
                self?.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "HQ 同伴決策",
                    detail: decision.decision.prefix(60) + (decision.decision.count > 60 ? "..." : ""),
                    source: connID
                ))
            }
            return

        case "hq_ai_request":
            // 來自 HQ peer 的 AI 決策請求 → 轉發到後台
            if let payloadData = msg.payload.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let context = dict["context"] as? String ?? ""
                backendBridge?.requestAIDecision(context: context)
            }
            return

        case "status_report":
            // HQ peer 不回報 status，忽略
            guard !peerConnIDs.contains(connID) else { return }
            guard let payloadData = msg.payload.data(using: .utf8),
                  let report = try? JSONDecoder().decode(FieldStatusReport.self, from: payloadData)
            else {
                print("[HQ-Server] Failed to decode status_report payload from \(connID)")
                return
            }

            // 記錄 connID → deviceID 對應
            queue.async { [weak self] in self?.connDeviceMap[connID] = report.deviceID }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                // Track new victims and broadcast an alert
                for v in report.victims {
                    if self.knownVictimIds.insert(v.id).inserted {
                        let cmd = WiFiCommand(
                            id: UUID().uuidString,
                            type: "alert",
                            priority: 1,
                            title: "New Victim Detected",
                            detail: "HQ received report for victim ID: \(v.id)",
                            sender: "HQ Auto-Alert",
                            timestamp: Date().timeIntervalSince1970
                        )
                        self.broadcastCommand(cmd)
                    }
                }

                if let idx = self.fieldUnits.firstIndex(where: { $0.id == connID }) {
                    self.fieldUnits[idx].deviceID = report.deviceID
                    self.fieldUnits[idx].deptCode = report.deptCode
                    self.fieldUnits[idx].battery = report.battery
                    self.fieldUnits[idx].bleConnected = report.bleConnected
                    self.fieldUnits[idx].victims = report.victims
                    self.fieldUnits[idx].teamMembers = report.teamMembers
                    self.fieldUnits[idx].sosCount = report.sosCount
                    self.fieldUnits[idx].lastUpdate = Date()
                    self.fieldUnits[idx].nickname = report.selfPersonnel?.nickname
                } else {
                    self.fieldUnits.append(ConnectedFieldUnit(
                        id: connID,
                        deviceID: report.deviceID,
                        deptCode: report.deptCode,
                        battery: report.battery,
                        bleConnected: report.bleConnected,
                        victims: report.victims,
                        teamMembers: report.teamMembers,
                        sosCount: report.sosCount,
                        lastUpdate: Date(),
                        nickname: report.selfPersonnel?.nickname
                    ))
                    self.appendTimelineEvent(TimelineEvent(
                        eventType: .statusReport,
                        title: L("前線裝置連線"),
                        detail: L("%@ (%@) 已連線", report.deviceID, report.deptCode),
                        source: report.deviceID
                    ))
                }
                self.statusUpdateSequence += 1

                // 自動將前線裝置註冊為救援人員
                if let sp = report.selfPersonnel {
                    if let idx = self.personnelAssignments.firstIndex(where: { $0.id == sp.id }) {
                        self.personnelAssignments[idx] = sp
                    } else {
                        self.personnelAssignments.append(sp)
                    }
                } else {
                    // 相容舊版前線：自動建立
                    let autoID = "field-\(report.deviceID)"
                    if !self.personnelAssignments.contains(where: { $0.id == autoID }) {
                        self.personnelAssignments.append(PersonnelAssignment(
                            id: autoID, name: report.deviceID, role: .rescue
                        ))
                    }
                }
            }
            queue.async { [weak self] in
                guard let self,
                      let connection = self.connections.first(where: { self.connectionIDMap[ObjectIdentifier($0)] == connID })
                else { return }
                self.sendPatientIDConfig(to: connection)
            }

        case "chat_message":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let chat = try? JSONDecoder().decode(ChatMessage.self, from: payloadData)
            else {
                print("[HQ-Server] Failed to decode chat_message payload from \(connID)")
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.chatMessages.append(chat)
                if self.chatMessages.count > 500 { self.chatMessages = Array(self.chatMessages.suffix(300)) }
                self.onChatReceived?(chat)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .chat,
                    title: "\(chat.senderName) 發送訊息",
                    detail: chat.content,
                    source: chat.senderID
                ))
                // HQ 自動計為已讀
                var readers = self.chatReadTracker[chat.id] ?? Set<String>()
                readers.insert("HQ")
                self.chatReadTracker[chat.id] = readers
                self.chatReadCounts[chat.id] = readers.count
                // 廣播已讀狀態
                let statusPayload: [String: Any] = ["message_id": chat.id, "read_count": readers.count]
                if let statusData = try? JSONSerialization.data(withJSONObject: statusPayload),
                   let statusStr = String(data: statusData, encoding: .utf8),
                   let relayData = self.encodeWiFiMessage(msgType: "chat_read_status", payload: statusStr) {
                    self.broadcastRaw(relayData)
                }
            }

            // 中繼轉發：私訊→目標裝置，廣播→全員（含 HQ 自身已在上方處理）
            relayChatMessage(chat, fromConnID: connID)

        case "quick_status":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let status = try? JSONDecoder().decode(QuickStatus.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.quickStatuses.contains(where: { $0.id == status.id }) { return }
                self.quickStatuses.insert(status, at: 0)
                self.statusUpdateSequence += 1
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .statusReport,
                    title: "\(status.senderName) 回報狀態",
                    detail: status.statusType?.label ?? status.type,
                    source: status.senderID
                ))
            }
            // 中繼廣播到其他前線裝置
            guard let data = encodeWiFiMessage(msgType: "quick_status", payload: status) else { return }
            relayBroadcast(data, fromConnID: connID)

        case "task_update":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let task = try? JSONDecoder().decode(TaskAssignment.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx] = task
                }
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .command,
                    title: "\(task.assigneeName) 更新任務",
                    detail: "\(task.title) → \(task.taskStatus.label)",
                    source: task.assigneeID
                ))
            }

        case "hazard_report":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let report = try? JSONDecoder().decode(HazardReport.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.hazardReports.contains(where: { $0.id == report.id }) { return }
                self.hazardReports.insert(report, at: 0)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .disaster,
                    title: "\(report.reporterName) 回報危險",
                    detail: "\(report.hazard?.label ?? report.hazardType)（\(report.severityLevel.label)）",
                    source: report.reporterID
                ))
            }
            // 中繼廣播到其他前線裝置
            guard let data = encodeWiFiMessage(msgType: "hazard_report", payload: report) else { return }
            relayBroadcast(data, fromConnID: connID)

        case "reinforcement_request":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let request = try? JSONDecoder().decode(ReinforcementRequest.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.reinforcementRequests.contains(where: { $0.id == request.id }) { return }
                self.reinforcementRequests.insert(request, at: 0)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .notification,
                    title: "\(request.fromTeam) 請求增援",
                    detail: request.message,
                    source: request.fromTeam
                ))
            }
            // 中繼廣播到其他前線裝置
            guard let data = encodeWiFiMessage(msgType: "reinforcement_request", payload: request) else { return }
            relayBroadcast(data, fromConnID: connID)

        case "reinforcement_reply":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let reply = try? JSONDecoder().decode(ReinforcementRequest.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let idx = self.reinforcementRequests.firstIndex(where: { $0.id == reply.id }) {
                    self.reinforcementRequests[idx] = reply
                }
            }
            // 中繼廣播
            guard let data = encodeWiFiMessage(msgType: "reinforcement_reply", payload: reply) else { return }
            relayBroadcast(data, fromConnID: connID)

        case "location":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return }
            // 支援規範 base format {type, data, ...} 和扁平格式 {lat, lon, ...}
            let locData = (json["data"] as? [String: Any]) ?? json
            guard let latitude = Self.doubleValue(locData["lat"]),
                  let longitude = Self.doubleValue(locData["lon"]) else { return }
            let deviceID = Self.stringValue(locData["device_id"]) ?? Self.stringValue(json["device_id"]) ?? connDeviceMap[connID] ?? connID
            let timestamp = Self.doubleValue(locData["timestamp"]).map { Date(timeIntervalSince1970: $0) } ?? Date()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let nickname = Self.stringValue(locData["nickname"]) ?? Self.stringValue(json["nickname"])
                let locDict: [String: Any] = [
                    "lat": latitude,
                    "lon": longitude,
                    "accuracy": Self.doubleValue(locData["accuracy"]) ?? -1,
                    "role": Self.stringValue(locData["role"]) ?? "",
                    "name": Self.stringValue(locData["name"]) ?? deviceID,
                    "nickname": nickname ?? "",
                    "conn_id": connID,
                    "timestamp": timestamp,
                ]
                self.deviceLocations[deviceID] = locDict
            }

        case "patient":
            guard let payloadData = msg.payload.data(using: .utf8) else {
                print("[HQ-Server] Failed to get patient payload data from \(connID)")
                return
            }
            // 支援三種格式：base format {type, data, ...}、扁平 snake_case、Codable camelCase
            let report: PatientReport? = {
                guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                    return nil
                }
                // 判斷欄位來源：如果有 data 子物件則從中取值，否則直接從頂層取
                let fields = (json["data"] as? [String: Any]) ?? json
                let id = fields["id"] as? String ?? fields["patientId"] as? String ?? "P\(Int(Date().timeIntervalSince1970))"
                let nid = fields["nationalId"] as? String ?? fields["national_id"] as? String ?? ""
                let pname = fields["name"] as? String ?? ""
                let bdate = fields["birthDate"] as? String ?? fields["birth_date"] as? String ?? ""
                let age = fields["age"] as? Int
                let location = fields["location"] as? String ?? ""
                let br = fields["breathing_rate"] as? Int ?? fields["breathingRate"] as? Int ?? 0
                let cr = fields["capillary_refill"] as? Double ?? fields["capillaryRefill"] as? Double ?? 0
                let cmd = fields["can_follow_commands"] as? Bool ?? fields["canFollowCommands"] as? Bool ?? false
                let gpsObj = fields["gps"] as? [String: Any]
                let lat = gpsObj?["lat"] as? Double ?? fields["gpsLat"] as? Double
                let lon = gpsObj?["lon"] as? Double ?? fields["gpsLon"] as? Double
                let notes = fields["notes"] as? String ?? ""
                return PatientReport(patientId: id, nationalId: nid, name: pname, birthDate: bdate, age: age,
                                    location: location,
                                    breathingRate: br, capillaryRefill: cr,
                                    canFollowCommands: cmd,
                                    gpsLat: lat, gpsLon: lon, notes: notes)
            }()
            guard let report else {
                print("[HQ-Server] Failed to decode patient payload from \(connID)")
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.patientReports.contains(where: { $0.patientId == report.patientId }) {
                    self.patientReports.insert(report, at: 0)
                }
                self.onPatientReport?(report)
                self.appendTimelineEvent(TimelineEvent(
                    eventType: .statusReport,
                    title: L("傷員回報：%@", report.patientId),
                    detail: L("位置：%@", report.location),
                    source: connID
                ))
            }

        case "radio_control":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let ctrl = try? JSONDecoder().decode(RadioControlPayload.self, from: payloadData) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.currentBroadcaster = ctrl.action == "start" ? ctrl.senderName : nil
            }
            // 中繼廣播 PTT 控制給所有前線（含發送者，確保狀態同步）
            guard let data = encodeWiFiMessage(msgType: "radio_control", payload: ctrl) else { return }
            broadcastRaw(data)

            // 日誌
            DispatchQueue.main.async { [weak self] in
                self?.appendTimelineEvent(TimelineEvent(
                    eventType: .briefing,
                    title: L("電台 %@", ctrl.action == "start" ? L("開始廣播") : L("結束廣播")),
                    detail: L("發送者：%@", ctrl.senderName),
                    source: connID
                ))
            }

        case "call_invite":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let invite = try? JSONDecoder().decode(CallInvite.self, from: payloadData) else { return }
            handleCallInvite(invite, fromConnID: connID)

        case "call_response":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let response = try? JSONDecoder().decode(CallResponse.self, from: payloadData) else { return }
            handleCallResponse(response, fromConnID: connID)

        case "call_end":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let end = try? JSONDecoder().decode(CallEnd.self, from: payloadData) else { return }
            handleCallEnd(end, fromConnID: connID)

        case "radio_report":
            guard let payloadData = msg.payload.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RadioReportSummary.self, from: payloadData) else { return }
            let report = HQRadioReport(
                senderName: decoded.senderName,
                transcription: decoded.transcription,
                locationDesc: decoded.locationDesc,
                reportId: decoded.reportId,
                patientsCount: decoded.patientsCount,
                weatherSnapshot: {
                    if let w = decoded.weather,
                       let d = try? JSONEncoder().encode(w),
                       let s = String(data: d, encoding: .utf8) { return s }
                    return ""
                }()
            )
            DispatchQueue.main.async { [weak self] in
                self?.radioReports.insert(report, at: 0)
                self?.appendTimelineEvent(TimelineEvent(
                    eventType: .briefing,
                    title: L("會報上傳：%@", decoded.senderName),
                    detail: decoded.transcription.prefix(50) + "...",
                    source: connID
                ))
            }
            // 中繼報告摘要給所有前線
            guard let summaryData = encodeWiFiMessage(msgType: "report_summary", payload: decoded) else { return }
            relayBroadcast(summaryData, fromConnID: connID)

        case "ping":
            // 回覆 pong 心跳
            if let pongData = encodeWiFiMessage(msgType: "pong", payload: ["ts": Date().timeIntervalSince1970]) {
                queue.async { [weak self] in
                    guard let self else { return }
                    if let conn = self.connections.first(where: {
                        self.connectionIDMap[ObjectIdentifier($0)] == connID
                    }) {
                        conn.send(content: pongData, completion: .contentProcessed { _ in })
                    }
                }
            }

        // MARK: - SOS / 照片 / 資源 / 統計 中繼

        case "sos":
            // 前線發送 SOS — 中繼給所有其他裝置並記錄 timeline
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let data = json["data"] as? [String: Any] ?? json
                let senderName = data["sender_name"] as? String ?? connID
                let sosId = data["sos_id"] as? String ?? UUID().uuidString
                let lat = data["lat"] as? Double ?? 0
                let lon = data["lon"] as? Double ?? 0
                let deviceID = connDeviceMap[connID] ?? connID
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // 同裝置已被解除 → 跳過
                    guard !self.dismissedSOSDeviceIDs.contains(deviceID) else { return }
                    // 同裝置已有 active SOS → 更新時間戳，不重複新增
                    if let idx = self.activeSOSAlerts.firstIndex(where: { $0.deviceID == deviceID }) {
                        self.activeSOSAlerts[idx] = SOSAlert(
                            id: self.activeSOSAlerts[idx].id, deviceID: deviceID,
                            senderName: senderName, lat: lat, lon: lon, timestamp: Date())
                        return
                    }
                    self.appendTimelineEvent(TimelineEvent(
                        eventType: .notification,
                        title: L("SOS 緊急呼叫"),
                        detail: L("發送者：%@", senderName),
                        source: deviceID
                    ))
                    let alert = SOSAlert(id: sosId, deviceID: deviceID,
                                         senderName: senderName,
                                         lat: lat, lon: lon, timestamp: Date())
                    self.activeSOSAlerts.insert(alert, at: 0)
                }
                // 廣播 sos_alert 給其他裝置
                if let relayData = encodeWiFiMessage(msgType: "sos_alert", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        case "sos_cancel":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let data = json["data"] as? [String: Any] ?? json
                let sosId = data["sos_id"] as? String ?? ""
                let deviceID = connDeviceMap[connID] ?? connID
                DispatchQueue.main.async { [weak self] in
                    self?.appendTimelineEvent(TimelineEvent(
                        eventType: .notification,
                        title: L("SOS 已取消"),
                        detail: "SOS ID: \(sosId)",
                        source: connID
                    ))
                    self?.activeSOSAlerts.removeAll { $0.id == sosId || $0.deviceID == deviceID }
                    self?.dismissedSOSDeviceIDs.remove(deviceID)
                }
                if let relayData = encodeWiFiMessage(msgType: "sos_cancel_alert", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        case "photo_alert":
            // 照片伺服器廣播的消息 — 中繼給前線
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let data = json["data"] as? [String: Any] ?? json
                let photoId = data["photo_id"] as? String ?? ""
                let sender = data["sender_name"] as? String ?? ""
                DispatchQueue.main.async { [weak self] in
                    self?.photoAlerts.insert(json, at: 0)
                    self?.appendTimelineEvent(TimelineEvent(
                        eventType: .briefing,
                        title: L("照片回報：%@", photoId),
                        detail: L("來自 %@", sender),
                        source: connID
                    ))
                }
                if let relayData = encodeWiFiMessage(msgType: "photo_alert", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        case "resource_update":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in
                    self?.latestResourceUpdate = json
                }
                if let relayData = encodeWiFiMessage(msgType: "resource_update", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        case "stats_update":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in
                    self?.latestStatsUpdate = json
                }
                if let relayData = encodeWiFiMessage(msgType: "stats_update", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        case "text_broadcast":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let message = json["message"] as? String ?? ""
                let senderName = json["sender_name"] as? String ?? connID
                let priority = json["priority"] as? String ?? "normal"
                let broadcastId = "bc_\(UUID().uuidString.prefix(8))"
                let now = Date()
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm:ss"
                let timeText = fmt.string(from: now)

                let broadcast = HQTextBroadcast(
                    broadcastId: broadcastId,
                    message: message,
                    senderName: senderName,
                    priority: priority,
                    timestamp: now.timeIntervalSince1970
                )
                DispatchQueue.main.async { [weak self] in
                    self?.textBroadcasts.insert(broadcast, at: 0)
                }
                appendTimelineEvent(TimelineEvent(
                    eventType: .briefing,
                    title: L("文字廣播"),
                    detail: "[\(priority)] \(senderName): \(message)",
                    source: connID
                ))
                // 初始化已讀追蹤
                let totalClients = max(connections.count - 1, 1)
                messageReadTracker[broadcastId] = (total: totalClients, readers: [])
                DispatchQueue.main.async { [weak self] in
                    self?.readStatuses[broadcastId] = (total: totalClients, readCount: 0)
                }
                // 組裝 text_broadcast_rx 中繼給所有前線
                var rxPayload = json
                rxPayload["broadcast_id"] = broadcastId
                rxPayload["time"] = timeText
                if let rxData = try? JSONSerialization.data(withJSONObject: rxPayload),
                   let rxStr = String(data: rxData, encoding: .utf8),
                   let relayData = encodeWiFiMessage(msgType: "text_broadcast_rx", payload: rxStr) {
                    broadcastRaw(relayData)
                }
            }

        case "message_ack":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
               let broadcastId = json["broadcast_id"] as? String {
                let deviceId = json["device_id"] as? String ?? connID
                if var tracker = messageReadTracker[broadcastId] {
                    tracker.readers.insert(deviceId)
                    let readCount = tracker.readers.count
                    messageReadTracker[broadcastId] = tracker
                    DispatchQueue.main.async { [weak self] in
                        self?.readStatuses[broadcastId] = (total: tracker.total, readCount: readCount)
                    }
                    // 廣播 read_status 給所有裝置
                    let statusPayload: [String: Any] = [
                        "broadcast_id": broadcastId,
                        "total": tracker.total,
                        "read_count": readCount
                    ]
                    if let statusData = try? JSONSerialization.data(withJSONObject: statusPayload),
                       let statusStr = String(data: statusData, encoding: .utf8),
                       let relayData = encodeWiFiMessage(msgType: "read_status", payload: statusStr) {
                        broadcastRaw(relayData)
                    }
                }
            }

        case "chat_read_receipt":
            // 前線回報聊天訊息已讀
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let data = json["data"] as? [String: Any] ?? json
                let messageIds = data["message_ids"] as? [String] ?? []
                let deviceId = data["device_id"] as? String ?? connDeviceMap[connID] ?? connID
                for msgId in messageIds {
                    var readers = chatReadTracker[msgId] ?? Set<String>()
                    readers.insert(deviceId)
                    chatReadTracker[msgId] = readers
                    let readCount = readers.count
                    DispatchQueue.main.async { [weak self] in
                        self?.chatReadCounts[msgId] = readCount
                    }
                    // 廣播 chat_read_status 給所有裝置
                    let statusPayload: [String: Any] = [
                        "message_id": msgId,
                        "read_count": readCount
                    ]
                    if let statusData = try? JSONSerialization.data(withJSONObject: statusPayload),
                       let statusStr = String(data: statusData, encoding: .utf8),
                       let relayData = encodeWiFiMessage(msgType: "chat_read_status", payload: statusStr) {
                        broadcastRaw(relayData)
                    }
                }
            }

        case "translate_request":
            // 中繼翻譯請求到 Mac-local 後台（gemma4 /translate）。
            // 在 data 內帶上 requesting_device_id，以便後台回應時能路由回原請求裝置。
            if let payloadData = msg.payload.data(using: .utf8),
               var json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let requestingDeviceId = (connDeviceMap[connID]) ?? connID
                json["requesting_device_id"] = requestingDeviceId
                if let bridge = backendBridge, bridge.isConnected {
                    bridge.forwardTranslateRequest(data: json, deviceId: requestingDeviceId)
                    print("[HQ-Server] translate_request 已轉發後台，req=\(requestingDeviceId)")
                } else {
                    // 未連上後台時才使用本地備援譯文，並明確告知使用者為離線模式
                    let text = json["text"] as? String ?? ""
                    let sourceLang = json["source_lang"] as? String ?? "auto"
                    let targetLang = json["target_lang"] as? String ?? "en"
                    Task {
                        await self.requestTranslation(text: text, sourceLang: sourceLang, targetLang: targetLang, forDevice: requestingDeviceId, connID: connID)
                    }
                }
            }

        case "patient_warning":
            if let payloadData = msg.payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                let warning = HQPatientWarning(
                    patientId: json["patient_id"] as? String ?? "",
                    patientName: json["patient_name"] as? String ?? "未知",
                    triageLevel: json["triage_level"] as? String ?? "",
                    warningMessage: json["warning_message"] as? String ?? "",
                    minutesSinceTriage: json["minutes_since_triage"] as? Int ?? 0,
                    timestamp: Date()
                )
                DispatchQueue.main.async { [weak self] in
                    self?.patientWarnings.insert(warning, at: 0)
                }
                appendTimelineEvent(TimelineEvent(
                    eventType: .pwsAlert,
                    title: L("傷患惡化預警"),
                    detail: "\(warning.patientName) [\(warning.triageLevel)] \(warning.warningMessage)",
                    source: connID
                ))
                // 中繼給所有前線
                if let relayData = encodeWiFiMessage(msgType: "patient_warning", payload: msg.payload) {
                    relayBroadcast(relayData, fromConnID: connID)
                }
            }

        default:
            print("[HQ-Server] Unknown message type: \(msg.msgType)")
        }
    }

    // MARK: - 通話中繼

    @MainActor private func handleCallInvite(_ invite: CallInvite, fromConnID: String) {
        callInviteIndex[invite.callID] = invite
        if !callInvites.contains(where: { $0.callID == invite.callID }) {
            callInvites.insert(invite, at: 0)
            if callInvites.count > 100 { callInvites = Array(callInvites.prefix(100)) }
        }
        appendTimelineEvent(TimelineEvent(
            eventType: .chat,
            title: L("通話邀請：%@", invite.initiatorName),
            detail: invite.targetDeviceIDs.joined(separator: ", "),
            source: invite.initiatorID
        ))
        guard let data = encodeWiFiMessage(msgType: "call_invite", payload: invite) else { return }
        sendToDevices(data,
                      targetDeviceIDs: invite.targetDeviceIDs,
                      fallbackToBroadcastOnNoMatch: true,
                      context: "call_invite \(invite.callID)")
        relayToHQPeers(data, excluding: fromConnID)
    }

    @MainActor private func handleCallResponse(_ response: CallResponse, fromConnID: String) {
        var routeTargets = Set<String>()
        if let invite = callInviteIndex[response.callID] {
            routeTargets.insert(invite.initiatorID)
            routeTargets.formUnion(invite.participants)
            if response.accepted {
                let participants = Array(routeTargets.union([response.responderID]))
                activeCallSession = CallSession(
                    callID: response.callID,
                    initiatorID: invite.initiatorID,
                    initiatorName: invite.initiatorName,
                    participants: participants,
                    status: .active
                )
            }
        } else if let active = activeCallSession, active.callID == response.callID {
            routeTargets.formUnion(active.participants)
        }
        routeTargets.remove(response.responderID)
        routeTargets.remove("HQ")

        appendTimelineEvent(TimelineEvent(
            eventType: .chat,
            title: response.accepted ? L("通話已接聽") : L("通話已拒絕"),
            detail: response.responderName,
            source: response.responderID
        ))
        guard let data = encodeWiFiMessage(msgType: "call_response", payload: response) else { return }
        if !routeTargets.isEmpty {
            sendToDevices(data, targetDeviceIDs: Array(routeTargets))
        }
        relayToHQPeers(data, excluding: fromConnID)
    }

    @MainActor private func handleCallEnd(_ end: CallEnd, fromConnID: String) {
        var routeTargets = Set<String>()
        if var active = activeCallSession, active.callID == end.callID {
            routeTargets.formUnion(active.participants)
            active.status = .ended
            active.endedAt = end.timestamp
            activeCallSession = nil
        } else if let invite = callInviteIndex[end.callID] {
            routeTargets.insert(invite.initiatorID)
            routeTargets.formUnion(invite.targetDeviceIDs)
            routeTargets.formUnion(invite.participants)
        }
        callInviteIndex.removeValue(forKey: end.callID)
        routeTargets.remove(end.senderID)
        routeTargets.remove("HQ")

        appendTimelineEvent(TimelineEvent(
            eventType: .chat,
            title: L("通話結束"),
            detail: end.reason,
            source: end.senderID
        ))
        guard let data = encodeWiFiMessage(msgType: "call_end", payload: end) else { return }
        if !routeTargets.isEmpty {
            sendToDevices(data, targetDeviceIDs: Array(routeTargets))
        }
        relayToHQPeers(data, excluding: fromConnID)
    }

    // MARK: - 翻譯請求

    private func requestTranslation(text: String, sourceLang: String, targetLang: String, forDevice deviceId: String, connID: String) async {
        // 先嘗試 HTTP 直連 gemma4 翻譯（Mac-local 後台在 :8001/translate）
        if let httpResult = await httpTranslateViaGemma4(text: text, sourceLang: sourceLang, targetLang: targetLang) {
            let result = HQTranslationResult(
                original: text,
                translated: httpResult,
                detectedLang: sourceLang,
                targetLang: targetLang
            )
            DispatchQueue.main.async { [weak self] in
                self?.latestTranslation = result
            }
            let payload: [String: Any] = [
                "original": text,
                "translated": httpResult,
                "detected_lang": sourceLang,
                "target_lang": targetLang,
                "engine": "gemma4_direct"
            ]
            if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let payloadStr = String(data: payloadData, encoding: .utf8),
               let msgData = encodeWiFiMessage(msgType: "translate_result", payload: payloadStr) {
                sendToDevices(msgData, targetDeviceIDs: [deviceId])
            }
            return
        }

        // HTTP 也失敗 → 離線本地 fallback
        let translated = localFallbackTranslate(text: text, sourceLang: sourceLang, targetLang: targetLang)
        let result = HQTranslationResult(
            original: text,
            translated: translated,
            detectedLang: sourceLang,
            targetLang: targetLang
        )

        DispatchQueue.main.async { [weak self] in
            self?.latestTranslation = result
        }

        let payload: [String: Any] = [
            "original": text,
            "translated": translated,
            "detected_lang": sourceLang,
            "target_lang": targetLang,
            "engine": "local_fallback"
        ]
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadStr = String(data: payloadData, encoding: .utf8),
           let msgData = encodeWiFiMessage(msgType: "translate_result", payload: payloadStr) {
            sendToDevices(msgData, targetDeviceIDs: [deviceId])
        }
    }

    /// 透過 HTTP 直連 Mac-local gemma4_server /translate 端點
    private func httpTranslateViaGemma4(text: String, sourceLang: String, targetLang: String) async -> String? {
        // 嘗試已知的後台位址：先用 bridge 紀錄的 host，再用 localhost
        let bridgeHost: String = await MainActor.run { [weak self] in
            self?.backendBridge?.backendHost ?? ""
        }
        let candidates: [String] = {
            var hosts: [String] = []
            if !bridgeHost.isEmpty {
                hosts.append(bridgeHost)
            }
            hosts.append("127.0.0.1")
            return hosts
        }()

        for host in candidates {
            guard let url = URL(string: "http://\(host):8001/translate") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let body: [String: Any] = [
                "text": text,
                "source_lang": sourceLang,
                "target_lang": targetLang,
                "context": "rescue_medical"
            ]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { continue }
            request.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else { continue }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let translated = json["translated"] as? String, !translated.isEmpty {
                    print("[HQ-Server] ✅ gemma4 HTTP 翻譯成功 (host=\(host))")
                    return translated
                }
            } catch {
                print("[HQ-Server] ⚠️ gemma4 HTTP 翻譯 \(host) 失敗: \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func localFallbackTranslate(text: String, sourceLang: String, targetLang: String) -> String {
        let normalizedTarget = targetLang.lowercased()
        if normalizedTarget.hasPrefix("zh") {
            return "[本地翻譯] \(text)"
        }
        return "[LOCAL \(sourceLang)->\(targetLang)] \(text)"
    }

    // MARK: - HQ 主動發送文字廣播

    /// 指揮中心主動發送文字廣播
    func sendTextBroadcast(message: String, priority: String = "normal") {
        let broadcastId = "bc_\(UUID().uuidString.prefix(8))"
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let timeText = fmt.string(from: now)

        let broadcast = HQTextBroadcast(
            broadcastId: broadcastId,
            message: message,
            senderName: "指揮中心",
            priority: priority,
            timestamp: now.timeIntervalSince1970
        )
        DispatchQueue.main.async { [weak self] in
            self?.textBroadcasts.insert(broadcast, at: 0)
        }
        let totalClients = max(connections.count, 1)
        messageReadTracker[broadcastId] = (total: totalClients, readers: [])
        DispatchQueue.main.async { [weak self] in
            self?.readStatuses[broadcastId] = (total: totalClients, readCount: 0)
        }
        let payload: [String: Any] = [
            "broadcast_id": broadcastId,
            "message": message,
            "sender_name": "指揮中心",
            "priority": priority,
            "time": timeText
        ]
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadStr = String(data: payloadData, encoding: .utf8),
           let data = encodeWiFiMessage(msgType: "text_broadcast_rx", payload: payloadStr) {
            broadcastRaw(data)
        }
    }

    // MARK: - 聊天中繼

    /// 中繼轉發聊天訊息：廣播或路由到特定裝置
    private func relayChatMessage(_ chat: ChatMessage, fromConnID: String) {
        guard let data = encodeWiFiMessage(msgType: "chat_message", payload: chat) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.cleanupConnections()

            if let recipientID = chat.recipientID {
                // 私訊：找到目標裝置的連線
                if let targetConnID = self.connDeviceMap.first(where: { $0.value == recipientID })?.key,
                   let conn = self.connections.first(where: {
                       self.connectionIDMap[ObjectIdentifier($0)] == targetConnID
                   }) {
                    conn.send(content: data, completion: .contentProcessed { _ in })
                }
            } else {
                // 廣播：轉發給所有連線（不含發送者）
                for conn in self.connections {
                    let cid = self.connectionIDMap[ObjectIdentifier(conn)]
                    if cid != fromConnID {
                        conn.send(content: data, completion: .contentProcessed { _ in })
                    }
                }
            }
        }
    }

    /// 中繼廣播（排除原始發送者）
    private func relayBroadcast(_ data: Data, fromConnID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cleanupConnections()
            for conn in self.connections {
                let cid = self.connectionIDMap[ObjectIdentifier(conn)]
                if cid != fromConnID {
                    conn.send(content: data, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    // MARK: - UDP 音訊中繼

    /// 啟動 UDP 音訊中繼（port 9001）
    private func startUDPRelay() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: udpListenPort) else {
                print("[HQ-UDP] ❌ Invalid port: \(udpListenPort)")
                return
            }
            udpAudioListener = try NWListener(using: params, on: nwPort)
        } catch {
            print("[HQ-UDP] ❌ Listener create failed: \(error)")
            return
        }
        udpAudioListener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[HQ-UDP] ✅ Audio relay listening on port \(self.udpListenPort), relay out → port \(self.udpRelayPort)")
            case .failed(let err):
                print("[HQ-UDP] ❌ Listener failed: \(err)")
            case .cancelled:
                print("[HQ-UDP] Listener cancelled")
            default:
                break
            }
        }
        udpAudioListener?.newConnectionHandler = { [weak self] newConn in
            newConn.start(queue: .global(qos: .userInteractive))
            print("[HQ-UDP] New UDP connection: \(newConn.endpoint)")
            self?.receiveUDPAudio(on: newConn)
        }
        udpAudioListener?.start(queue: queue)
    }

    /// 停止 UDP 音訊中繼
    private func stopUDPRelay() {
        udpAudioListener?.cancel()
        udpAudioListener = nil
        udpRelayOutgoing.values.forEach { $0.cancel() }
        udpRelayOutgoing.removeAll()
        knownUDPDeviceIPs.removeAll()
    }

    /// 從 UDP connection 取得遠端 IP
    private func extractUDPSenderIP(from conn: NWConnection) -> String? {
        if let remote = conn.currentPath?.remoteEndpoint,
           case .hostPort(let host, _) = remote {
            return normalizeIP("\(host)")
        }
        if case .hostPort(let host, _) = conn.endpoint {
            return normalizeIP("\(host)")
        }
        return nil
    }

    /// 接收 UDP 音訊封包並中繼給其他裝置
    private func receiveUDPAudio(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                if let error {
                    print("[HQ-UDP] ❌ Receive error: \(error)")
                }
                return
            }
            guard data.count >= 18 else {
                self.receiveUDPAudio(on: conn)
                return
            }
            // 驗證 magic
            let magic = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard magic == self.udpMagic else {
                self.receiveUDPAudio(on: conn)
                return
            }

            // 從 UDP connection 直接取得發送者 IP
            let senderIP = self.extractUDPSenderIP(from: conn)

            // 所有 knownUDPDeviceIPs / udpPacketCount 存取都在 queue 中（執行緒安全）
            self.queue.async {
                // 自動註冊——從 UDP 封包發現裝置 IP
                if let ip = senderIP {
                    if self.knownUDPDeviceIPs.insert(ip).inserted {
                        print("[HQ-UDP] 📡 Auto-discovered field device: \(ip)")
                    }
                }

                self.udpPacketCount += 1
                let pktNum = self.udpPacketCount
                if pktNum <= 20 || pktNum % 100 == 0 {
                    print("[HQ-UDP] 📦 Packet #\(pktNum) from \(senderIP ?? "?"), known IPs: \(self.knownUDPDeviceIPs), size=\(data.count)B")
                }

                // 中繼給所有其他裝置
                var relayCount = 0
                let targets = self.knownUDPDeviceIPs.filter { $0 != senderIP }
                for ip in targets {
                    self.sendUDPAudioPacket(data, to: ip)
                    relayCount += 1
                }
                if pktNum <= 20 || pktNum % 100 == 0 {
                    print("[HQ-UDP] 📤 Relayed to \(relayCount) device(s), targets=\(targets)")
                }
            }
            self.receiveUDPAudio(on: conn)
        }
    }

    /// 等待首次連線 ready 期間暫存的封包（每 IP 最多暫存 1 筆，避免記憶體暴漲）
    private var udpPendingFirstPacket: [String: Data] = [:]  // 只在 queue 中存取

    /// 送出 UDP 音訊封包（重複使用既有連線，首包排隊等 .ready）
    /// ❗ 必須在 self.queue 上呼叫
    private func sendUDPAudioPacket(_ data: Data, to ip: String) {
        if let existing = udpRelayOutgoing[ip] {
            existing.send(content: data, completion: .contentProcessed { sendErr in
                if let sendErr {
                    print("[HQ-UDP] ❌ Send failed to \(ip): \(sendErr)")
                }
            })
        } else {
            print("[HQ-UDP] 🔗 Creating new outgoing UDP to \(ip):\(self.udpRelayPort)")
            let conn = NWConnection(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: self.udpRelayPort)!,
                using: .udp
            )
            // 暫存首包，等 .ready 後才發送
            udpPendingFirstPacket[ip] = data
            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                // 回到 queue 保證執行緒安全
                self.queue.async {
                    switch state {
                    case .ready:
                        print("[HQ-UDP] ✅ Outgoing UDP to \(ip) ready")
                        if let pending = self.udpPendingFirstPacket.removeValue(forKey: ip) {
                            conn.send(content: pending, completion: .contentProcessed { sendErr in
                                if let sendErr {
                                    print("[HQ-UDP] ❌ First send to \(ip) failed: \(sendErr)")
                                }
                            })
                        }
                    case .failed(let err):
                        print("[HQ-UDP] ❌ Outgoing UDP to \(ip) failed: \(err)")
                        self.udpPendingFirstPacket.removeValue(forKey: ip)
                        self.udpRelayOutgoing.removeValue(forKey: ip)
                    default:
                        break
                    }
                }
            }
            conn.start(queue: self.queue)
            udpRelayOutgoing[ip] = conn
        }
    }

    // MARK: - 新連線推送現有狀態

    /// 推送災害狀態、PWS 警報、人員配置、最近會報給新連線
    private func sendCurrentState(to connection: NWConnection) {
        sendPatientIDConfig(to: connection)
        // 災害狀態
        if let site = disasterSite,
           let data = encodeWiFiMessage(msgType: "disaster_update", payload: site) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        // 活躍 PWS 警報
        for alert in pwsAlerts where alert.isActive {
            if let data = encodeWiFiMessage(msgType: "pws_alert", payload: alert) {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        // 人員配置
        if !personnelAssignments.isEmpty,
           let data = encodeWiFiMessage(msgType: "personnel_assignment", payload: personnelAssignments) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        // 最近會報
        if let latest = briefings.last,
           let data = encodeWiFiMessage(msgType: "briefing", payload: latest) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        // 伺服器狀態快照（HQ peer 同步用）
        DispatchQueue.main.async { [weak self] in
            guard let self, let snapshot = self.statusSnapshotProvider?() else { return }
            self.queue.async {
                if let data = self.encodeWiFiMessage(msgType: "server_status", payload: snapshot) {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    private func sendPatientIDConfig(to connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var config = self.patientIDConfig
            config.nextPatientSerial = max(config.nextPatientSerial, self.patientReports.count + 1)
            self.queue.async {
                if let data = self.encodeWiFiMessage(msgType: "patient_id_config", payload: config) {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    // MARK: - 廣播方法（HQ 主動推送）

    /// 廣播災害狀態更新
    func broadcastDisasterUpdate(_ site: DisasterSite, targetDeviceIDs: [String]? = nil) {
        DispatchQueue.main.async { [weak self] in self?.disasterSite = site }
        guard let data = encodeWiFiMessage(msgType: "disaster_update", payload: site) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播人員配置
    func broadcastPersonnelAssignment(_ assignments: [PersonnelAssignment], targetDeviceIDs: [String]? = nil) {
        DispatchQueue.main.async { [weak self] in self?.personnelAssignments = assignments }
        guard let data = encodeWiFiMessage(msgType: "personnel_assignment", payload: assignments) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播 PWS 警報
    func broadcastPWSAlert(_ alert: PWSAlert, targetDeviceIDs: [String]? = nil) {
        DispatchQueue.main.async {
            if let idx = self.pwsAlerts.firstIndex(where: { $0.id == alert.id }) {
                self.pwsAlerts[idx] = alert
            } else {
                self.pwsAlerts.insert(alert, at: 0)
            }
        }
        guard let data = encodeWiFiMessage(msgType: "pws_alert", payload: alert) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播會報
    func broadcastBriefing(_ briefing: BriefingReport, targetDeviceIDs: [String]? = nil) {
        DispatchQueue.main.async {
            self.briefings.insert(briefing, at: 0)
            if self.briefings.count > 50 { self.briefings = Array(self.briefings.prefix(50)) }
        }
        guard let data = encodeWiFiMessage(msgType: "briefing", payload: briefing) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播任務指派
    func broadcastTaskAssignment(_ task: TaskAssignment, targetDeviceIDs: [String]? = nil) {
        guard let data = encodeWiFiMessage(msgType: "task_assignment", payload: task) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播計時器同步
    func broadcastTimerSync(_ timer: CountdownTimerModel, targetDeviceIDs: [String]? = nil) {
        guard let data = encodeWiFiMessage(msgType: "timer_sync", payload: timer) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播計時器取消
    func broadcastTimerCancel(_ timerID: String, targetDeviceIDs: [String]? = nil) {
        let payload = ["id": timerID]
        guard let data = encodeWiFiMessage(msgType: "timer_cancel", payload: payload) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播增援回應（批准/拒絕）
    func broadcastReinforcementResponse(_ request: ReinforcementRequest, targetDeviceIDs: [String]? = nil) {
        guard let data = encodeWiFiMessage(msgType: "reinforcement_reply", payload: request) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播 HQ 指揮決策
    func broadcastDecision(_ payload: HQDecisionPayload, targetDeviceIDs: [String]? = nil) {
        guard let data = encodeWiFiMessage(msgType: "decision", payload: payload) else { return }
        sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
    }

    /// 廣播會報摘要到所有前線裝置（語音辨識完成後呼叫）
    func broadcastReportSummary(_ summary: RadioReportSummary) {
        guard let data = encodeWiFiMessage(msgType: "report_summary", payload: summary) else { return }
        sendToDevices(data, targetDeviceIDs: nil)
    }

    func sendCallInviteFromHQ(_ invite: CallInvite) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.callInviteIndex[invite.callID] = invite
            self.callInvites.insert(invite, at: 0)
            self.activeCallSession = CallSession(
                callID: invite.callID,
                initiatorID: invite.initiatorID,
                initiatorName: invite.initiatorName,
                participants: invite.participants + invite.targetDeviceIDs,
                status: .ringing
            )
            self.appendTimelineEvent(TimelineEvent(
                eventType: .chat,
                title: L("HQ 發起通話"),
                detail: invite.targetDeviceIDs.joined(separator: ", "),
                source: invite.initiatorID
            ))
        }
        guard let data = encodeWiFiMessage(msgType: "call_invite", payload: invite) else { return }
        sendToDevices(data,
                      targetDeviceIDs: invite.targetDeviceIDs,
                      fallbackToBroadcastOnNoMatch: true,
                      context: "hq_call_invite \(invite.callID)")
    }

    func sendCallEndFromHQ(_ end: CallEnd) {
        let targetDeviceIDs = activeCallSession?.participants.filter { $0 != "HQ" } ?? []
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeCallSession = nil
            self.callInviteIndex.removeValue(forKey: end.callID)
            self.appendTimelineEvent(TimelineEvent(
                eventType: .chat,
                title: L("HQ 結束通話"),
                detail: end.reason,
                source: end.senderID
            ))
        }
        guard let data = encodeWiFiMessage(msgType: "call_end", payload: end) else { return }
        if !targetDeviceIDs.isEmpty {
            sendToDevices(data, targetDeviceIDs: targetDeviceIDs)
        }
    }

    /// 中繼後台 JSON 訊息給所有前線裝置（Backend Bridge 呼叫）
    func relayBackendJSON(msgType: String, data: [String: Any]) {
        guard let payloadData = try? JSONSerialization.data(withJSONObject: data),
              let payloadStr = String(data: payloadData, encoding: .utf8) else { return }
        let wifi: [String: String] = ["msgType": msgType, "payload": payloadStr]
        guard let wireData = try? JSONSerialization.data(withJSONObject: wifi) else { return }
        let message = wireData + Data([0x0A])
        sendToDevices(message, targetDeviceIDs: nil)
    }

    /// 中繼後台 JSON 訊息給指定前線裝置（用於有明確 target 的回應，如 translate_result）
    func relayBackendJSON(msgType: String, data: [String: Any], targetDeviceID: String) {
        guard let payloadData = try? JSONSerialization.data(withJSONObject: data),
              let payloadStr = String(data: payloadData, encoding: .utf8) else { return }
        let wifi: [String: String] = ["msgType": msgType, "payload": payloadStr]
        guard let wireData = try? JSONSerialization.data(withJSONObject: wifi) else { return }
        let message = wireData + Data([0x0A])
        sendToDevices(message, targetDeviceIDs: [targetDeviceID])
    }

    /// 發送個人通知到指定裝置
    func sendPersonalNotification(_ notif: PersonalNotification) {
        DispatchQueue.main.async { [weak self] in self?.personalNotifications.append(notif) }
        guard let data = encodeWiFiMessage(msgType: "personal_notification", payload: notif) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            if let targetConnID = self.connDeviceMap.first(where: { $0.value == notif.targetDeviceID })?.key,
               let conn = self.connections.first(where: {
                   self.connectionIDMap[ObjectIdentifier($0)] == targetConnID
               }) {
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    /// 從 HQ 發送聊天訊息（HQ 自己作為發送者）
    func sendChatFromHQ(_ chat: ChatMessage) {
        DispatchQueue.main.async {
            self.chatMessages.append(chat)
            if self.chatMessages.count > 500 { self.chatMessages = Array(self.chatMessages.suffix(300)) }
        }
        guard let data = encodeWiFiMessage(msgType: "chat_message", payload: chat) else { return }

        if chat.recipientID != nil {
            // 私訊
            queue.async { [weak self] in
                guard let self else { return }
                if let targetConnID = self.connDeviceMap.first(where: { $0.value == chat.recipientID })?.key,
                   let conn = self.connections.first(where: {
                       self.connectionIDMap[ObjectIdentifier($0)] == targetConnID
                   }) {
                    conn.send(content: data, completion: .contentProcessed { _ in })
                }
            }
        } else {
            broadcastRaw(data)
        }
    }

    /// 廣播團隊更新
    func broadcastTeamUpdate(_ members: [TeamSummary]) {
        guard let data = encodeWiFiMessage(msgType: "team_update", payload: members) else { return }
        broadcastRaw(data)
    }

    // MARK: - PADOS 統一路由

    /// 統一路由方法：targetDeviceIDs 為 nil/空 → 廣播全體；有值 → 僅發送給指定裝置
    private func sendToDevices(_ data: Data,
                               targetDeviceIDs: [String]?,
                               fallbackToBroadcastOnNoMatch: Bool = false,
                               context: String = "") {
        queue.async { [weak self] in
            guard let self else { return }
            self.cleanupConnections()

            guard let targets = targetDeviceIDs, !targets.isEmpty else {
                // 廣播全體
                for conn in self.connections {
                    conn.send(content: data, completion: .contentProcessed { error in
                        if let error { print("[HQ-Server] Send failed: \(error)") }
                    })
                }
                return
            }

            // 定向發送：查找匹配 deviceID 的連線
            let targetSet = Set(targets.map(Self.normalizedRouteID))
            var sentCount = 0
            for conn in self.connections {
                guard let connID = self.connectionIDMap[ObjectIdentifier(conn)],
                      self.connectionMatchesTargets(connID: connID, targetSet: targetSet) else { continue }
                let deviceID = self.connDeviceMap[connID] ?? connID
                conn.send(content: data, completion: .contentProcessed { error in
                    if let error { print("[HQ-Server] Send to \(deviceID) failed: \(error)") }
                })
                sentCount += 1
            }

            if sentCount == 0, fallbackToBroadcastOnNoMatch {
                print("[HQ-Server] ⚠️ No direct target for \(context). targets=\(targets.joined(separator: ",")) known=\(self.connDeviceMap.values.joined(separator: ",")); broadcasting as fallback")
                for conn in self.connections {
                    guard let connID = self.connectionIDMap[ObjectIdentifier(conn)],
                          !self.peerConnIDs.contains(connID) else { continue }
                    conn.send(content: data, completion: .contentProcessed { error in
                        if let error { print("[HQ-Server] Fallback call invite send failed: \(error)") }
                    })
                }
            }
        }
    }

    private func connectionMatchesTargets(connID: String, targetSet: Set<String>) -> Bool {
        let candidates = [connID, connDeviceMap[connID]].compactMap { $0 }
        return candidates.contains { targetSet.contains(Self.normalizedRouteID($0)) }
    }

    private static func normalizedRouteID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func broadcastRaw(_ data: Data) {
        sendToDevices(data, targetDeviceIDs: nil)
    }

    private func relayToHQPeers(_ data: Data, excluding connID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for conn in self.connections {
                guard let cid = self.connectionIDMap[ObjectIdentifier(conn)],
                      cid != connID,
                      self.peerConnIDs.contains(cid) else { continue }
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    private func encodeWiFiMessage<T: Encodable>(msgType: String, payload: T) -> Data? {
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return nil }
        let msg = WiFiMessage(msgType: msgType, payload: payloadJSON)
        guard let data = try? JSONEncoder().encode(msg) else { return nil }
        return data + Data([0x0A])
    }

    /// String 專用 overload：直接使用原始字串作為 payload，避免 JSONEncoder 雙重編碼
    private func encodeWiFiMessage(msgType: String, payload: String) -> Data? {
        let msg = WiFiMessage(msgType: msgType, payload: payload)
        guard let data = try? JSONEncoder().encode(msg) else { return nil }
        return data + Data([0x0A])
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value { return "\(value)" }
        return nil
    }

    private func cleanupConnections() {
        connections.removeAll { conn in
            let dead: Bool = {
                if case .cancelled = conn.state { return true }
                if case .failed = conn.state { return true }
                return false
            }()
            if dead {
                let cid = connectionIDMap.removeValue(forKey: ObjectIdentifier(conn))
                if let cid { connDeviceMap.removeValue(forKey: cid) }
            }
            return dead
        }
        DispatchQueue.main.async { [weak self] in self?.connectedClients = self?.connections.count ?? 0 }
    }

    // MARK: - 聚合資料

    /// 所有前線裝置追蹤到的不重複受困者
    var allVictims: [VictimSummary] {
        var seen = Set<String>()
        var result: [VictimSummary] = []
        for unit in fieldUnits {
            for v in unit.victims where !seen.contains(v.id) {
                seen.insert(v.id)
                result.append(v)
            }
        }
        return result
    }

    /// 所有前線裝置追蹤到的不重複團隊成員
    var allTeamMembers: [TeamSummary] {
        var seen = Set<String>()
        var result: [TeamSummary] = []
        for unit in fieldUnits {
            for t in unit.teamMembers where !seen.contains(t.id) {
                seen.insert(t.id)
                result.append(t)
            }
        }
        return result
    }

    var totalSOSCount: Int { fieldUnits.reduce(0) { $0 + $1.sosCount } + activeSOSAlerts.count }
    var onlineVictimCount: Int { allVictims.filter(\.isOnline).count }
    var onlineFieldUnitCount: Int { fieldUnits.filter(\.isOnline).count }

    // MARK: - 事件日誌

    func appendTimelineEvent(_ event: TimelineEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timelineEvents.insert(event, at: 0)
            if self.timelineEvents.count > 500 {
                self.timelineEvents = Array(self.timelineEvents.prefix(500))
            }
        }
    }

    /// 標記裝置 SOS 已解除，阻止同裝置後續 SOS 重複觸發
    func markSOSDeviceDismissed(_ deviceID: String) {
        dismissedSOSDeviceIDs.insert(deviceID)
    }

    // MARK: - 本地統計（Mac-only 離線模式）

    private var localStatsTimer: Timer?
    private var serverStartTime: Date?

    /// 啟動本地統計定時器（當後端不可用時自動計算統計）
    func startLocalStatsTimer() {
        serverStartTime = Date()
        localStatsTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.computeLocalStats()
        }
        timer.tolerance = 10
        localStatsTimer = timer
        // 首次延遲 5 秒後計算
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.computeLocalStats()
        }
    }

    func stopLocalStatsTimer() {
        localStatsTimer?.invalidate()
        localStatsTimer = nil
    }

    /// 從 HQ 本地資料計算統計
    private func computeLocalStats() {
        // 僅在後端未提供統計時產生本地統計
        if let existing = latestStatsUpdate,
           let source = existing["_source"] as? String, source == "backend" {
            return
        }

        // START 檢傷分類
        var immediate = 0, delayed = 0, minor = 0, expectant = 0
        for patient in patientReports {
            if patient.breathingRate == 0 {
                expectant += 1
            } else if patient.breathingRate > 30 || patient.capillaryRefill > 2.0 || !patient.canFollowCommands {
                immediate += 1
            } else if patient.breathingRate <= 30 && patient.canFollowCommands {
                minor += 1
            } else {
                delayed += 1
            }
        }

        let durationMinutes: Int
        if let start = serverStartTime {
            durationMinutes = Int(Date().timeIntervalSince(start) / 60)
        } else {
            durationMinutes = 0
        }

        let stats: [String: Any] = [
            "_source": "local",
            "patients": [
                "total": patientReports.count,
                "immediate": immediate,
                "delayed": delayed,
                "minor": minor,
                "expectant": expectant,
            ],
            "personnel": [
                "total": personnelAssignments.count + allTeamMembers.count,
                "online": fieldUnits.filter(\.isOnline).count,
            ],
            "communications": [
                "chat_count": chatMessages.count,
                "radio_reports": radioReports.count,
                "commands": sentCommands.count,
            ],
            "decisions_count": 0,  // backendDecisions 統計由後台提供
            "photos_count": photoAlerts.count,
            "event_duration_minutes": durationMinutes,
        ]

        DispatchQueue.main.async { [weak self] in
            self?.latestStatsUpdate = stats
        }
    }

    /// 產生本地資源概況（Mac-only 離線模式）
    func computeLocalResources() {
        let online = fieldUnits.filter(\.isOnline).count
        let total = fieldUnits.count

        let resources: [String: Any] = [
            "_source": "local",
            "summary": [
                "救護人員": ["total": allTeamMembers.count, "available": allTeamMembers.count],
                "通訊裝置": ["total": total, "available": online],
            ],
            "resources": fieldUnits.map { unit -> [String: Any] in
                [
                    "resource_id": "field-device-\(unit.deviceID)",
                    "name": unit.deviceID,
                    "type": "通訊裝置",
                    "status": unit.isOnline ? "available" : "offline",
                    "total": 1,
                    "available": unit.isOnline ? 1 : 0,
                    "assigned_zone": "",
                    "allocations": [],
                ]
            },
        ]

        DispatchQueue.main.async { [weak self] in
            if self?.latestResourceUpdate == nil {
                self?.latestResourceUpdate = resources
            }
        }
    }
}
