import Foundation
import Network
import Combine

// MARK: - 已發現的 HQ 伺服器

struct DiscoveredHQServer: Identifiable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
}

// MARK: - HQ Peer 用戶端
// 以 "hq_peer" 角色連線到另一台裝置的 HQCommandServer，
// 同步命令、聊天、災害狀態等，並可透過 hq_command 送出命令。

class HQPeerClient: ObservableObject {

    // MARK: - 連線狀態
    @Published var isSearching = false
    @Published var isConnected = false
    @Published var connectedServerName = ""
    @Published var discoveredServers: [DiscoveredHQServer] = []

    // MARK: - 從伺服器同步的狀態
    @Published var sentCommands: [WiFiCommand] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var disasterSite: DisasterSite?
    @Published var pwsAlerts: [PWSAlert] = []
    @Published var personnelAssignments: [PersonnelAssignment] = []
    @Published var briefings: [BriefingReport] = []
    @Published var personalNotifications: [PersonalNotification] = []
    @Published var timelineEvents: [TimelineEvent] = []
    @Published var tasks: [TaskAssignment] = []
    @Published var countdownTimers: [CountdownTimerModel] = []
    @Published var hazardReports: [HazardReport] = []
    @Published var reinforcementRequests: [ReinforcementRequest] = []
    @Published var activeSOSAlerts: [SOSAlert] = []
    @Published var radioReports: [HQRadioReport] = []
    @Published var currentBroadcaster: String?
    @Published var serverStatus: HQServerStatusSnapshot?

    // MARK: - 本機身份
    var myID: String = "HQ-Peer"
    var myName: String = "HQ 指揮官"

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.linkguard.hqpeerclient")

    // MARK: - 發現 HQ 伺服器

    func startBrowsing() {
        guard !isSearching else { return }
        DispatchQueue.main.async { self.isSearching = true; self.discoveredServers = [] }

        let params = NWParameters()
        params.includePeerToPeer = false
        browser = NWBrowser(
            for: .bonjour(type: "_linkguard-hq._tcp", domain: nil),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                print("[HQPeer] Browse error: \(error)")
                DispatchQueue.main.async { self?.isSearching = false }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredServers = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredHQServer(name: name, endpoint: result.endpoint)
                }
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async { self.isSearching = false }
    }

    // MARK: - 連線到選定伺服器

