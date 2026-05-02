import SwiftUI
import AVFoundation
import CoreLocation
import Combine
import Network
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 電台模式

enum RadioMode: String, CaseIterable {
    case live = "即時廣播"
    case briefing = "固定會報"
    case aiChat = "AI 通訊"

    static let radioModes: [RadioMode] = [.live, .briefing]
}

// MARK: - 電台頁面

struct RadioView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var mode: RadioMode = .live
    @StateObject private var briefingManager = BriefingRecordManager()
    @StateObject private var liveManager = LiveBroadcastManager()
    @StateObject private var aiChatManager = FieldAIChatManager()
    private let initialMode: RadioMode
    private let showsModePicker: Bool
    private let embedsNavigationStack: Bool

    init(vm: LinkGuardViewModel, initialMode: RadioMode = .live, showsModePicker: Bool = true, embedsNavigationStack: Bool = true) {
        self.vm = vm
        self.initialMode = initialMode
        self.showsModePicker = showsModePicker
        self.embedsNavigationStack = embedsNavigationStack
        self._mode = State(initialValue: initialMode)
    }

    private var titleText: String {
        showsModePicker ? "電台" : initialMode.rawValue
    }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
                // 標題列
                HStack {
                    Text(L(titleText))
                        .font(.title2).bold()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 模式選擇器
                if showsModePicker {
                    Picker(L("模式"), selection: $mode) {
                        ForEach(RadioMode.radioModes, id: \.self) { m in
                            Text(L(m.rawValue)).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                Divider()

                // 模式內容
                switch mode {
                case .live:
                    liveContent
                case .briefing:
                    briefingContent
                case .aiChat:
                    aiChatContent
                }
            }
            .navigationTitle(L(titleText))
            #if os(iOS)
            .toolbarVisibility(.hidden, for: .navigationBar)
            #endif
            .onAppear {
                briefingManager.serverHost = vm.transcriptionServerHost
                liveManager.senderName = vm.nodeStatus.nodeID
                liveManager.serverHost = vm.transcriptionServerHost
                liveManager.startListening()
                aiChatManager.serverHost = vm.transcriptionServerHost
                aiChatManager.senderName = vm.nodeStatus.nodeID
            }
            .onDisappear {
                liveManager.stopListening()
            }
            .onChange(of: vm.transcriptionServerHost) { _, newHost in
                briefingManager.serverHost = newHost
                liveManager.serverHost = newHost
                aiChatManager.serverHost = newHost
            }
            .onReceive(vm.escalationTriggerPublisher) { json in
                let requestId = (json["request_id"] as? String) ?? ""
                let hqSummary = (json["hq_summary"] as? String) ?? ""
                let fieldSummary = (json["field_summary"] as? String) ?? ""
                let status = (json["status"] as? String) ?? "processing"
                aiChatManager.externalEscalationTrigger(
                    requestId: requestId,
                    hqSummary: hqSummary,
                    fieldSummary: fieldSummary,
                    status: status
                )
            }
    }

    // MARK: - 即時廣播模式

    private var liveContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // 廣播者狀態
            if let broadcaster = vm.currentBroadcaster {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(NV.danger)
                    Text(L("%@ 正在廣播", broadcaster))
                        .font(.headline)
                        .foregroundColor(NV.danger)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NV.danger.opacity(0.1))
                .cornerRadius(12)
            }

            // PTT 按鈕（純按住/放開，不用 Button 避免 action 衝突）
            ZStack {
                Circle()
                    .fill(liveManager.isBroadcasting ? NV.danger : Color.gray.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .shadow(color: liveManager.isBroadcasting ? NV.danger.opacity(0.5) : .clear, radius: 20)

                VStack(spacing: 8) {
                    Image(systemName: liveManager.isBroadcasting ? "mic.fill" : "mic")
                        .font(.system(size: 48))
                    Text(liveManager.isBroadcasting ? L("放開結束") : L("按住說話"))
                        .font(.caption)
                        .bold()
                }
                .foregroundColor(liveManager.isBroadcasting ? .white : .primary)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !liveManager.isBroadcasting {
                            liveManager.startBroadcast()
                            vm.commandClient.sendRadioStart(senderName: vm.nodeStatus.nodeID)
                        }
                    }
                    .onEnded { _ in
                        if liveManager.isBroadcasting {
                            liveManager.stopBroadcast()
                            vm.commandClient.sendRadioStop(senderName: vm.nodeStatus.nodeID)
                        }
                    }
            )

            Text(L("按住錄音，放開後自動上傳轉錄歸檔"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // 上傳進度
            if liveManager.isUploading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(liveManager.uploadProgress ?? L("上傳中…"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let progress = liveManager.uploadProgress {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NV.green)
                    Text(progress)
                        .font(.caption)
                        .foregroundColor(NV.green)
                }
            }

            // 錯誤訊息
            if let error = liveManager.connectionError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NV.danger)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(NV.danger)
                }
                .padding(.horizontal)
            }

            Spacer()

            // 自動 / 手動播放切換
            HStack {
                Image(systemName: vm.autoPlayRadio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundColor(vm.autoPlayRadio ? NV.green : .secondary)
                Text(vm.autoPlayRadio ? L("自動播放") : L("手動播放"))
                    .font(.caption)
                Toggle("", isOn: $vm.autoPlayRadio)
                    .labelsHidden()
                    .tint(NV.green)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // 連線狀態
            VStack(spacing: 4) {
                HStack {
                    Circle()
                        .fill(vm.commandClient.isConnected ? NV.green : .gray)
                        .frame(width: 8, height: 8)
                    Text(vm.commandClient.isConnected ? L("已連線 Mac HQ") : L("未連線 Mac HQ"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !vm.commandClient.isConnected {
                    Text(L("需先連線 Mac HQ 才能使用電台"))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.bottom)
        }
    }

    // MARK: - AI 通訊模式

    private var aiChatContent: some View {
        VStack(spacing: 0) {
            // 連線狀態
            if vm.isAIServicePaused {
                AIServicePausedBanner(message: vm.aiServicePauseMessage)
                    .padding(.horizontal)
                    .padding(.top, 8)
            } else if !vm.commandClient.isConnected {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text(L("需先連線 Mac HQ 才能使用 AI 通訊"))
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(NV.danger)
            }

            // 雙 AI 決策狀態列
            if let escalation = aiChatManager.activeEscalation {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("AI 判斷需上報"))
                            .font(.caption).bold()
                        Text(escalation.status == "queued"
                             ? "排隊中 #\(escalation.queuePosition)"
                             : escalation.status == "processing"
                             ? L("主模型處理中…")
                             : escalation.status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(NV.command.opacity(0.15))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 4)
            } else if aiChatManager.pendingEscalationHint {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(NV.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("等待 HQ AI 共識"))
                            .font(.caption).bold()
                        Text(L("現場 AI 已建議上報，等待 HQ 指揮官 AI 同步判斷"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(NV.warning.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 4)
            }

            VStack(spacing: 0) {
                // 訊息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(aiChatManager.messages) { msg in
                                AIChatBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: aiChatManager.messages.count) { _, _ in
                        if let last = aiChatManager.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // 快速提問模板
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(aiQuickPrompts, id: \.self) { prompt in
                            Button {
                                aiChatManager.send(prompt)
                            } label: {
                                Text(prompt)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(NV.command)
                            .disabled(aiChatManager.isLoading || !vm.commandClient.isConnected || vm.isAIServicePaused)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                // 輸入列
                HStack(spacing: 10) {
                    TextField(L("詢問 AI…"), text: $aiChatManager.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .submitLabel(.send)
                        .onSubmit {
                            guard !aiChatManager.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  vm.commandClient.isConnected,
                                  !vm.isAIServicePaused else { return }
                            aiChatManager.send(aiChatManager.draft)
                        }

                    if aiChatManager.isLoading {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else {
                        Button {
                            aiChatManager.send(aiChatManager.draft)
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                        }
                        .disabled(aiChatManager.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || !vm.commandClient.isConnected
                                  || vm.isAIServicePaused)
                        .tint(NV.command)
                    }
                }
                .padding()
            }
            .aiPausedAppearance(vm.isAIServicePaused)
        }
    }

    private var aiQuickPrompts: [String] {
        [
            "傷患優先處置建議",
            "現場風險評估",
            "需要哪些資源",
            "撤離路線建議",
        ]
    }

    // MARK: - 固定會報模式

    private var briefingContent: some View {
        VStack(spacing: 0) {
            // 錄音控制區
            VStack(spacing: 16) {
                // 錄音按鈕
                Button {
                    if briefingManager.isRecording {
                        briefingManager.stopRecording()
                        // 自動上傳
                        briefingManager.uploadRecording(
                            senderName: vm.nodeStatus.nodeID,
                            victims: vm.victims,
                            location: nil,
                            deviceID: vm.nodeStatus.nodeID
                        )
                    } else {
                        briefingManager.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(briefingManager.isRecording ? NV.danger : Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .shadow(color: briefingManager.isRecording ? NV.danger.opacity(0.4) : .clear, radius: 15)

                        VStack(spacing: 6) {
                            Image(systemName: briefingManager.isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 36))
                            Text(briefingManager.isRecording ? L("停止") : L("錄音"))
                                .font(.caption)
                                .bold()
                        }
                        .foregroundColor(briefingManager.isRecording ? .white : .primary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(briefingManager.isUploading)

                // 上傳進度
                if briefingManager.isUploading {
                    ProgressView(L("正在上傳會報..."))
                        .padding()
                }

                // 上傳結果
                if let result = briefingManager.uploadResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? NV.green : NV.danger)
                        Text(result.message)
                            .font(.caption)
                    }
                    .padding(.horizontal)

                    if !result.success {
                        Button(L("重試")) {
                            briefingManager.uploadRecording(
                                senderName: vm.nodeStatus.nodeID,
                                victims: vm.victims,
                                location: nil,
                                deviceID: vm.nodeStatus.nodeID
                            )
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()

            Divider()

            // 報告列表
            if vm.radioReports.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L("尚無會報紀錄"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(vm.radioReports.prefix(20)) { report in
                        ReportRow(report: report,
                                  isPlaying: vm.playingReportId == report.reportId,
                                  onPlay: { vm.playReportAudio(report) })
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - 報告列表行

private struct ReportRow: View {
    let report: RadioReport
    var isPlaying: Bool = false
    var onPlay: (() -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(NV.command)
                Text(report.senderName)
                    .font(.subheadline.bold())
                Spacer()

                // 手動播放按鈕
                if !report.audioUrl.isEmpty {
                    Button {
                        onPlay?()
                    } label: {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(isPlaying ? NV.danger : NV.command)
                    }
                    .buttonStyle(.plain)
                }

                Text(formatTimestamp(report.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !report.location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(report.location)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            if !report.transcription.isEmpty {
                Text(report.transcription)
                    .font(.caption)
                    .lineLimit(expanded ? nil : 2)
                    .onTapGesture { expanded.toggle() }
            }

            HStack {
                Text("ID: \(report.reportId)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

// MARK: - 固定會報錄音 & 上傳管理器

struct UploadResult {
    let success: Bool
    let message: String
}

@MainActor
final class BriefingRecordManager: ObservableObject {
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var uploadResult: UploadResult?

    var serverHost = "localhost"

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            print("[BriefingManager] Audio session error: \(error)")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("briefing_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingURL = url
            isRecording = true
            uploadResult = nil
        } catch {
            print("[BriefingManager] Record error: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
    }

    func uploadRecording(senderName: String, victims: [VictimNode], location: CLLocationCoordinate2D?,
                         weatherSnapshot: WeatherSnapshot? = nil, deviceID: String = "") {
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            uploadResult = UploadResult(success: false, message: L("找不到錄音檔案"))
            return
        }

        // 檢查 server
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "localhost" else {
            uploadResult = UploadResult(success: false, message: L("未連線 Mac HQ，無法上傳會報"))
            return
        }

        isUploading = true
        uploadResult = nil

        Task {
            do {
                let result = try await performUpload(
                    fileURL: url,
                    senderName: senderName,
                    victims: victims,
                    location: location,
                    weatherSnapshot: weatherSnapshot,
                    deviceID: deviceID
                )
                isUploading = false
                uploadResult = result
            } catch {
                isUploading = false
                uploadResult = UploadResult(success: false, message: L("上傳失敗：%@", error.localizedDescription))
            }
        }
    }

    private func performUpload(fileURL: URL, senderName: String, victims: [VictimNode],
                               location: CLLocationCoordinate2D?,
                               weatherSnapshot: WeatherSnapshot?,
                               deviceID: String) async throws -> UploadResult {
        let boundary = UUID().uuidString
        // 清理 host：移除 zone ID、IPv4-mapped IPv6 前綴
        var cleanHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pct = cleanHost.firstIndex(of: "%") {
            cleanHost = String(cleanHost[cleanHost.startIndex..<pct])
        }
        if cleanHost.hasPrefix("::ffff:") {
            cleanHost = String(cleanHost.dropFirst(7))
        }
        let host = cleanHost.contains(":") ? "[\(cleanHost)]" : cleanHost
        guard let uploadURL = URL(string: "http://\(host):8003/report") else {
            return UploadResult(success: false, message: L("無效的伺服器位址：%@", serverHost))
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        // 規範 4.4 欄位
        appendField("device_id", deviceID.isEmpty ? senderName : deviceID)
        appendField("sender_name", senderName)
        appendField("source_type", "briefing")
        appendField("location_lat", location.map { "\($0.latitude)" } ?? "0")
        appendField("location_lon", location.map { "\($0.longitude)" } ?? "0")
        appendField("location_desc", "")
        appendField("timestamp", ISO8601DateFormatter().string(from: Date()))

        // patients_snapshot
        let patientsArr = victims.prefix(50).map { v -> [String: Any] in
            ["id": v.id, "heartRate": v.heartRate, "isSOS": v.isSOS, "isOnline": v.isOnline]
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: patientsArr),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            appendField("patients_snapshot", jsonStr)
        } else {
            appendField("patients_snapshot", "[]")
        }

        // weather_snapshot
        if let w = weatherSnapshot,
           let wData = try? JSONEncoder().encode(w),
           let wStr = String(data: wData, encoding: .utf8) {
            appendField("weather_snapshot", wStr)
        } else {
            appendField("weather_snapshot", "{}")
        }

        // audio file — 規範欄位名稱 "audio"
        let audioData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"briefing.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n".utf8))

        // end
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            return UploadResult(success: false, message: L("無效回應"))
        }
        if httpResp.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reportId = json["report_id"] as? String {
                return UploadResult(success: true, message: L("上傳成功 (ID: %@)", reportId))
            }
            return UploadResult(success: true, message: L("上傳成功"))
        } else {
            return UploadResult(success: false, message: L("伺服器錯誤 (%lld)", httpResp.statusCode))
        }
    }
}

// MARK: - 即時廣播管理器（錄製後上傳模式）
//
// PTT 按住 → AVAudioRecorder 錄音（16kHz mono AAC）
// PTT 放開 → 停止錄音 → HTTP 上傳到 Mac HQ:8003/report（轉錄 + 廣播 report_summary）

@MainActor
final class LiveBroadcastManager: ObservableObject {
    @Published var isBroadcasting = false
    @Published var isUploading = false
    @Published var uploadProgress: String?
    @Published var connectionError: String?
    var senderName = ""
    var serverHost = ""

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// 錄音計時器（最長 60 秒自動停止）
    private var recordingTimer: Timer?
    /// 用於播放收到的廣播音訊
    private var audioPlayer: AVAudioPlayer?

    // MARK: - LGAP 即時串流（與 Android 一致）

    private var lgapConnection: NWConnection?
    private var lgapEngine: AVAudioEngine?
    private var lgapConverter: AVAudioConverter?
    private let lgapQueue = DispatchQueue(label: "com.linkguard.lgap", qos: .userInteractive)
    private static let lgapMagic: UInt32 = 0x4C474150  // "LGAP"
    private static let lgapSampleRate: Double = 16000
    private static let lgapPort: UInt16 = 8005

    // MARK: - PTT 錄音（發送端）

    func startBroadcast() {
        guard !isBroadcasting else { return }
        connectionError = nil
        uploadProgress = nil

        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "localhost" else {
            connectionError = L("未連線 Mac HQ，無法廣播")
            return
        }

        #if os(iOS)
        let perm = AVAudioSession.sharedInstance().recordPermission
        if perm != .granted {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    if granted {
                        self.startBroadcast()
                    } else {
                        self.connectionError = L("需要麥克風權限，請至設定開啟")
                    }
                }
            }
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[LiveBroadcast] ❌ AudioSession error: \(error)")
            connectionError = L("音訊初始化失敗")
            return
        }
        #endif

        // 建立錄音檔案
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingURL = url
            isBroadcasting = true
            print("[LiveBroadcast] 🎙️ Recording started: \(url.lastPathComponent)")

            // 同時啟動 LGAP TCP 即時串流（與 Android 一致）
            startLGAPStream()

            // 60 秒自動停止
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopBroadcast()
                }
            }
        } catch {
            print("[LiveBroadcast] ❌ Recording error: \(error)")
            connectionError = L("錄音啟動失敗")
        }
    }

    func stopBroadcast() {
        stopLGAPStream()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let wasBroadcasting = isBroadcasting
        isBroadcasting = false

        audioRecorder?.stop()
        audioRecorder = nil
        print("[LiveBroadcast] ⏹️ Recording stopped (wasBroadcasting=\(wasBroadcasting))")

        if wasBroadcasting {
            uploadRecording()
        }
    }

    // MARK: - HTTP 上傳（轉錄/歸檔）

    private func uploadRecording() {
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            print("[LiveBroadcast] ℹ️ No recording file to upload")
            return
        }

        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "localhost" else {
            connectionError = L("未連線 Mac HQ，無法上傳")
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("[LiveBroadcast] 📤 Uploading \(url.lastPathComponent) (\(fileSize) bytes)")

        if fileSize < 100 {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            return
        }

        // 檢查錄音時長：太短的錄音辨識不出內容
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        if duration < 1.0 {
            print("[LiveBroadcast] ⚠️ Recording too short (\(String(format: "%.1f", duration))s), skipping upload")
            connectionError = L("錄音太短，請按住至少 1 秒")
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.connectionError = nil
            }
            return
        }

        isUploading = true
        uploadProgress = L("上傳中…")

        Task {
            do {
                let result = try await performUpload(fileURL: url, host: host)
                isUploading = false
                if result.success {
                    uploadProgress = L("傳送成功")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.uploadProgress = nil
                    }
                } else {
                    uploadProgress = nil
                    connectionError = result.errorMessage ?? L("上傳失敗")
                    print("[LiveBroadcast] ⚠️ Upload failed: \(result.errorMessage ?? "unknown")")
                }
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
            } catch {
                isUploading = false
                uploadProgress = nil
                connectionError = "上傳失敗：\(error.localizedDescription)"
                print("[LiveBroadcast] ⚠️ Upload error: \(error)")
            }
        }
    }

    private struct PTTUploadResult {
        let success: Bool
        let errorMessage: String?
    }

    private func performUpload(fileURL: URL, host: String) async throws -> PTTUploadResult {
        let boundary = UUID().uuidString
        // 清理 host：移除 zone ID、IPv4-mapped IPv6 前綴
        var cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pct = cleanHost.firstIndex(of: "%") {
            cleanHost = String(cleanHost[cleanHost.startIndex..<pct])
        }
        if cleanHost.hasPrefix("::ffff:") {
            cleanHost = String(cleanHost.dropFirst(7))
        }
        let hostStr = cleanHost.contains(":") ? "[\(cleanHost)]" : cleanHost
        guard let uploadURL = URL(string: "http://\(hostStr):8003/report") else {
            print("[LiveBroadcast] ❌ Invalid URL: http://\(hostStr):8003/report (original host: \(host))")
            return PTTUploadResult(success: false, errorMessage: L("無效的伺服器位址：%@", host))
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("device_id", senderName)
        appendField("sender_name", senderName)
        appendField("source_type", "live")
        appendField("location_lat", "0")
        appendField("location_lon", "0")
        appendField("location_desc", "")
        appendField("timestamp", ISO8601DateFormatter().string(from: Date()))
        appendField("patients_snapshot", "[]")
        appendField("weather_snapshot", "{}")

        let audioData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"ptt.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body
        print("[LiveBroadcast] 📤 Sending \(body.count) bytes to \(uploadURL)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            return PTTUploadResult(success: false, errorMessage: L("無效回應"))
        }
        if httpResp.statusCode == 200 {
            return PTTUploadResult(success: true, errorMessage: nil)
        } else {
            var errMsg = "伺服器錯誤 (\(httpResp.statusCode))"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverErr = json["error"] as? String {
                errMsg = serverErr
            }
            return PTTUploadResult(success: false, errorMessage: errMsg)
        }
    }

    // MARK: - 接收播放

    /// 下載並播放指定 audioUrl 的音訊（由 ViewModel 收到 report_summary 時呼叫）
    func playReceivedAudio(from urlString: String) {
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    print("[LiveBroadcast] ❌ Audio download failed")
                    return
                }

                #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                #endif

                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
                print("[LiveBroadcast] ▶️ Playing received audio (\(data.count) bytes)")
            } catch {
                print("[LiveBroadcast] ❌ Audio playback error: \(error)")
            }
        }
    }

    func startListening() {
        print("[LiveBroadcast] ✅ Ready (LGAP real-time + record-then-upload mode)")
    }

    func stopListening() {
        stopLGAPStream()
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - LGAP TCP 即時串流

    /// 啟動 LGAP 即時串流：AVAudioEngine 擷取 PCM → TCP 傳送到 HQ:8005
    private func startLGAPStream() {
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "localhost" else {
            print("[LGAP] ⚠️ No valid server host, skipping LGAP stream")
            return
        }

        var cleanHost = host
        if let pct = cleanHost.firstIndex(of: "%") {
            cleanHost = String(cleanHost[cleanHost.startIndex..<pct])
        }
        if cleanHost.hasPrefix("::ffff:") {
            cleanHost = String(cleanHost.dropFirst(7))
        }

        // 1. TCP 連線到 HQ LGAP 伺服器 (port 8005)
        let tcpParams = NWParameters.tcp
        tcpParams.requiredInterfaceType = .wifi
        guard let nwPort = NWEndpoint.Port(rawValue: Self.lgapPort) else {
            print("[LGAP] ❌ Invalid port: \(Self.lgapPort)")
            return
        }
        let conn = NWConnection(
            host: NWEndpoint.Host(cleanHost),
            port: nwPort,
            using: tcpParams
        )
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[LGAP] ✅ Connected to \(cleanHost):\(Self.lgapPort)")
            case .failed(let error):
                print("[LGAP] ❌ Connection failed: \(error)")
            case .cancelled:
                print("[LGAP] ⏹️ Connection cancelled")
            default:
                break
            }
        }
        conn.start(queue: lgapQueue)
        lgapConnection = conn

        // 2. AVAudioEngine 擷取麥克風 PCM
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.lgapSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("[LGAP] ❌ Cannot create target format")
            conn.cancel()
            lgapConnection = nil
            return
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("[LGAP] ❌ Cannot create audio converter (\(nativeFormat) → \(targetFormat))")
            conn.cancel()
            lgapConnection = nil
            return
        }
        lgapConverter = converter

        var packetCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = Self.lgapSampleRate / nativeFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0,
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)
            else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil, outputBuffer.frameLength > 0,
                  let int16Data = outputBuffer.int16ChannelData else { return }

            let byteCount = Int(outputBuffer.frameLength) * 2
            let pcmData = Data(bytes: int16Data[0], count: byteCount)
            self.sendLGAPFrame(pcmData, over: conn)

            packetCount += 1
            if packetCount == 1 {
                print("[LGAP] 📡 First packet sent: \(byteCount) bytes PCM")
            } else if packetCount % 50 == 0 {
                print("[LGAP] 📊 Packets sent: \(packetCount)")
            }
        }

        do {
            try engine.start()
            lgapEngine = engine
            print("[LGAP] 🎙️ AudioEngine started (native: \(nativeFormat.sampleRate)Hz → 16kHz)")
        } catch {
            print("[LGAP] ❌ AudioEngine start failed: \(error)")
            conn.cancel()
            lgapConnection = nil
        }
    }

    /// 發送一個 LGAP 封包：magic(4 LE) + payloadLen(4 LE) + PCM Int16 data
    private nonisolated func sendLGAPFrame(_ pcmData: Data, over conn: NWConnection) {

        var packet = Data(capacity: 8 + pcmData.count)
        var magic = Self.lgapMagic
        var length = UInt32(pcmData.count)
        withUnsafeBytes(of: &magic) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(pcmData)

        conn.send(content: packet, completion: .contentProcessed { _ in })
    }

    /// 停止 LGAP 串流
    private func stopLGAPStream() {
        lgapEngine?.inputNode.removeTap(onBus: 0)
        lgapEngine?.stop()
        lgapEngine = nil
        lgapConverter = nil

        lgapConnection?.cancel()
        lgapConnection = nil

        print("[LGAP] ⏹️ Stream stopped")
    }
}

// MARK: - AI 通訊模型

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: String          // "user" | "assistant" | "system"
    let content: String
    let timestamp: Date
    var isEscalation: Bool = false
}

struct EscalationState {
    let requestId: String
    var status: String       // "pending" | "queued" | "processing" | "done" | "failed"
    var queuePosition: Int = 0
    var finalDecision: String?
}

// MARK: - AI 聊天氣泡

private struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        let isUser = message.role == "user"
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: message.isEscalation
                              ? "exclamationmark.arrow.triangle.2.circlepath"
                              : "cpu")
                            .font(.caption2)
                            .foregroundColor(message.isEscalation ? NV.danger : NV.command)
                    }
                    Text(isUser ? L("你") : (message.isEscalation ? L("決策 AI") : L("現場 AI")))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser
                                ? NV.command.opacity(0.2)
                                : message.isEscalation
                                    ? NV.danger.opacity(0.1)
                                    : Color.gray.opacity(0.15))
                    .cornerRadius(12)

                Text(timeFmt.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
}

// MARK: - 前線 AI 通訊管理器
//
// 架構說明：
// - 僅呼叫單一後端 /chat（帶 session_id: "field_{deviceID}"、use_server_session: true）
// - 「雙 AI 決策」實際發生於後端：當本 session 與 HQ session 於 60 秒窗口內
//   都觸發 ESCALATE 訊號時，後端會自動呼叫 /escalate 並透過 TCP
//   escalation_trigger 訊息同時通知雙方 UI
// - 本類別透過 externalEscalationTrigger(payload:) 接收外部推送的觸發事件
//   （由 LinkGuardViewModel 訂閱 commandClient.onEscalationTrigger 轉發）

@MainActor
final class FieldAIChatManager: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var draft = ""
    @Published var isLoading = false
    @Published var activeEscalation: EscalationState?
    /// 本裝置最近一次 /chat 是否被後端偵測為 ESCALATE 訊號（尚在等待對側共識）
    @Published var pendingEscalationHint = false

    var serverHost = ""
    var senderName = ""

    /// 後端 session_id：前線裝置一律為 "field_{deviceID}"
    private var sessionId: String {
        let safe = senderName.replacingOccurrences(of: " ", with: "_")
        return safe.isEmpty ? "field_unknown" : "field_\(safe)"
    }

    // MARK: - 發送訊息

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""

        let userMsg = AIChatMessage(role: "user", content: trimmed, timestamp: Date())
        messages.append(userMsg)

        isLoading = true

        Task {
            let result = await callChat(message: trimmed)
            isLoading = false

            if !result.reply.isEmpty {
                let aiMsg = AIChatMessage(role: "assistant", content: result.reply, timestamp: Date())
                messages.append(aiMsg)
            } else {
                let errMsg = AIChatMessage(role: "system", content: L("AI 回覆失敗，請重試"), timestamp: Date())
                messages.append(errMsg)
            }

            // 後端若偵測到 ESCALATE 訊號：顯示「等待 HQ AI 共識」提示
            // 真正的上報觸發由後端 /chat 回傳 escalation.consensus_fired 或
            // TCP escalation_trigger 訊息驅動
            if result.escalateDetected && !result.consensusFired {
                pendingEscalationHint = true
                let sysMsg = AIChatMessage(
                    role: "system",
                    content: L("現場 AI 建議上報，等待 HQ AI 同步確認中…"),
                    timestamp: Date()
                )
                messages.append(sysMsg)

                // 90 秒後若仍未共識，清除提示
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 90_000_000_000)
                    await MainActor.run {
                        guard let self else { return }
                        if self.pendingEscalationHint && self.activeEscalation == nil {
                            self.pendingEscalationHint = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - 呼叫後端 /chat

    private struct ChatResult {
        let reply: String
        let escalateDetected: Bool
        let consensusFired: Bool
    }

    private func callChat(message: String) async -> ChatResult {
        let host = cleanHost(serverHost)
        guard !host.isEmpty, host != "localhost" else {
            return ChatResult(reply: "", escalateDetected: false, consensusFired: false)
        }

        let hostStr = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "http://\(hostStr):8001/chat") else {
            return ChatResult(reply: "", escalateDetected: false, consensusFired: false)
        }

        let systemPrompt = """
        你是 LinkGuard 前線現場 AI 助理，協助救援人員判斷傷患狀態、建議處置方式、評估現場風險。
        回覆精準簡短，使用正體中文；不足資訊時主動追問。
        上報規則：若你評估目前情況超出現場處理能力，需要指揮中心主模型或更多資源介入，
        請在回覆最後一行加上 [ESCALATE:YES] 標記。
        上報不會立即觸發主模型，需要 HQ 指揮官 AI 也做出相同判斷才會共識上報。
        若情況在現場可處理，不要加此標記。
        """

        let body: [String: Any] = [
            "message": message,
            "history": [],
            "system_prompt": systemPrompt,
            "session_id": sessionId,
            "use_server_session": true,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return ChatResult(reply: "", escalateDetected: false, consensusFired: false)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let reply = dataDict["reply"] as? String else {
                return ChatResult(reply: "", escalateDetected: false, consensusFired: false)
            }

            var escalateDetected = false
            var consensusFired = false
            if let esc = dataDict["escalation"] as? [String: Any] {
                escalateDetected = (esc["detected"] as? Bool) ?? false
                consensusFired = (esc["consensus_fired"] as? Bool) ?? false
            }

            return ChatResult(reply: reply, escalateDetected: escalateDetected, consensusFired: consensusFired)
        } catch {
            print("[FieldAIChat] error: \(error)")
            return ChatResult(reply: "", escalateDetected: false, consensusFired: false)
        }
    }

    // MARK: - 接收外部共識觸發（由 LinkGuardViewModel 透過 TCP 推送）

    /// 當後端雙 AI 共識成立後，TCP 會廣播 escalation_trigger
    /// LinkGuardViewModel 訂閱後轉呼叫此方法更新 UI
    func externalEscalationTrigger(requestId: String, hqSummary: String,
                                    fieldSummary: String, status: String) {
        pendingEscalationHint = false
        activeEscalation = EscalationState(
            requestId: requestId,
            status: status == "dispatched" ? "processing" : status
        )
        let msg = AIChatMessage(
            role: "system",
            content: L("需要上報主模型") + " — " + L("現場 AI 與 HQ AI 共識達成，已提交主模型決策"),
            timestamp: Date(),
            isEscalation: true
        )
        messages.append(msg)

        // 啟動輪詢以取得主模型回覆
        pollEscalationResult(requestId: requestId)
    }

    private func pollEscalationResult(requestId: String) {
        let host = cleanHost(serverHost)
        let hostStr = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "http://\(hostStr):8001/escalation/\(requestId)") else { return }

        Task {
            for _ in 0..<40 {  // 最多輪詢 40 次，每次 3 秒（合計 2 分鐘）
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard activeEscalation?.requestId == requestId else { return }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let status = dataDict["status"] as? String else {
                    continue
                }

                activeEscalation?.status = status
                if let pos = dataDict["queue_position"] as? Int {
                    activeEscalation?.queuePosition = pos
                }

                if status == "done" {
                    let finalDecision = dataDict["final_decision"] as? String ?? ""
                    activeEscalation?.finalDecision = finalDecision
                    let msg = AIChatMessage(
                        role: "assistant",
                        content: "【\(L("主模型決策回覆"))】\n\(finalDecision)",
                        timestamp: Date(),
                        isEscalation: true
                    )
                    messages.append(msg)

                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    activeEscalation = nil
                    return
                } else if status == "failed" {
                    let errDetail = dataDict["error"] as? String ?? L("未知錯誤")
                    let msg = AIChatMessage(
                        role: "system",
                        content: L("主模型處理失敗：%@，將使用現場 AI 的判斷", errDetail),
                        timestamp: Date(),
                        isEscalation: true
                    )
                    messages.append(msg)
                    activeEscalation = nil
                    return
                }
            }

            // 超時
            activeEscalation?.status = "timeout"
            let msg = AIChatMessage(
                role: "system",
                content: L("上報等待逾時，將使用現場 AI 的判斷繼續處理"),
                timestamp: Date()
            )
            messages.append(msg)
            activeEscalation = nil
        }
    }

    // MARK: - Helpers

    private func cleanHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pct = h.firstIndex(of: "%") {
            h = String(h[h.startIndex..<pct])
        }
        if h.hasPrefix("::ffff:") {
            h = String(h.dropFirst(7))
        }
        return h
    }
}
