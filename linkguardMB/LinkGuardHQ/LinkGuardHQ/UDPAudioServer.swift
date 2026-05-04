import Network
import Speech
import AVFoundation
import WhisperKit

// MARK: - Mac HQ UDP 音訊伺服器（port 9001）
//
// 整合雙重語音辨識：Apple Speech（即時） + WhisperKit（精確）
//
// 前線裝置 PTT 按住 → UDP LGBD 封包串流到 HQ:9001
// 第一層：Apple Speech 即時辨識（灰色字幕，低延遲）
// 第二層：靜音 ≥ 1 秒 → WhisperKit 精確辨識覆蓋（白色確定結果）
// 同時中繼音訊到所有其他 peer（port 9002）

final class UDPAudioServer: ObservableObject, @unchecked Sendable {

    // MARK: - Published 屬性

    @Published var isRunning = false
    @Published var activeBroadcaster: String? = nil
    @Published var connectedClientCount = 0
    @Published var isLocalPlaybackEnabled = true
    @Published var playbackVolume: Double = 1.0

    /// 雙重辨識結果（key = deviceID）
    @Published var liveTranscriptions: [String: String] = [:]    // Apple Speech 即時
    @Published var finalTranscriptions: [String: String] = [:]   // WhisperKit 精確
    @Published var transcriptionStates: [String: TranscriptionState] = [:]

    enum TranscriptionState: Equatable {
        case idle
        case listening   // Apple Speech 進行中（顯示灰色即時字幕）
        case processing  // WhisperKit 處理中（顯示 spinner）
        case done        // WhisperKit 完成（顯示白色確定結果）
    }

    // MARK: - 私有屬性

    private let queue = DispatchQueue(label: "udp.audio.server", qos: .userInitiated)
    private let magic: UInt32 = 0x4C474244  // "LGBD"
    private let port: NWEndpoint.Port = 9001

    private var listener: NWListener?
    private var clientConnections: [String: NWConnection] = [:]
    private var inboundPacketCount: UInt64 = 0
    private var audioBuffers: [String: Data] = [:]
    private var lastPacketTime: [String: Date] = [:]
    private let silenceThreshold: TimeInterval = 2.0

    // WhisperKit（精確辨識）— 公開供 HQSpeechServer 共用
    private(set) var whisperKit: WhisperKit?
    private(set) var whisperReady = false
    private var isLoadingWhisperKit = false

    // Apple Speech（即時辨識）
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequests: [String: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var recognitionTasks: [String: SFSpeechRecognitionTask] = [:]
    private let audioEngine = AVAudioEngine()

    // 本地播放（16 kHz mono Int16 PCM -> Float32）
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: false)!

    private var silenceTimer: Timer?

    // MARK: - 外部音訊輸入（LGAP TCP 串流轉發）