    func connect(to server: DiscoveredHQServer) {
        disconnect()
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let conn = NWConnection(to: server.endpoint, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.connectedServerName = server.name
                }
                self.sendHello()
                self.receiveLoop()
                print("[HQPeer] Connected to \(server.name)")
            case .failed(let error):
                print("[HQPeer] Connection failed: \(error)")
                DispatchQueue.main.async { self.isConnected = false; self.connectedServerName = "" }
            case .cancelled:
                DispatchQueue.main.async { self.isConnected = false; self.connectedServerName = "" }
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedServerName = ""
            self.serverStatus = nil
        }
    }

    // MARK: - 握手

    private func sendHello() {
        let payload = HQHelloPayload(role: "hq_peer", id: myID, name: myName)
        send(msgType: "hello", encodable: payload)
    }

    // MARK: - 送出命令（讓伺服器廣播給所有前線裝置）

    func sendCommand(_ cmd: WiFiCommand) {
        send(msgType: "hq_command", encodable: cmd)
    }

    func sendChat(_ chat: ChatMessage) {
        DispatchQueue.main.async {
            self.chatMessages.append(chat)
            if self.chatMessages.count > 500 { self.chatMessages = Array(self.chatMessages.suffix(300)) }
        }
        send(msgType: "chat_message", encodable: chat)
    }

    func assignTask(_ task: TaskAssignment) {
        send(msgType: "hq_task_assign", encodable: task)
    }

    func startTimer(_ timer: CountdownTimerModel) {
        send(msgType: "hq_timer_start", encodable: timer)
    }

    func cancelTimer(_ timerID: String) {
        send(msgType: "hq_timer_cancel", encodable: ["id": timerID])
    }

    func sendDecision(_ payload: HQDecisionPayload) {
        send(msgType: "hq_decision", encodable: payload)
    }

    func requestAIDecision(context: String) {
        send(msgType: "hq_ai_request", encodable: ["context": context])
    }

    // MARK: - 接收迴圈

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.receiveBuffer.append(data)
                while let nlIdx = self.receiveBuffer.firstIndex(of: 0x0A) {
                    let msgData = Data(self.receiveBuffer[self.receiveBuffer.startIndex..<nlIdx])
                    self.receiveBuffer = Data(self.receiveBuffer[self.receiveBuffer.index(after: nlIdx)...])
                    if !msgData.isEmpty,
                       let msg = try? JSONDecoder().decode(WiFiMessage.self, from: msgData) {
                        self.handleMessage(msg)
                    }
                }
            }
            if !isComplete && error == nil { self.receiveLoop() }
        }
    }

    private func handleMessage(_ msg: WiFiMessage) {
        guard let data = msg.payload.data(using: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch msg.msgType {
            case "command":
                if let cmd = try? JSONDecoder().decode(WiFiCommand.self, from: data) {
                    if !self.sentCommands.contains(where: { $0.id == cmd.id }) {
                        self.sentCommands.insert(cmd, at: 0)
                        if self.sentCommands.count > 100 { self.sentCommands = Array(self.sentCommands.prefix(100)) }
                    }
                }
            case "chat_message":
                if let chat = try? JSONDecoder().decode(ChatMessage.self, from: data),
                   !self.chatMessages.contains(where: { $0.id == chat.id }) {
                    self.chatMessages.append(chat)
                    if self.chatMessages.count > 500 { self.chatMessages = Array(self.chatMessages.suffix(300)) }
                }
            case "disaster_update":
                self.disasterSite = try? JSONDecoder().decode(DisasterSite.self, from: data)
            case "pws_alert":
                if let alert = try? JSONDecoder().decode(PWSAlert.self, from: data) {
                    if let idx = self.pwsAlerts.firstIndex(where: { $0.id == alert.id }) {
                        self.pwsAlerts[idx] = alert
                    } else {
                        self.pwsAlerts.insert(alert, at: 0)
                    }
                }
            case "personnel_assignment":
                if let list = try? JSONDecoder().decode([PersonnelAssignment].self, from: data) {
                    self.personnelAssignments = list
                }
            case "briefing":
                if let b = try? JSONDecoder().decode(BriefingReport.self, from: data),
                   !self.briefings.contains(where: { $0.id == b.id }) {
                    self.briefings.insert(b, at: 0)
                    if self.briefings.count > 50 { self.briefings = Array(self.briefings.prefix(50)) }
                }
            case "personal_notification":
                if let notif = try? JSONDecoder().decode(PersonalNotification.self, from: data),
                   !self.personalNotifications.contains(where: { $0.id == notif.id }) {
                    self.personalNotifications.append(notif)
                }
            case "task_assignment":
                if let task = try? JSONDecoder().decode(TaskAssignment.self, from: data) {
                    if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                        self.tasks[idx] = task
                    } else {
                        self.tasks.append(task)
                    }
                }
            case "timer_sync":
                if let timer = try? JSONDecoder().decode(CountdownTimerModel.self, from: data) {
                    if let idx = self.countdownTimers.firstIndex(where: { $0.id == timer.id }) {
                        self.countdownTimers[idx] = timer
                    } else {
                        self.countdownTimers.append(timer)
                    }
                }
            case "timer_cancel":
                if let dict = try? JSONDecoder().decode([String: String].self, from: data),
                   let timerID = dict["id"] {
                    self.countdownTimers.removeAll { $0.id == timerID }
                }
            case "hazard_report":
                if let report = try? JSONDecoder().decode(HazardReport.self, from: data),
                   !self.hazardReports.contains(where: { $0.id == report.id }) {
                    self.hazardReports.insert(report, at: 0)
                }
            case "reinforcement_request", "reinforcement_reply":
                if let req = try? JSONDecoder().decode(ReinforcementRequest.self, from: data) {
                    if let idx = self.reinforcementRequests.firstIndex(where: { $0.id == req.id }) {
                        self.reinforcementRequests[idx] = req
                    } else {
                        self.reinforcementRequests.insert(req, at: 0)
                    }
                }
            case "radio_control":
                if let ctrl = try? JSONDecoder().decode(RadioControlPayload.self, from: data) {
                    self.currentBroadcaster = ctrl.action == "start" ? ctrl.senderName : nil
                }
            case "radio_report":
                if let decoded = try? JSONDecoder().decode(RadioReportSummary.self, from: data) {
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
                    self.radioReports.insert(report, at: 0)
                }
            case "sos_alert":
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let d = json["data"] as? [String: Any] ?? json
                    let sosId = d["sos_id"] as? String ?? UUID().uuidString
                    let deviceID = d["device_id"] as? String ?? ""
                    let senderName = d["sender_name"] as? String ?? deviceID
                    let lat = d["lat"] as? Double ?? 0
                    let lon = d["lon"] as? Double ?? 0
                    if !self.activeSOSAlerts.contains(where: { $0.deviceID == deviceID }) {
                        let alert = SOSAlert(id: sosId, deviceID: deviceID,
                                             senderName: senderName,
                                             lat: lat, lon: lon, timestamp: Date())
                        self.activeSOSAlerts.insert(alert, at: 0)
                    }
                }
            case "sos_cancel_alert":
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let d = json["data"] as? [String: Any] ?? json
                    let sosId = d["sos_id"] as? String ?? ""
                    let deviceID = d["device_id"] as? String ?? ""
                    self.activeSOSAlerts.removeAll { $0.id == sosId || $0.deviceID == deviceID }
                }
            case "ping":
                // 回覆 pong 給伺服器以維持心跳
                self.send(msgType: "pong", encodable: ["ts": Date().timeIntervalSince1970])
            case "server_status":
                self.serverStatus = try? JSONDecoder().decode(HQServerStatusSnapshot.self, from: data)
            default:
                break
            }
        }
    }

    // MARK: - 通用發送

    private func send<T: Encodable>(msgType: String, encodable: T) {
        guard let payloadData = try? JSONEncoder().encode(encodable),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }
        let msg = WiFiMessage(msgType: msgType, payload: payloadJSON)
        guard let data = try? JSONEncoder().encode(msg) else { return }
        connection?.send(content: data + Data([0x0A]), completion: .contentProcessed { _ in })
    }
}
