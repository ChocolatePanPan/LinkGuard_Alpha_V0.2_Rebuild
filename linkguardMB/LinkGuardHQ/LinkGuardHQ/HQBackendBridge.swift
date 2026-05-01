import Foundation
import Network
import Combine

// MARK: - URL helper（處理 IPv6 link-local zone 等情況）

/// 為 backend host 建構合法 URL：
/// - IPv4 / domain：直接使用
/// - IPv6：以 `[...]` 包覆，並將 zone identifier `%enX` percent-encode 為 `%25enX`
/// - 同時去除可能誤帶的 scheme/path/空白
func makeBackendURL(host rawHost: String, port: Int, path: String) -> URL? {
    var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return nil }

    // 移除誤輸入的 scheme 與尾部斜線
    if let r = host.range(of: "://") { host = String(host[r.upperBound...]) }
    host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    // 若使用者輸入含 port，砍掉（IPv6 例外，因為含多個冒號）
    if !host.contains(":") || host.hasPrefix("[") {
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
    }

    // IPv6 偵測（含多個冒號且不是已用 `[]` 包覆）
    let isIPv6 = host.filter { $0 == ":" }.count >= 2 && !host.hasPrefix("[")
    if isIPv6 {
        if let pct = host.firstIndex(of: "%") {
            let zone = host[host.index(after: pct)...]
            host = String(host[..<pct]) + "%25" + zone
        }
        host = "[\(host)]"
    } else {
        // IPv4 / domain：剝除誤帶的 zone identifier（例如 "192.168.50.22%en0"）
        if let pct = host.firstIndex(of: "%") {
            host = String(host[..<pct])
        }
    }

    let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: "http://\(host):\(port)\(normalizedPath)")
}

// MARK: - HQ 後台橋接器（選用）

/// 連接 Mac HQ 到外部 Backend TCP Server (port 9000)（選用，Mac 本身即主伺服器）
/// 可將前線數據轉發至外部後台，並接收後台的決策/氣象/節點資訊回傳前線
@MainActor
class HQBackendBridge: ObservableObject {
    @Published var isConnected = false
    @Published var backendHost: String = ""
    @Published var lastError: String?
    @Published var backendDecisions: [BackendDecision] = []
    @Published var backendWeather: BackendWeather?