    /// 接收外部音訊（如 AudioStreamServer 的 LGAP TCP 串流）並啟動語音辨識
    func feedAudioForRecognition(audioData: Data, deviceID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastPacketTime[deviceID] = Date()
            self.audioBuffers[deviceID, default: Data()].append(audioData)
            self.feedToAppleSpeech(audioData: audioData, deviceID: deviceID)
            DispatchQueue.main.async {
                self.activeBroadcaster = deviceID
                self.transcriptionStates[deviceID] = .listening
            }
        }
    }

    // MARK: - 初始化 Apple Speech / WhisperKit

    func initialize() async {
        prepareAppleSpeechIfNeeded()
        _ = await initializeWhisperKitIfNeeded()
    }

    private func prepareAppleSpeechIfNeeded() {
        guard speechRecognizer == nil else { return }

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))

        // 申請語音辨識權限；不載入 WhisperKit 重模型，避免 HQ 待機耗 CPU。
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("[UDPAudioServer] ✅ Speech 權限已授權")
            case .denied:
                print("[UDPAudioServer] ❌ Speech 權限被拒絕")
            case .restricted:
                print("[UDPAudioServer] ⚠️ Speech 權限受限")
            case .notDetermined:
                print("[UDPAudioServer] ℹ️ Speech 權限未決定")
            @unknown default:
                print("[UDPAudioServer] Speech 權限: \(status.rawValue)")
            }
        }
    }

    @discardableResult
    func initializeWhisperKitIfNeeded() async -> Bool {
        guard !whisperReady else { return true }
        guard shouldUseNativeWhisperKit else { return false }
        guard !isLoadingWhisperKit else { return false }

        isLoadingWhisperKit = true
        defer { isLoadingWhisperKit = false }

        prepareAppleSpeechIfNeeded()

        // 初始化 WhisperKit — 優先嘗試 large-v3，失敗則降級 base。
        for model in ["large-v3", "base"] {
            do {
                print("[UDPAudioServer] 正在載入 WhisperKit 模型: \(model) ...")
                whisperKit = try await WhisperKit(
                    model: model,
                    verbose: false,
                    logLevel: .none
                )
                whisperReady = true
                print("[UDPAudioServer] ✅ WhisperKit 載入完成 (模型: \(model))")
                break
            } catch {
                print("[UDPAudioServer] ⚠️ WhisperKit \(model) 載入失敗: \(error)")
                whisperKit = nil
                whisperReady = false
            }
        }

        if !whisperReady {
            print("[UDPAudioServer] ℹ️ WhisperKit 未就緒，僅使用 Apple Speech")
        }
        return whisperReady
    }

    private var shouldUseNativeWhisperKit: Bool {
        (UserDefaults.standard.string(forKey: "voice.engine") ?? "whisperkit") == "whisperkit"
    }

    // MARK: - 啟動 UDP 監聽

    func startListening() {
        guard listener == nil else { return }
        prepareAppleSpeechIfNeeded()

        let params = NWParameters.udp
        params.allowFastOpen = true
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: port)
        } catch {
            print("[UDPAudioServer] listener 建立失敗: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("[UDPAudioServer] ✅ UDP 伺服器啟動於 port 9001（雙重辨識就緒）")
                case .failed(let error):
                    self?.isRunning = false
                    print("[UDPAudioServer] ❌ 失敗: \(error)")
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
        startPlaybackEngine()
        startSilenceDetection()
    }

    func stopListening() {
        stop()
    }

    // MARK: - 新連線處理

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveData(on: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - 接收封包

    private func receiveData(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65535
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error {
                print("[UDPAudioServer] UDP receive error: \(error.localizedDescription)")
                return
            }

            if let data, !data.isEmpty, let packet = self.parsePacket(data) {
                self.inboundPacketCount &+= 1
                if self.inboundPacketCount % 50 == 0 {
                    print("[UDPAudioServer] ↔️ LGBD packets=\(self.inboundPacketCount) from=\(packet.deviceID) bytes=\(packet.audioData.count) clients=\(self.clientConnections.count) complete=\(isComplete)")
                }

                // 記錄 inbound NWConnection（中繼時需要反向送回這條雙向 socket）
                if self.clientConnections[packet.deviceID] !== connection {
                    self.clientConnections[packet.deviceID] = connection
                    DispatchQueue.main.async {
                        self.connectedClientCount = self.clientConnections.count
                    }
                }

                self.lastPacketTime[packet.deviceID] = Date()
                self.audioBuffers[packet.deviceID, default: Data()]
                    .append(packet.audioData)

                // 中繼到所有其他 field 裝置的 port 9002
                self.relayToFieldDevices(data: data, excludeDeviceID: packet.deviceID)

                // 第一層：Apple Speech 即時辨識
                self.feedToAppleSpeech(
                    audioData: packet.audioData,
                    deviceID: packet.deviceID
                )

                self.playLocallyIfNeeded(audioData: packet.audioData, deviceID: packet.deviceID)

                // 更新狀態為 listening
                DispatchQueue.main.async {
                    self.transcriptionStates[packet.deviceID] = .listening
                }
            }

            // UDP datagram 多半每包都是 complete；仍要持續 receive 下一包。
            self.receiveData(on: connection)
        }
    }

    // MARK: - 解析 LGBD 封包

    private struct LGBDPacket {
        let deviceID: String
        let sequence: UInt32
        let timestamp: UInt64
        let audioData: Data
    }

    private func parsePacket(_ data: Data) -> LGBDPacket? {
        // 最小封包: magic(4) + idLen(2) + seq(4) + timestamp(8) = 18
        guard data.count >= 18 else { return nil }

        guard let magic = Self.readBigEndianUInt32(from: data, at: 0) else { return nil }
        guard magic == self.magic else { return nil }

        guard let idLen = Self.readBigEndianUInt16(from: data, at: 4) else { return nil }
        let minLen = 6 + Int(idLen) + 12  // header(6) + deviceID(idLen) + sequence(4) + timestamp(8)
        guard data.count >= minLen else { return nil }

        let idData = data.subdata(in: 6..<(6 + Int(idLen)))
        guard let deviceID = String(data: idData, encoding: .utf8) else { return nil }

        let seqOffset = 6 + Int(idLen)
        guard let sequence = Self.readBigEndianUInt32(from: data, at: seqOffset),
              let timestamp = Self.readBigEndianUInt64(from: data, at: seqOffset + 4) else { return nil }

        let audioData = data.subdata(in: (seqOffset + 12)..<data.count)

        return LGBDPacket(
            deviceID: deviceID,
            sequence: sequence,
            timestamp: timestamp,
            audioData: audioData
        )
    }

    private static func readBigEndianUInt16(from data: Data, at offset: Int) -> UInt16? {
        guard hasBytes(data, at: offset, count: 2) else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            let byte0 = UInt16(rawBuffer.load(fromByteOffset: offset, as: UInt8.self))
            let byte1 = UInt16(rawBuffer.load(fromByteOffset: offset + 1, as: UInt8.self))
            return (byte0 << 8) | byte1
        }
    }

    private static func readBigEndianUInt32(from data: Data, at offset: Int) -> UInt32? {
        guard hasBytes(data, at: offset, count: 4) else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            let byte0 = UInt32(rawBuffer.load(fromByteOffset: offset, as: UInt8.self))
            let byte1 = UInt32(rawBuffer.load(fromByteOffset: offset + 1, as: UInt8.self))
            let byte2 = UInt32(rawBuffer.load(fromByteOffset: offset + 2, as: UInt8.self))
            let byte3 = UInt32(rawBuffer.load(fromByteOffset: offset + 3, as: UInt8.self))
            return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
        }
    }

    private static func readBigEndianUInt64(from data: Data, at offset: Int) -> UInt64? {
        guard hasBytes(data, at: offset, count: 8) else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            var value: UInt64 = 0
            for index in 0..<8 {
                let byte = UInt64(rawBuffer.load(fromByteOffset: offset + index, as: UInt8.self))
                value = (value << 8) | byte
            }
            return value
        }
    }

    private static func hasBytes(_ data: Data, at offset: Int, count byteCount: Int) -> Bool {
        guard offset >= 0, byteCount >= 0, byteCount <= data.count else { return false }
        return offset <= data.count - byteCount
    }

    // MARK: - 中繼音訊到 field 裝置 (port 9002)

    private func extractSenderIP(from connection: NWConnection) -> String? {
        if let remote = connection.currentPath?.remoteEndpoint,
           case .hostPort(let host, _) = remote {
            return normalizeIP("\(host)")
        }
        if case .hostPort(let host, _) = connection.endpoint {
            return normalizeIP("\(host)")
        }
        return nil
    }

    private func normalizeIP(_ raw: String) -> String {
        raw.components(separatedBy: "%").first ?? raw
    }

    /// 將音訊原封反向送回每一個其他已連線 client。
    /// 直接用 inbound NWConnection 雙向送，避免依賴 field 的 9002 listener
    /// （iOS 對 UDP NWListener 的 inbound 接收在 CallKit 切換期間不穩，
    ///  且來源 IP 反查容易遇到 IPv6 link-local / NAT 問題）。
    private func relayToFieldDevices(data: Data, excludeDeviceID: String) {
        for (deviceID, conn) in clientConnections {
            guard deviceID != excludeDeviceID else { continue }
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    print("[UDPAudioServer] relay to \(deviceID) failed: \(error.localizedDescription)")
                }
            })
        }
    }

    // MARK: - 本地播放

    private func startPlaybackEngine() {
        guard playbackEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        do {
            try engine.start()
            player.play()
            playbackEngine = engine
            playerNode = player
        } catch {
            print("[UDPAudioServer] 本地播放啟動失敗: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        playerNode?.stop()
        playbackEngine?.stop()
        playerNode = nil
        playbackEngine = nil
    }

    private func playLocallyIfNeeded(audioData: Data, deviceID: String) {
        guard isLocalPlaybackEnabled else { return }
        guard deviceID != "HQ" else { return }
        guard audioData.count >= 2 else { return }

        startPlaybackEngine()

        let frameCount = audioData.count / MemoryLayout<Int16>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channel = buffer.floatChannelData?[0] else { return }

        audioData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<frameCount {
                channel[index] = Float(samples[index]) / Float(Int16.max)
            }
        }

        playerNode?.volume = Float(playbackVolume)
        playerNode?.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - 第一層：Apple Speech 即時辨識

    private func feedToAppleSpeech(audioData: Data, deviceID: String) {
        if recognitionRequests[deviceID] == nil {
            startAppleSpeechSession(deviceID: deviceID)
        }

        guard let request = recognitionRequests[deviceID] else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(audioData.count / 2)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount
        audioData.withUnsafeBytes { ptr in
            buffer.int16ChannelData?[0]
                .update(from: ptr.bindMemory(to: Int16.self).baseAddress!,
                        count: Int(frameCount))
        }

        request.append(buffer)
    }

    private func startAppleSpeechSession(deviceID: String) {
        guard let recognizer = speechRecognizer,
              recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // 強制離線辨識
        request.contextualStrings = [
            "傷患", "傷者", "受困者", "救護車", "救護員", "擔架",
            "呼吸", "脈搏", "心跳", "血壓", "意識", "出血",
            "紅區", "黃區", "綠區", "黑區", "檢傷", "分類",
            "SOS", "收到", "回報", "請求支援", "增援",
            "現場", "指揮中心", "前線", "撤離", "疏散",
        ]

        recognitionRequests[deviceID] = request

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.liveTranscriptions[deviceID] = text
                }
            }

            if let error = error {
                print("[UDPAudioServer] ⚠️ Speech recognition error for \(deviceID): \(error.localizedDescription)")
            }

            if error != nil || result?.isFinal == true {
                self.queue.async {
                    self.recognitionRequests.removeValue(forKey: deviceID)
                    self.recognitionTasks.removeValue(forKey: deviceID)
                }
            }
        }

        recognitionTasks[deviceID] = task
    }

    // MARK: - 靜音偵測 → 觸發 WhisperKit

    private func startSilenceDetection() {
        guard silenceTimer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            self?.checkSilence()
        }
        timer.tolerance = 0.25
        silenceTimer = timer
    }

    private func checkSilence() {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            for (deviceID, lastTime) in self.lastPacketTime {
                let silence = now.timeIntervalSince(lastTime)
                if silence >= self.silenceThreshold {
                    if let buffer = self.audioBuffers[deviceID], !buffer.isEmpty {
                        // 結束 Apple Speech session
                        self.recognitionRequests[deviceID]?.endAudio()

                        // 更新狀態為 processing
                        DispatchQueue.main.async { [weak self] in
                            self?.transcriptionStates[deviceID] = .processing
                            self?.activeBroadcaster = nil
                        }

                        // 第二層：WhisperKit 精確辨識
                        let capturedBuffer = buffer
                        let capturedID = deviceID
                        Task { [weak self] in
                            await self?.transcribeWithWhisperKit(
                                audioData: capturedBuffer,
                                deviceID: capturedID
                            )
                        }

                        self.audioBuffers[deviceID] = Data()
                    }
                    self.lastPacketTime.removeValue(forKey: deviceID)
                }
            }
        }
    }

    // MARK: - 第二層：WhisperKit 精確辨識

    private func transcribeWithWhisperKit(
        audioData: Data,
        deviceID: String
    ) async {
        if !whisperReady {
            _ = await initializeWhisperKitIfNeeded()
        }

        guard whisperReady, let whisperKit = whisperKit else {
            // WhisperKit 不可用，保留 Apple Speech 結果
            DispatchQueue.main.async { [weak self] in
                self?.transcriptionStates[deviceID] = .done
            }
            return
        }

        // 把 PCM data 存成暫存 WAV 檔
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(deviceID)_\(Date().timeIntervalSince1970).wav")

        do {
            try writeWAV(pcmData: audioData, to: tempURL)
        } catch {
            print("[WhisperKit] WAV 寫入失敗: \(error)")
            return
        }

        // 呼叫 WhisperKit 辨識
        do {
            var options = DecodingOptions(
                language: "zh",
                temperature: 0.0,
                usePrefillPrompt: true,
                suppressBlank: false
            )
            // 繁體中文救災領域提示詞：引導模型輸出繁體字並熟悉專業術語
            if let tokenizer = whisperKit.tokenizer {
                let prompt = "以下是災害現場無線電通訊的繁體中文語音辨識，包含傷患狀態、救援指令與現場回報。"
                options.promptTokens = tokenizer.encode(text: prompt).map { Int($0) }
            }
            let results = try await whisperKit.transcribe(
                audioPath: tempURL.path,
                decodeOptions: options
            )

            let finalText = results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            DispatchQueue.main.async { [weak self] in
                // WhisperKit 結果覆蓋 Apple Speech
                self?.finalTranscriptions[deviceID] = finalText
                self?.liveTranscriptions[deviceID] = finalText
                self?.transcriptionStates[deviceID] = .done

                // 推播到 HQViewModel
                NotificationCenter.default.post(
                    name: .whisperTranscriptionReceived,
                    object: nil,
                    userInfo: [
                        "text": finalText,
                        "device_id": deviceID,
                        "source": "whisperkit"
                    ]
                )
            }

            // 清除暫存檔
            try? FileManager.default.removeItem(at: tempURL)

        } catch {
            print("[WhisperKit] 辨識失敗: \(error)")
            // 失敗時保留 Apple Speech 結果
            DispatchQueue.main.async { [weak self] in
                self?.transcriptionStates[deviceID] = .done
            }
        }
    }

    // MARK: - PCM 轉 WAV 輔助函式

    private func writeWAV(pcmData: Data, to url: URL) throws {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let dataSize = UInt32(pcmData.count)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8

        var header = Data()

        func append(_ value: UInt32) {
            var v = value.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }
        func append(_ value: UInt16) {
            var v = value.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }

        header.append("RIFF".data(using: .ascii)!)
        append(36 + dataSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        append(UInt32(16))        // chunk size
        append(UInt16(1))         // PCM format
        append(channels)
        append(sampleRate)
        append(byteRate)
        append(channels * bitsPerSample / 8)  // block align
        append(bitsPerSample)
        header.append("data".data(using: .ascii)!)
        append(dataSize)

        var wav = header
        wav.append(pcmData)
        try wav.write(to: url)
    }

    // MARK: - 清理資源

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        listener?.cancel()
        listener = nil
        clientConnections.values.forEach { $0.cancel() }
        clientConnections.removeAll()
        recognitionRequests.values.forEach { $0.endAudio() }
        recognitionRequests.removeAll()
        recognitionTasks.values.forEach { $0.cancel() }
        recognitionTasks.removeAll()
        stopPlaybackEngine()
        audioBuffers.removeAll()
        lastPacketTime.removeAll()
        if Thread.isMainThread {
            self.isRunning = false
            self.activeBroadcaster = nil
            self.connectedClientCount = 0
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
                self?.activeBroadcaster = nil
                self?.connectedClientCount = 0
            }
        }
    }

    deinit {
        silenceTimer?.invalidate()
        listener?.cancel()
    }
}
