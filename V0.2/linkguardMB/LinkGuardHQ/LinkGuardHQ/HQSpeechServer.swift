import Foundation
import Network
import Speech
import AVFoundation
import Combine
import WhisperKit

// MARK: - Mac HQ 語音辨識 HTTP 伺服器

/// 在 HQ Mac 上啟動 HTTP 伺服器（port 8003），接收前線音訊上傳
/// 優先使用 WhisperKit 辨識（中文精確），Apple Speech 備援
final class HQSpeechServer: ObservableObject, @unchecked Sendable {
    @Published var isRunning = false
    @Published var processedCount = 0
    @Published var lastTranscription = ""
    @Published var lastError: String?

    private var listener: NWListener?
    private let port: UInt16 = 8003
    private let queue = DispatchQueue(label: "hq.speech.server", qos: .userInitiated)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))

    /// 共享 WhisperKit 引擎（由 HQViewModel 注入，與 UDPAudioServer 共用）
    var whisperKit: WhisperKit?
    var whisperReady: Bool { whisperKit != nil }

    /// 持久化音檔儲存目錄
    private lazy var audioDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("LinkGuardData/audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 辨識完成後的回呼（用於轉發到後台 + 廣播）
    var onTranscriptionComplete: ((SpeechResult) -> Void)?

    /// 音訊檔案儲存完成後立即回呼（用於本地播放，不等轉錄）
    var onAudioFileReady: ((URL, String) -> Void)?

    /// 後台橋接器（會報轉發到 Windows）
    weak var backendBridge: HQBackendBridge?

    struct SpeechResult {
        let reportId: String
        let senderName: String
        let transcription: String
        let duration: Double
        let locationLat: Double
        let locationLon: Double
        let locationDesc: String
        let patientsSnapshot: String
        let weatherSnapshot: String
        let sourceType: RadioSourceType
    }

    // MARK: - 啟動/停止

    @MainActor func start() {
        guard !isRunning, listener == nil else { return }

        // 請求語音辨識權限
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                if status != .authorized {
                    self.lastError = "語音辨識權限未授權 (\(status.rawValue))"
                    print("[SpeechServer] 權限被拒絕: \(status.rawValue)")
                }
            }
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                lastError = "無效的 port: \(port)"
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            lastError = "伺服器啟動失敗: \(error.localizedDescription)"
            print("[SpeechServer] Listener 建立失敗: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .global())
            self?.receiveHTTPRequest(on: conn)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                    print("[SpeechServer] HTTP 伺服器啟動於 port \(self?.port ?? 0)")
                case .failed(let err):
                    self?.isRunning = false
                    self?.lastError = "伺服器錯誤: \(err.localizedDescription)"
                    print("[SpeechServer] 失敗: \(err)")
                case .cancelled:
                    self?.isRunning = false
                default: break
                }
            }
        }

        listener?.start(queue: queue)
    }

    @MainActor func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - 處理連線

    private func receiveHTTPRequest(on conn: NWConnection) {
        accumulateHTTP(conn: conn, accumulated: Data(), startTime: Date())
    }

    /// 根據 Content-Length 持續讀取直到收完整個 HTTP body（附帶 30 秒超時）
    private func accumulateHTTP(conn: NWConnection, accumulated: Data, startTime: Date) {
        // 30 秒超時保護
        if Date().timeIntervalSince(startTime) > 30 {
            print("[SpeechServer] ❌ Accumulation timeout after 30s, received \(accumulated.count) bytes")
            conn.cancel()
            return
        }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 2 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }

            var all = accumulated
            if let data {
                all.append(data)
                print("[SpeechServer] 📥 Received chunk \(data.count)B, total \(all.count)B")
            }

            if let error {
                print("[SpeechServer] ❌ Receive error: \(error)")
                conn.cancel()
                return
            }

            if isComplete || self.isHTTPBodyComplete(all) {
                print("[SpeechServer] ✅ HTTP request complete: \(all.count) bytes (isComplete=\(isComplete))")
                Task { @MainActor in
                    self.processHTTPRequest(data: all, conn: conn)
                }
            } else {
                self.accumulateHTTP(conn: conn, accumulated: all, startTime: startTime)
            }
        }
    }

    /// 檢查 HTTP body 是否已根據 Content-Length 收完
    private func isHTTPBodyComplete(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEndRange = data.range(of: separator) else { return false }
        let bodyStart = headerEndRange.upperBound

        // headers 只包含純文字，安全轉換
        guard let headerStr = String(data: data[data.startIndex..<headerEndRange.lowerBound], encoding: .utf8) else {
            return true
        }
        for line in headerStr.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valStr = String(line.dropFirst("content-length:".count)).trimmingCharacters(in: .whitespaces)
                if let contentLength = Int(valStr) {
                    let received = data.count - bodyStart
                    print("[SpeechServer] Content-Length=\(contentLength), received body=\(received)")
                    return received >= contentLength
                }
            }
        }
        return true
    }

    // MARK: - HTTP 解析

    private func processHTTPRequest(data: Data, conn: NWConnection) {
        // 在原始 bytes 中找 \r\n\r\n，只將 header 部分轉為字串（避免 binary body 破壞 UTF-8 解碼）
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEndRange = data.range(of: separator) else {
            print("[SpeechServer] ❌ No header end found in \(data.count) bytes")
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Invalid request"])
            return
        }
        guard let headerStr = String(data: data[data.startIndex..<headerEndRange.lowerBound], encoding: .utf8) else {
            print("[SpeechServer] ❌ Header UTF-8 decode failed")
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Invalid headers"])
            return
        }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "No request line"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Bad request"])
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])
        print("[SpeechServer] 📨 \(method) \(path) (\(data.count) bytes)")

        if method == "POST" && path == "/report" {
            handleReportUpload(data: data, conn: conn)
        } else if method == "POST" && path == "/transcribe" {
            handleTranscribe(data: data, conn: conn)
        } else if method == "GET" && path.hasPrefix("/audio/") {
            let reportId = String(path.dropFirst("/audio/".count))
            handleAudioDownload(reportId: reportId, conn: conn)
        } else if method == "GET" && path == "/health" {
            sendHTTPResponse(conn: conn, status: 200, body: [
                "status": "ok",
                "engine": "apple_speech",
                "processed": processedCount
            ])
        } else {
            sendHTTPResponse(conn: conn, status: 404, body: ["error": "Not found: \(path)"])
        }
    }

    // MARK: - /report 端點（接收會報 + 辨識 + 轉發）

    private func handleReportUpload(data: Data, conn: NWConnection) {
        // 解析 multipart/form-data
        guard let parsed = parseMultipart(data: data) else {
            print("[SpeechServer] ❌ parseMultipart failed for \(data.count) bytes")
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "無法解析 multipart 資料 (\(data.count) bytes)"])
            return
        }

        let senderName = parsed.fields["sender_name"] ?? parsed.fields["device_id"] ?? "unknown"
        let locationLat = Double(parsed.fields["location_lat"] ?? "0") ?? 0
        let locationLon = Double(parsed.fields["location_lon"] ?? "0") ?? 0
        let locationDesc = parsed.fields["location_desc"] ?? ""
        let patientsSnapshot = parsed.fields["patients_snapshot"] ?? "[]"
        let weatherSnapshot = parsed.fields["weather_snapshot"] ?? "{}"
        let sourceType: RadioSourceType = parsed.fields["source_type"] == "briefing" ? .briefing : .live

        guard let audioData = parsed.fileData, !audioData.isEmpty else {
            print("[SpeechServer] ❌ No audio data in multipart. Fields: \(parsed.fields.keys.joined(separator: ", "))")
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "缺少音訊檔案 (fields: \(parsed.fields.keys.joined(separator: ",")))"])
            return
        }
        print("[SpeechServer] 🎤 Report from \(senderName), audio=\(audioData.count) bytes")

        // 產生 report ID
        let reportId = generateReportId()

        // 根據上傳檔名偵測音訊格式（支援 wav / m4a）
        let uploadExt = (parsed.fileName as NSString?)?.pathExtension.lowercased() ?? "m4a"
        let audioExt = ["wav", "m4a", "mp4", "caf"].contains(uploadExt) ? uploadExt : "m4a"

        // 持久化音檔到 ~/Documents/LinkGuardData/audio/
        let audioFileURL = audioDir.appendingPathComponent("\(reportId).\(audioExt)")
        do {
            try audioData.write(to: audioFileURL)
        } catch {
            sendHTTPResponse(conn: conn, status: 500, body: ["error": "音訊儲存失敗"])
            return
        }
        cleanOldAudioFiles()

        // 立即通知 ViewModel 播放音訊（不等轉錄）
        self.onAudioFileReady?(audioFileURL, senderName)

        // 立即回應前線（不等待轉錄完成，避免 iOS 端卡住）
        sendHTTPResponse(conn: conn, status: 200, body: [
            "report_id": reportId,
            "status": "accepted",
            "engine": "apple_speech"
        ])
        print("[SpeechServer] ✅ 已接收 [\(reportId)] \(senderName), \(audioData.count / 1024)KB")

        // 背景執行語音辨識 + 廣播（不阻塞 HTTP 回應）
        Task { @MainActor in
            let transcription = await self.transcribeAudioWithTimeout(url: audioFileURL)
            let duration = self.getAudioDuration(url: audioFileURL)

            self.processedCount += 1
            self.lastTranscription = transcription

            let result = SpeechResult(
                reportId: reportId,
                senderName: senderName,
                transcription: transcription,
                duration: duration,
                locationLat: locationLat,
                locationLon: locationLon,
                locationDesc: locationDesc,
                patientsSnapshot: patientsSnapshot,
                weatherSnapshot: weatherSnapshot,
                sourceType: sourceType
            )

            // 回呼（HQViewModel 會記錄結果 + 廣播給前線）
            self.onTranscriptionComplete?(result)

            print("[SpeechServer] 辨識完成 [\(reportId)] \(senderName): \(transcription.prefix(60))...")
        }
    }

    // MARK: - GET /audio/{reportId} 端點（音訊下載）

    private func handleAudioDownload(reportId: String, conn: NWConnection) {
        // 防止路徑穿越
        let sanitized = reportId.replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "")

        // 嘗試多種副檔名（支援 wav / m4a）
        var fileURL: URL?
        var contentType = "audio/mp4"
        var ext = "m4a"
        for tryExt in ["wav", "m4a", "caf", "mp4"] {
            let url = audioDir.appendingPathComponent("\(sanitized).\(tryExt)")
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
                ext = tryExt
                contentType = tryExt == "wav" ? "audio/wav" : "audio/mp4"
                break
            }
        }

        guard let url = fileURL, let fileData = try? Data(contentsOf: url) else {
            sendHTTPResponse(conn: conn, status: 404, body: ["error": "Audio not found: \(sanitized)"])
            return
        }
        sendBinaryResponse(conn: conn, data: fileData, contentType: contentType,
                           fileName: "\(sanitized).\(ext)")
        print("[SpeechServer] 📥 音檔下載: \(sanitized).\(ext) (\(fileData.count / 1024)KB)")
    }

    /// 清理超過 24 小時的舊音檔，最多保留 200 筆
    private func cleanOldAudioFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: audioDir,
                                                       includingPropertiesForKeys: [.creationDateKey],
                                                       options: .skipsHiddenFiles) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var remaining: [(URL, Date)] = []
        for f in files {
            if let attrs = try? f.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate {
                if created < cutoff {
                    try? fm.removeItem(at: f)
                } else {
                    remaining.append((f, created))
                }
            }
        }
        // 超過 200 筆時刪除最舊的
        if remaining.count > 200 {
            let sorted = remaining.sorted { $0.1 < $1.1 }
            for (url, _) in sorted.prefix(remaining.count - 200) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - /transcribe 端點（純語音辨識）

    private func handleTranscribe(data: Data, conn: NWConnection) {
        guard let parsed = parseMultipart(data: data) else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "無法解析 multipart 資料"])
            return
        }

        let senderId = parsed.fields["sender_id"] ?? "unknown"
        guard let audioData = parsed.fileData, !audioData.isEmpty else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "缺少音訊檔案"])
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe_\(UUID().uuidString).m4a")
        do { try audioData.write(to: tempURL) } catch {
            sendHTTPResponse(conn: conn, status: 500, body: ["error": "音訊儲存失敗"])
            return
        }

        Task { @MainActor in
            let transcription = await self.transcribeAudio(url: tempURL)
            let duration = self.getAudioDuration(url: tempURL)
            try? FileManager.default.removeItem(at: tempURL)

            self.processedCount += 1

            self.sendHTTPResponse(conn: conn, status: 200, body: [
                "text": transcription,
                "language": "zh",
                "duration": duration
            ])

            print("[SpeechServer] 轉錄 [\(senderId)]: \(transcription.prefix(60))...")
        }
    }

    // MARK: - HQ 本地直接餵入錄音（HQ PTT）
    //
    // HQ 自己的麥克風錄完一段 PCM Int16 16kHz mono，直接呼叫此函式即可走完
    // 與遠端 /report 上傳完全相同的管線：寫 WAV → 觸發 onTranscriptionComplete
    // （由 HQViewModel 建立 HQRadioReport + broadcastReportSummary 給所有前線）。
    // 與遠端 upload 路徑唯一差別：不觸發 onAudioFileReady 以避免 HQ 自己的喇叭
    // 立即回放自己剛說過的話造成嘯叫。
    @MainActor
    @discardableResult
    func ingestLocalRecording(pcmInt16: Data,
                              senderName: String,
                              locationDesc: String = "",
                              sourceType: RadioSourceType = .live) -> String? {
        guard !pcmInt16.isEmpty else { return nil }

        let reportId = generateReportId()
        let audioFileURL = audioDir.appendingPathComponent("\(reportId).wav")
        do {
            try writeWAV(pcmData: pcmInt16, to: audioFileURL)
        } catch {
            print("[SpeechServer] ❌ HQ PTT WAV 寫入失敗: \(error)")
            return nil
        }
        cleanOldAudioFiles()

        Task { @MainActor in
            let transcription = await self.transcribeAudioWithTimeout(url: audioFileURL)
            let duration = self.getAudioDuration(url: audioFileURL)
            self.processedCount += 1
            self.lastTranscription = transcription

            let result = SpeechResult(
                reportId: reportId,
                senderName: senderName,
                transcription: transcription,
                duration: duration,
                locationLat: 0,
                locationLon: 0,
                locationDesc: locationDesc,
                patientsSnapshot: "[]",
                weatherSnapshot: "{}",
                sourceType: sourceType
            )
            self.onTranscriptionComplete?(result)
            print("[SpeechServer] HQ PTT 辨識完成 [\(reportId)] \(senderName): \(transcription.prefix(60))...")
        }
        return reportId
    }

    // MARK: - Apple Speech 語音辨識

    /// 帶有 60 秒超時的語音辨識（避免在音訊損壞時永久掛起）
    private func transcribeAudioWithTimeout(url: URL) async -> String {
        return await withTaskGroup(of: String.self) { group in
            group.addTask {
                await self.transcribeAudio(url: url)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                return L("[辨識超時]")
            }
            let result = await group.next() ?? "[辨識失敗]"
            group.cancelAll()
            return result
        }
    }

    private func transcribeAudio(url: URL) async -> String {
        // 檢查音檔時長：太短的音檔辨識不出任何內容
        let duration = getAudioDuration(url: url)
        if duration < 0.8 {
            print("[SpeechServer] ⚠️ 音檔太短 (\(String(format: "%.1f", duration))s)，跳過辨識")
            return L("[錄音過短，請至少說 1 秒]")
        }

        // 優先使用 WhisperKit（中文辨識更精確）
        if let result = await transcribeWithWhisperKit(url: url) {
            return result
        }
        print("[SpeechServer] ⚠️ WhisperKit 不可用或回空白 (whisperKit=\(whisperKit != nil ? "已載入" : "未載入"))，使用 Apple Speech")

        // 備援：Apple SFSpeechRecognizer
        return await transcribeWithAppleSpeech(url: url)
    }

    /// WhisperKit 辨識（需要 WAV 或可直接讀取的路徑）
    private func transcribeWithWhisperKit(url: URL) async -> String? {
        guard let whisperKit else { return nil }

        do {
            // 若上傳格式非 WAV，先轉換為 WAV
            let wavURL: URL
            let needsCleanup: Bool
            if url.pathExtension.lowercased() == "wav" {
                wavURL = url
                needsCleanup = false
            } else {
                wavURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("whisper_\(UUID().uuidString).wav")
                do {
                    try await convertToWAV(source: url, destination: wavURL)
                } catch {
                    print("[SpeechServer] 音訊轉 WAV 失敗: \(error)")
                    return nil
                }
                needsCleanup = true
            }

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
                audioPath: wavURL.path,
                decodeOptions: options
            )

            if needsCleanup { try? FileManager.default.removeItem(at: wavURL) }

            let text = results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            guard !text.isEmpty else {
                print("[SpeechServer] WhisperKit 回傳空白，降級 Apple Speech")
                return nil
            }

            print("[SpeechServer] ✅ WhisperKit 辨識: \(text.prefix(60))")
            return text

        } catch {
            print("[SpeechServer] WhisperKit 辨識失敗: \(error), 降級 Apple Speech")
            return nil
        }
    }

    /// 將 m4a/caf 等格式轉換為 16kHz mono WAV（WhisperKit 要求）
    private func convertToWAV(source: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw NSError(domain: "HQSpeech", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法讀取音訊檔"])
        }

        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "HQSpeech", code: -2, userInfo: [NSLocalizedDescriptionKey: "無音訊軌"])
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var pcmData = Data()
        while let buffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            let len = CMBlockBufferGetDataLength(blockBuffer)
            var chunk = Data(count: len)
            chunk.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: len, destination: ptr.baseAddress!)
            }
            pcmData.append(chunk)
        }

        try writeWAV(pcmData: pcmData, to: destination)
    }

    /// PCM → WAV 檔案
    private func writeWAV(pcmData: Data, to url: URL) throws {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let dataSize = UInt32(pcmData.count)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8

        var header = Data()
        func appendU32(_ v: UInt32) { var val = v.littleEndian; header.append(contentsOf: withUnsafeBytes(of: &val) { Array($0) }) }
        func appendU16(_ v: UInt16) { var val = v.littleEndian; header.append(contentsOf: withUnsafeBytes(of: &val) { Array($0) }) }

        header.append("RIFF".data(using: .ascii)!)
        appendU32(36 + dataSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        appendU32(16)
        appendU16(1)          // PCM
        appendU16(channels)
        appendU32(sampleRate)
        appendU32(byteRate)
        appendU16(channels * bitsPerSample / 8)
        appendU16(bitsPerSample)
        header.append("data".data(using: .ascii)!)
        appendU32(dataSize)

        var wav = header
        wav.append(pcmData)
        try wav.write(to: url)
    }

    /// Apple Speech 備援辨識（先嘗試離線，失敗再試線上）
    private func transcribeWithAppleSpeech(url: URL) async -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[SpeechServer] SFSpeechRecognizer 不可用")
            return L("[語音辨識不可用]")
        }

        // 優先離線辨識：避免 error 1107 浪費時間
        if #available(macOS 13, iOS 16, *), recognizer.supportsOnDeviceRecognition {
            let offlineResult = await appleSpeechRecognize(url: url, recognizer: recognizer, forceOnDevice: true)
            if !offlineResult.hasPrefix("[辨識失敗") && !offlineResult.hasPrefix("[辨識超時") {
                return offlineResult
            }
            print("[SpeechServer] 離線辨識失敗，嘗試線上辨識")
        }

        // 備援：嘗試線上辨識
        return await appleSpeechRecognize(url: url, recognizer: recognizer, forceOnDevice: false)
    }

    private func appleSpeechRecognize(url: URL, recognizer: SFSpeechRecognizer, forceOnDevice: Bool) async -> String {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.contextualStrings = [
            "傷患", "傷者", "受困者", "救護車", "救護員", "擔架",
            "呼吸", "脈搏", "心跳", "血壓", "意識", "出血",
            "紅區", "黃區", "綠區", "黑區", "檢傷", "分類",
            "SOS", "收到", "回報", "請求支援", "增援",
            "現場", "指揮中心", "前線", "撤離", "疏散",
        ]

        if #available(macOS 13, iOS 16, *), forceOnDevice {
            request.requiresOnDeviceRecognition = true
        }

        return await withTaskGroup(of: String.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    var didResume = false
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        guard !didResume else { return }
                        if let error {
                            didResume = true
                            let mode = forceOnDevice ? "離線" : "線上"
                            print("[SpeechServer] Apple Speech \(mode)辨識錯誤: \(error.localizedDescription)")
                            continuation.resume(returning: "[辨識失敗: \(error.localizedDescription)]")
                            return
                        }
                        if let result, result.isFinal {
                            didResume = true
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        }
                    }
                    // 保持 task 引用避免被釋放
                    _ = task
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return L("[辨識超時]")
            }
            let result = await group.next() ?? "[辨識失敗]"
            group.cancelAll()
            return result
        }
    }

    private func getAudioDuration(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    // MARK: - Multipart 解析（簡易版）

    struct MultipartData {
        var fields: [String: String] = [:]
        var fileData: Data?
        var fileName: String?
    }

    private func parseMultipart(data: Data) -> MultipartData? {
        // 尋找 boundary
        guard let headerEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            print("[SpeechServer] ❌ parseMultipart: no header end found in \(data.count) bytes")
            return nil
        }
        let headerStr = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""

        // 從 Content-Type header 提取 boundary
        var boundary = ""
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().contains("content-type:") && line.lowercased().contains("boundary=") {
                // 支援大小寫不同的 boundary=
                if let range = line.range(of: "boundary=", options: .caseInsensitive) {
                    boundary = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    // 移除可能的引號
                    if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                        boundary = String(boundary.dropFirst().dropLast())
                    }
                }
            }
        }
        guard !boundary.isEmpty else {
            print("[SpeechServer] ❌ parseMultipart: no boundary found in headers")
            print("[SpeechServer] Headers: \(headerStr.prefix(500))")
            return nil
        }
        print("[SpeechServer] 📦 parseMultipart: boundary=\(boundary), body starts at \(headerEnd.upperBound), total \(data.count) bytes")

        let bodyData = data[headerEnd.upperBound...]
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let parts = splitData(bodyData, separator: boundaryData)
        print("[SpeechServer] 📦 parseMultipart: found \(parts.count) parts")

        var result = MultipartData()

        for (i, part) in parts.enumerated() {
            guard part.count > 4 else { continue }
            guard let partHeaderEnd = part.range(of: "\r\n\r\n".data(using: .utf8)!) else { continue }
            let partHeader = String(data: part[part.startIndex..<partHeaderEnd.lowerBound], encoding: .utf8) ?? ""
            var partBody = part[partHeaderEnd.upperBound...]

            // 去掉尾部 \r\n
            if partBody.count >= 2 && partBody.suffix(2) == "\r\n".data(using: .utf8)! {
                partBody = partBody.dropLast(2)
            }

            // 解析 Content-Disposition
            if partHeader.contains("filename=") {
                // 檔案欄位
                result.fileData = Data(partBody)
                if let fnMatch = partHeader.range(of: "filename=\"") {
                    let afterQuote = partHeader[fnMatch.upperBound...]
                    if let endQuote = afterQuote.firstIndex(of: "\"") {
                        result.fileName = String(afterQuote[..<endQuote])
                    }
                }
                print("[SpeechServer] 📦 Part \(i): file=\(result.fileName ?? "?"), \(partBody.count) bytes")
            } else if let nameMatch = partHeader.range(of: "name=\"") {
                // 文字欄位
                let afterQuote = partHeader[nameMatch.upperBound...]
                if let endQuote = afterQuote.firstIndex(of: "\"") {
                    let fieldName = String(afterQuote[..<endQuote])
                    let fieldValue = String(data: partBody, encoding: .utf8) ?? ""
                    result.fields[fieldName] = fieldValue
                    print("[SpeechServer] 📦 Part \(i): \(fieldName)=\(fieldValue.prefix(30))")
                }
            }
        }

        print("[SpeechServer] 📦 parseMultipart result: \(result.fields.count) fields, fileData=\(result.fileData?.count ?? 0) bytes")
        return result
    }

    private func splitData(_ data: Data.SubSequence, separator: Data) -> [Data] {
        var result: [Data] = []
        var searchRange = data.startIndex..<data.endIndex

        while let range = data.range(of: separator, in: searchRange) {
            let chunk = data[searchRange.lowerBound..<range.lowerBound]
            if !chunk.isEmpty { result.append(Data(chunk)) }
            searchRange = range.upperBound..<data.endIndex
        }

        let remaining = data[searchRange]
        if remaining.count > 4 { // 忽略 "--\r\n" 結尾
            result.append(Data(remaining))
        }

        return result
    }

    // MARK: - HTTP 回應

    private func sendHTTPResponse(conn: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? "{}".data(using: .utf8)!
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(jsonData.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(jsonData)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - Report ID 生成

    private var reportCounter = 0

    private func generateReportId() -> String {
        reportCounter += 1
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        return "RPT-\(dateFormatter.string(from: Date()))-\(String(format: "%03d", reportCounter))"
    }

    // MARK: - 取得本機 IP

    func getLocalIP() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }

    // MARK: - Binary HTTP 回應（音檔下載用）

    private func sendBinaryResponse(conn: NWConnection, data: Data, contentType: String, fileName: String) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(data.count)",
            "Content-Disposition: inline; filename=\"\(fileName)\"",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(data)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