    /// 從 NWEndpoint.Host 萃取適合放進 backendHost 的字串：
    /// - IPv4 直接回傳
    /// - IPv6 link-local（fe80::）跳過（回傳空字串），避免後續所有 HTTP 呼叫無法建立 URL
    /// - 其他 IPv6 / domain name 回傳原字串
    static func normalizeHost(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let v4):
            // v4.debugDescription 在某些情境會帶 zone identifier（如 "192.168.50.22%en0"）
            // 統一剝除，避免下游 URL 建構失敗
            let s = v4.debugDescription
            if let pct = s.firstIndex(of: "%") {
                return String(s[..<pct])
            }
            return s
        case .ipv6(let v6):
            let s = v6.debugDescription
            if s.lowercased().hasPrefix("fe80") {
                print("[Bridge] 跳過 IPv6 link-local: \(s)")
                return ""
            }
            return s
        case .name(let n, _):
            return n
        @unknown default:
            return "\(host)"
        }
    }
    @Published var loraNodes: [LoRaNodeStatus] = []
    @Published var isRequestingAI = false
    @Published var latestAIDecision: BackendDecision?
    @Published var rankedPatients: [PatientDecisionEntry] = []
    /// 雙 AI 共識升級觸發（由 win11 後端 tcp_server 廣播）
    @Published var latestEscalationTrigger: [String: Any]? = nil

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.linkguard.backend-bridge")
    private var reconnectTask: DispatchWorkItem?
    private var pingTimer: Timer?
    private var aiTimeoutTask: DispatchWorkItem?

    // Bonjour 自動探索
    @Published var isDiscovering: Bool = false
    private var browsers: [NWBrowser] = []
    private var resolveConnection: NWConnection?
    private var hasAutoConnected = false

    weak var server: HQCommandServer?

    // MARK: - 連線管理

    func connect(host: String, port: UInt16 = 9000) {
        backendHost = host
        lastError = nil

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "無效的 port: \(port)"
            return
        }
        let params = NWParameters.tcp

        connection = NWConnection(host: nwHost, port: nwPort, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.lastError = nil
                    self.receiveBuffer = Data()
                    print("[Bridge] 已連接到後台 \(host):\(port)")
                    self.startPing()
                    self.sendHello()
                case .failed(let error):
                    print("[Bridge] 連線失敗: \(error)")
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.scheduleReconnect()
                case .cancelled:
                    self.isConnected = false
                    self.stopPing()
                default:
                    break
                }
            }
        }
        connection?.start(queue: queue)
        receiveLoop()
    }

    func disconnect() {
        stopAutoDiscovery()
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPing()
        connection?.cancel()
        connection = nil
        isConnected = false
        print("[Bridge] 已斷開後台連線")
    }

    // MARK: - Bonjour 自動探索（多服務類型）

    /// 同時搜尋多種 Bonjour 服務類型，自動連接到後台
    /// - `_linkguardpy._tcp`：tcp_server（完整橋接協議）
    /// - `_linkguard-hq._tcp`：hq_server（僅解析 IP 供 AI 呼叫）
    /// - `_linkguard-hq._tcp`：舊版 HQ 服務
    func startAutoDiscovery() {
        guard !isConnected, !isDiscovering else { return }
        isDiscovering = true
        hasAutoConnected = false
        stopBrowsers()

        let params = NWParameters()
        params.includePeerToPeer = false

        // 可完整橋接的服務類型（tcp_server）
        let bridgeTypes = ["_linkguardpy._tcp"]
        // 僅用於解析 IP 的服務類型（hq_server）
        let resolveOnlyTypes = ["_linkguard-hq._tcp"]

        // 搜尋可橋接的服務
        for serviceType in bridgeTypes {
            let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
            b.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    print("[Bridge] Bonjour 搜尋 \(serviceType) 失敗: \(error)")
                }
            }
            b.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                if let result = results.first {
                    Task { @MainActor [weak self] in
                        guard let self, !self.hasAutoConnected else { return }
                        self.hasAutoConnected = true
                        print("[Bridge] 發現 \(serviceType) 服務，嘗試完整橋接...")
                        self.connectViaBonjour(endpoint: result.endpoint)
                    }
                }
            }
            b.start(queue: queue)
            browsers.append(b)
        }

        // 搜尋僅解析 IP 的服務（如果橋接服務不可用，至少能取得 IP）
        for serviceType in resolveOnlyTypes {
            let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
            b.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    print("[Bridge] Bonjour 搜尋 \(serviceType) 失敗: \(error)")
                }
            }
            b.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                if let result = results.first {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // 只在尚未取得 backendHost 時解析 IP
                        if self.backendHost.isEmpty {
                            print("[Bridge] 發現 \(serviceType) 服務，解析 IP...")
                            self.resolveEndpointForIP(result.endpoint)
                        }
                    }
                }
            }
            b.start(queue: queue)
            browsers.append(b)
        }

        print("[Bridge] 開始搜尋後台服務（_linkguardpy, _linkguard, _linkguard-hq）...")
    }

    func stopAutoDiscovery() {
        stopBrowsers()
        resolveConnection?.cancel()
        resolveConnection = nil
        isDiscovering = false
    }

    private func stopBrowsers() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }

    /// 僅解析 Bonjour endpoint 的 IP，不建立橋接協議
    private func resolveEndpointForIP(_ endpoint: NWEndpoint) {
        resolveConnection?.cancel()
        let params = NWParameters.tcp
        resolveConnection = NWConnection(to: endpoint, using: params)
        resolveConnection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    if let path = self.resolveConnection?.currentPath,
                       let remote = path.remoteEndpoint,
                       case .hostPort(let host, _) = remote {
                        let ip = Self.normalizeHost(host)
                        if !ip.isEmpty, self.backendHost.isEmpty {
                            self.backendHost = ip
                            self.isDiscovering = false
                            print("[Bridge] 從 Bonjour 自動取得後台 IP: \(ip)")
                        }
                    }
                    self.resolveConnection?.cancel()
                    self.resolveConnection = nil
                case .failed(_):
                    self.resolveConnection?.cancel()
                    self.resolveConnection = nil
                default:
                    break
                }
            }
        }
        resolveConnection?.start(queue: self.queue)
    }

    /// 透過 Bonjour endpoint 建立 TCP 連線（不需預先知道 IP）
    /// 後台 IP 將從首個 pong 訊息中取得，以供後續 HTTP 呼叫使用
    private func connectViaBonjour(endpoint: NWEndpoint) {
        stopAutoDiscovery()
        lastError = nil
        backendHost = "" // 待 pong 帶回 server_ip 後填入

        let params = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.lastError = nil
                    self.receiveBuffer = Data()
                    print("[Bridge] 已自動連接到後台（Bonjour）")
                    // 從已解析的連線路徑取得 IP（備援機制）
                    if self.backendHost.isEmpty,
                       let path = self.connection?.currentPath,
                       let remote = path.remoteEndpoint,
                       case .hostPort(let host, _) = remote {
                        let ip = Self.normalizeHost(host)
                        if !ip.isEmpty {
                            self.backendHost = ip
                            print("[Bridge] 從連線路徑取得後台 IP: \(self.backendHost)")
                        }
                    }
                    self.startPing()
                    self.sendHello()
                case .failed(let error):
                    print("[Bridge] Bonjour 連線失敗: \(error)")
                    self.isConnected = false
                    self.backendHost = ""
                    self.lastError = error.localizedDescription
                    // 重新啟動探索
                    self.startAutoDiscovery()
                case .cancelled:
                    self.isConnected = false
                    self.stopPing()
                default:
                    break
                }
            }
        }
        connection?.start(queue: queue)
        receiveLoop()
    }

    private func scheduleReconnect() {
        stopPing()
        reconnectTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isConnected, !self.backendHost.isEmpty else { return }
                print("[Bridge] 嘗試重新連接...")
                self.connect(host: self.backendHost)
            }
        }
        reconnectTask = task
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: task)
    }

    // MARK: - 心跳

    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendToBackend(type: "ping", data: [:])
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - 發送到後台

    private func sendHello() {
        sendToBackend(type: "ping", data: [
            "role": "hq",
            "name": "HQ-Alpha",
        ])
    }

    /// HQ 主動請求後台 AI 生成決策
    func requestAIDecision(context: String = "") {
        guard isConnected else { return }
        isRequestingAI = true
        lastError = nil
        sendToBackend(type: "request_decision", data: ["voice_text": context], deviceId: "HQ")
        // 安全逾時：若 120 秒內無回應則重置狀態
        aiTimeoutTask?.cancel()
        aiTimeoutTask = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRequestingAI else { return }
                self.isRequestingAI = false
                self.lastError = "AI 決策逾時（120 秒無回應）"
                print("[Bridge] AI 決策請求逾時")
            }
        }
        if let task = aiTimeoutTask {
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: task)
        }
    }

    /// 將前線傷員資料轉發到後台
    func forwardPatient(_ report: PatientReport) {
        var patientData: [String: Any] = [
            "id": report.patientId,
            "location": report.location,
            "breathing_rate": report.breathingRate,
            "capillary_refill": report.capillaryRefill,
            "can_follow_commands": report.canFollowCommands,
            "notes": report.notes,
        ]
        if let lat = report.gpsLat, let lon = report.gpsLon {
            patientData["gps"] = ["lat": lat, "lon": lon]
        }
        sendToBackend(type: "patient", data: patientData, deviceId: "HQ-bridge")
    }

    /// 將前線位置資料轉發到後台
    func forwardLocation(deviceId: String, location: [String: Any]) {
        var locData: [String: Any] = [:]
        locData["lat"] = location["lat"]
        locData["lon"] = location["lon"]
        locData["accuracy"] = location["accuracy"]
        locData["role"] = location["role"]
        locData["name"] = location["name"]
        sendToBackend(type: "location", data: locData, deviceId: deviceId)
    }

    /// 將語音辨識結果轉發到後台
    func forwardVoiceResult(text: String, deviceId: String) {
        sendToBackend(type: "voice_result", data: ["text": text], deviceId: deviceId)
    }

    // MARK: - 完整中繼層（iOS → Mac → Windows）

    /// 轉發裝置狀態報告
    func forwardStatusReport(deviceId: String, data: [String: Any]) {
        sendToBackend(type: "status_report", data: data, deviceId: deviceId)
    }

    /// 轉發聊天訊息
    func forwardChat(data: [String: Any], deviceId: String) {
        sendToBackend(type: "chat_message", data: data, deviceId: deviceId)
    }

    /// 轉發快速狀態
    func forwardQuickStatus(data: [String: Any], deviceId: String) {
        sendToBackend(type: "quick_status", data: data, deviceId: deviceId)
    }

    /// 轉發任務更新
    func forwardTaskUpdate(data: [String: Any], deviceId: String) {
        sendToBackend(type: "task_update", data: data, deviceId: deviceId)
    }

    /// 轉發危險回報
    func forwardHazardReport(data: [String: Any], deviceId: String) {
        sendToBackend(type: "hazard_report", data: data, deviceId: deviceId)
    }

    /// 轉發增援請求
    func forwardReinforcementRequest(data: [String: Any], deviceId: String) {
        sendToBackend(type: "reinforcement_request", data: data, deviceId: deviceId)
    }

    /// 轉發增援回覆
    func forwardReinforcementReply(data: [String: Any], deviceId: String) {
        sendToBackend(type: "reinforcement_reply", data: data, deviceId: deviceId)
    }

    /// 轉發 PTT 廣播控制
    func forwardRadioControl(data: [String: Any], deviceId: String) {
        sendToBackend(type: "radio_control", data: data, deviceId: deviceId)
    }

    /// 轉發 SOS 緊急呼叫
    func forwardSOS(data: [String: Any], deviceId: String) {
        sendToBackend(type: "sos", data: data, deviceId: deviceId)
    }

    /// 轉發 SOS 取消
    func forwardSOSCancel(data: [String: Any], deviceId: String) {
        sendToBackend(type: "sos_cancel", data: data, deviceId: deviceId)
    }

    /// 轉發照片回報
    func forwardPhotoAlert(data: [String: Any], deviceId: String) {
        sendToBackend(type: "photo_alert", data: data, deviceId: deviceId)
    }

    /// 轉發文字廣播
    func forwardTextBroadcast(data: [String: Any], deviceId: String) {
        sendToBackend(type: "text_broadcast", data: data, deviceId: deviceId)
    }

    /// 轉發已讀回條
    func forwardMessageAck(data: [String: Any], deviceId: String) {
        sendToBackend(type: "message_ack", data: data, deviceId: deviceId)
    }

    /// 轉發傷患惡化預警
    func forwardPatientWarning(data: [String: Any], deviceId: String) {
        sendToBackend(type: "patient_warning", data: data, deviceId: deviceId)
    }

    /// 轉發翻譯請求（記錄用）
    func forwardTranslateRequest(data: [String: Any], deviceId: String) {
        sendToBackend(type: "translate_request", data: data, deviceId: deviceId)
    }

    /// 將照片二進位轉發到 Windows photo_server
    func forwardPhotoToBackend(photoData: Data, metadata: [String: String]) {
        guard isConnected, !backendHost.isEmpty else { return }
        guard let url = makeBackendURL(host: backendHost, port: 8004, path: "/photo") else {
            print("[Bridge] 照片轉發失敗：URL 無效 host=\(backendHost)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // 文字欄位
        for (key, value) in metadata {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        // 照片檔案
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(photoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[Bridge] 照片轉發失敗: \(error)")
            } else {
                print("[Bridge] 照片已轉發到 Windows photo_server")
            }
        }.resume()
    }

    /// 將會報音訊轉發到 Windows http_server
    func forwardReportToBackend(audioData: Data, metadata: [String: String]) {
        guard isConnected, !backendHost.isEmpty else { return }
        guard let url = makeBackendURL(host: backendHost, port: 8003, path: "/report") else {
            print("[Bridge] 會報轉發失敗：URL 無效 host=\(backendHost)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (key, value) in metadata {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"report.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[Bridge] 會報轉發失敗: \(error)")
            } else {
                print("[Bridge] 會報已轉發到 Windows http_server")
            }
        }.resume()
    }

    /// 通用發送方法
    private func sendToBackend(type: String, data: [String: Any], deviceId: String = "HQ") {
        guard isConnected else { return }

        let msg: [String: Any] = [
            "type": type,
            "data": data,
            "device_id": deviceId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: msg),
              let line = String(data: jsonData, encoding: .utf8) else { return }

        let payload = Data((line + "\n").utf8)
        connection?.send(content: payload, completion: .contentProcessed { error in
            if let error {
                print("[Bridge] 發送失敗: \(error)")
            }
        })
    }

    // MARK: - 接收後台訊息

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data {
                Task { @MainActor [weak self] in
                    self?.processReceivedData(data)
                }
            }
            if isComplete || error != nil {
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    self?.scheduleReconnect()
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.receiveLoop()
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
            receiveBuffer = receiveBuffer[(newlineIndex + 1)...]

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            let msgData = json["data"] as? [String: Any] ?? [:]
            handleBackendMessage(type: type, data: msgData)
        }
    }

    private func handleBackendMessage(type: String, data: [String: Any]) {
        switch type {

        case "decision", "decision_update":
            // 後台 AI 決策（含初步 + 升級進度）→ 儲存 + 廣播給前線
            let decision = BackendDecision(
                decision: data["decision"] as? String ?? "",
                trigger: data["trigger"] as? String ?? "",
                timestamp: data["timestamp"] as? String ?? "",
                patients: parsePatientEntries(data["patients"]),
                weather: data["weather"] as? [String: Any],
                model: data["model"] as? String ?? "",
                escalated: data["escalated"] as? Bool ?? false,
                requestId: data["request_id"] as? String,
                provisional: data["provisional"] as? Bool ?? false,
                escalationStatus: data["escalation_status"] as? String,
                queuePosition: data["queue_position"] as? Int,
                estimatedWaitSec: data["estimated_wait_sec"] as? Double,
                smallModelTimeMs: data["small_model_time_ms"] as? Int,
                largeModelTimeMs: data["large_model_time_ms"] as? Int,
                escalationError: data["error"] as? String
            )
            // 同 requestId in-place 更新；否則 insert
            if let rid = decision.requestId, !rid.isEmpty,
               let idx = backendDecisions.firstIndex(where: { $0.requestId == rid }) {
                backendDecisions[idx] = decision
            } else {
                backendDecisions.insert(decision, at: 0)
                if backendDecisions.count > 100 { backendDecisions = Array(backendDecisions.prefix(100)) }
            }

            // 解析氣象為 HQWeatherSnapshot
            var weatherSnapshot: HQWeatherSnapshot?
            if let w = decision.weather {
                weatherSnapshot = HQWeatherSnapshot(
                    temp: w["temperature"] as? Double,
                    humidity: w["humidity"] as? Double,
                    wind: w["wind_speed"] as? Double,
                    rainfall: w["rainfall"] as? Double
                )
            }

            // 轉為 HQDecisionPayload 廣播給前線裝置（含升級狀態）
            let payload = HQDecisionPayload(
                decision: decision.decision,
                patients: decision.patients,
                trigger: decision.trigger,
                weather: weatherSnapshot,
                timestamp: decision.timestamp,
                model: decision.model,
                escalated: decision.escalated,
                requestId: decision.requestId,
                provisional: decision.provisional,
                escalationStatus: decision.escalationStatus,
                queuePosition: decision.queuePosition,
                estimatedWaitSec: decision.estimatedWaitSec,
                smallModelTimeMs: decision.smallModelTimeMs,
                largeModelTimeMs: decision.largeModelTimeMs,
                error: decision.escalationError
            )
            server?.broadcastDecision(payload)

            // 最終決策才解除 isRequestingAI；provisional 保持 loading 狀態
            if !decision.provisional {
                isRequestingAI = false
                aiTimeoutTask?.cancel()
            }
            latestAIDecision = decision
            print("[Bridge] 收到後台決策 (\(type)) provisional=\(decision.provisional) status=\(decision.escalationStatus ?? "-") rid=\(decision.requestId ?? "-")")

        case "patient_ranking":
            // 後台 START triage 評分排序 → 儲存 + 廣播給前線
            let patients = parsePatientEntries(data["patients"])
            rankedPatients = patients
            server?.relayBackendJSON(msgType: "patient_ranking", data: data)
            print("[Bridge] 收到傷患排序: \(patients.count) 人")

        case "weather_update":
            // 後台氣象更新
            let weather = BackendWeather(
                temperature: data["temperature"] as? Double,
                humidity: data["humidity"] as? Double,
                windSpeed: data["wind_speed"] as? Double,
                rainfall: data["rainfall"] as? Double,
                obsTime: data["obs_time"] as? String
            )
            backendWeather = weather

            // 轉為 PWSAlert 廣播給前線
            if let temp = weather.temperature {
                let alert = PWSAlert(
                    alertType: .other,
                    title: "氣象更新",
                    content: String(format: "溫度 %.1f°C｜濕度 %.0f%%｜風速 %.1f m/s",
                                    temp, weather.humidity ?? 0, weather.windSpeed ?? 0),
                    severity: .info
                )
                server?.broadcastPWSAlert(alert)
            }
            print("[Bridge] 收到氣象更新: \(data)")

        case "node_status":
            // LoRa 節點狀態
            if let nodes = data["nodes"] as? [[String: Any]] {
                loraNodes = nodes.compactMap { node in
                    guard let nodeId = node["node_id"] as? String else { return nil }
                    return LoRaNodeStatus(
                        nodeId: nodeId,
                        rssi: node["rssi"] as? Int ?? 0,
                        snr: node["snr"] as? Double ?? 0,
                        battery: node["battery"] as? Int ?? 0,
                        lat: node["lat"] as? Double,
                        lon: node["lon"] as? Double,
                        pdr: node["pdr"] as? Double
                    )
                }
            }

        case "pong":
            // 若是透過 Bonjour 自動連線，從 pong 中取得後台 IP 供 HTTP 呼叫使用
            if backendHost.isEmpty, let serverIP = data["server_ip"] as? String, !serverIP.isEmpty {
                backendHost = serverIP
                print("[Bridge] 自動取得後台 IP: \(serverIP)")
            }
            break

        case "ack":
            break

        case "error":
            let errorMsg = data["message"] as? String ?? "Unknown error"
            print("[Bridge] 後台錯誤: \(errorMsg)")
            lastError = errorMsg
            isRequestingAI = false
            aiTimeoutTask?.cancel()

        case "report_summary":
            // 會報摘要 → 廣播給前線裝置
            server?.relayBackendJSON(msgType: "report_summary", data: data)
            print("[Bridge] 中繼會報摘要: \(data["report_id"] as? String ?? "?")")

        case "voice_broadcast_rx":
            // 語音廣播狀態 → 廣播給前線裝置
            server?.relayBackendJSON(msgType: "radio_control", data: data)

        case "stats_update":
            // 統計更新 → 更新 HQ 本地顯示 + 廣播給前線裝置
            var tagged = data
            tagged["_source"] = "backend"
            server?.latestStatsUpdate = tagged
            server?.relayBackendJSON(msgType: "stats_update", data: data)

        case "resource_update":
            // 資源更新 → 更新 HQ 本地顯示 + 廣播給前線裝置
            server?.latestResourceUpdate = data
            server?.relayBackendJSON(msgType: "resource_update", data: data)

        case "photo_alert":
            // 照片回報 → 更新 HQ 照片牆 + 廣播給前線裝置
            server?.photoAlerts.insert(data, at: 0)
            server?.relayBackendJSON(msgType: "photo_alert", data: data)
            print("[Bridge] 中繼照片回報: \(data["photo_id"] as? String ?? "?")")

        case "translate_result":
            // 翻譯結果 → 透過 requesting_device_id 路由回原始請求的前線裝置
            if let reqId = data["requesting_device_id"] as? String, !reqId.isEmpty {
                server?.relayBackendJSON(msgType: "translate_result", data: data, targetDeviceID: reqId)
                print("[Bridge] 中繼翻譯結果 → \(reqId)")
            } else {
                server?.relayBackendJSON(msgType: "translate_result", data: data)
                print("[Bridge] 中繼翻譯結果（廣播）")
            }

        case "escalation_trigger":
            // 雙 AI 共識升級觸發：更新 HQ UI 狀態 + 廣播給前線裝置
            self.latestEscalationTrigger = data
            server?.relayBackendJSON(msgType: "escalation_trigger", data: data)
            print("[Bridge] 雙 AI 共識升級觸發: request_id=\(data["request_id"] as? String ?? "?")")

        default:
            print("[Bridge] 未處理的後台訊息: \(type)")
        }
    }

    // MARK: - 輔助解析

    private func parsePatientEntries(_ raw: Any?) -> [PatientDecisionEntry] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String ?? entry["patient_id"] as? String else { return nil }
            return PatientDecisionEntry(
                id: id,
                location: entry["location"] as? String ?? "",
                priority: entry["priority"] as? String ?? "",
                reason: entry["reason"] as? String ?? "",
                totalScore: entry["total_score"] as? Double ?? 0.0,
                startBonus: entry["start_bonus"] as? Int ?? 0,
                rank: entry["rank"] as? Int ?? 0
            )
        }
    }
}

// MARK: - 後台資料模型

struct BackendDecision: Identifiable {
    let id = UUID()
    var decision: String
    let trigger: String
    let timestamp: String
    var patients: [PatientDecisionEntry]
    let weather: [String: Any]?
    var model: String
    var escalated: Bool
    // 雙模型升級欄位（V2）
    var requestId: String?
    var provisional: Bool
    var escalationStatus: String?  // pending|queued|processing|done|failed|not_required|peer_offline
    var queuePosition: Int?
    var estimatedWaitSec: Double?
    var smallModelTimeMs: Int?
    var largeModelTimeMs: Int?
    var escalationError: String?
}

struct BackendWeather {
    let temperature: Double?
    let humidity: Double?
    let windSpeed: Double?
    let rainfall: Double?
    let obsTime: String?
}

struct LoRaNodeStatus: Identifiable {
    var id: String { nodeId }
    let nodeId: String
    let rssi: Int
    let snr: Double
    let battery: Int
    let lat: Double?
    let lon: Double?
    let pdr: Double?
}
