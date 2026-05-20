import Foundation
import Network
import AVFoundation

// MARK: - 即時音訊串流伺服器（Mac HQ, port 8005）
//
// 前線 iOS 裝置按住 PTT 時，AVAudioEngine 即時擷取麥克風 PCM Int16 16kHz mono，
// 透過 TCP 以 LGAP（LinkGuard Audio Protocol）小包傳送到 HQ。
// HQ 接收後即時轉 Float32 並用 AVAudioPlayerNode 播放。
//
// LGAP 封包格式（小端序）：
//   [4 bytes] magic: "LGAP" (0x4C474150)
//   [4 bytes] payloadLength: UInt32 (PCM Int16 位元組數)
//   [N bytes] payload: Int16 PCM samples, 16kHz mono, little-endian

final class AudioStreamServer: ObservableObject, @unchecked Sendable {
    @Published var isRunning = false
    @Published var isPlaying = false
    @Published var currentSender: String?
    @Published var packetCount = 0

    /// 音訊資料回呼（用於轉發到語音辨識管線）
    /// 參數: (pcmInt16Data, senderID)
    var onPCMDataReceived: ((Data, String) -> Void)?

    private var listener: NWListener?
    private let port: UInt16 = 8005
    private let queue = DispatchQueue(label: "hq.audio.stream", qos: .userInteractive)

    // 音訊播放引擎（隨伺服器啟動常駐，不等連線才建立）
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: false)!
    /// 追蹤活躍連線以便清理
    private var activeConnections: [NWConnection] = []

    private static let magic: UInt32 = 0x4C474150  // "LGAP"
    private static let headerSize = 8  // 4 magic + 4 length

    // MARK: - 啟動 / 停止

    @MainActor func start() {
        guard !isRunning, listener == nil else { return }

        // 預先啟動音訊播放引擎（不等連線，避免 race condition）
        startPlaybackEngine()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                print("[AudioStream] ❌ Invalid port: \(port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            print("[AudioStream] ❌ Listener create failed: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("[AudioStream] ✅ Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.isRunning = false
                    print("[AudioStream] ❌ Listener failed: \(error)")
                default:
                    break
                }
            }
        }
        listener?.start(queue: queue)
    }

    @MainActor func stop() {
        listener?.cancel()
        listener = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        stopPlaybackEngine()
        isRunning = false
        isPlaying = false
        currentSender = nil
        print("[AudioStream] Stopped")
    }

    // MARK: - 連線處理

    private func handleConnection(_ connection: NWConnection) {
        print("[AudioStream] 📡 New connection from \(connection.endpoint)")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[AudioStream] ✅ Connection ready from \(connection.endpoint)")
                DispatchQueue.main.async {
                    self?.activeConnections.append(connection)
                    self?.isPlaying = true
                    self?.currentSender = "前線裝置"
                    self?.packetCount = 0
                }
                // 開始接收
                let senderID = Self.extractSenderID(from: connection)
                let bufferBox = DataBox(Data(), senderID: senderID)
                self?.receiveNext(connection: connection, bufferBox: bufferBox)
            case .failed(let error):
                print("[AudioStream] ❌ Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                print("[AudioStream] Connection cancelled")
                self?.removeConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveNext(connection: NWConnection, bufferBox: DataBox) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                bufferBox.data.append(data)
                self.processBuffer(bufferBox)
            }

            if isComplete || error != nil {
                if let error {
                    print("[AudioStream] ⚠️ Receive error: \(error)")
                }
                self.removeConnection(connection)
                return
            }

            self.receiveNext(connection: connection, bufferBox: bufferBox)
        }
    }

    /// 從緩衝區解析 LGAP 封包
    private func processBuffer(_ box: DataBox) {
        while box.data.count >= Self.headerSize {
            // 讀取 magic
            let magic = box.data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            guard magic == Self.magic else {
                // 找不到 magic，丟棄 1 byte 重新對齊
                box.data.removeFirst(1)
                continue
            }

            // 讀取 payload 長度
            let payloadLen = Int(box.data.withUnsafeBytes {
                $0.load(fromByteOffset: 4, as: UInt32.self)
            })

            // 安全檢查：payload 不應超過 1MB
            guard payloadLen > 0, payloadLen < 1_048_576 else {
                print("[AudioStream] ⚠️ Invalid payload length: \(payloadLen), skipping")
                box.data.removeFirst(4)
                continue
            }

            let totalLen = Self.headerSize + payloadLen
            guard box.data.count >= totalLen else {
                break  // 資料不完整，等待更多
            }

            // 提取 payload（用 prefix/dropFirst 避免 index 問題）
            let packet = Data(box.data.prefix(totalLen))
            let payload = Data(packet.dropFirst(Self.headerSize))
            box.data.removeFirst(totalLen)

            // 播放
            playPCMChunk(payload)

            // 轉發到語音辨識管線
            onPCMDataReceived?(payload, box.senderID)

            // 計數（不頻繁更新 UI）
            DispatchQueue.main.async { [weak self] in
                self?.packetCount += 1
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeConnections.removeAll { $0 === connection }
            let count = self.packetCount
            print("[AudioStream] 📊 Connection ended. Total packets played: \(count)")
            if self.activeConnections.isEmpty {
                self.isPlaying = false
                self.currentSender = nil
            }
        }
    }

    // MARK: - 音訊播放引擎（常駐）

    private func startPlaybackEngine() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        // 明確設定音量（macOS 預設可能不是 1.0）
        player.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0

        do {
            try engine.start()
            player.play()
            audioEngine = engine
            playerNode = player
            let outFmt = engine.outputNode.outputFormat(forBus: 0)
            print("[AudioStream] ▶️ Playback engine pre-started")
            print("[AudioStream]    Player format: \(playbackFormat)")
            print("[AudioStream]    Output format: \(outFmt)")
            print("[AudioStream]    Output component available: \(engine.outputNode.audioUnit != nil)")
            print("[AudioStream]    Player volume: \(player.volume), Mixer volume: \(engine.mainMixerNode.outputVolume)")
        } catch {
            print("[AudioStream] ❌ Engine start failed: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        print("[AudioStream] ⏹️ Playback engine stopped")
    }

    /// 將 Int16 PCM 轉換為 Float32 並排入播放佇列
    private var chunksPlayed = 0
    private func playPCMChunk(_ int16Data: Data) {
        // 直接存取（playerNode/audioEngine 在 start() 時已建立，生命週期內不變）
        guard let player = playerNode, let engine = audioEngine else {
            print("[AudioStream] ⚠️ No player/engine, dropping chunk")
            return
        }
        if !engine.isRunning {
            // 嘗試重啟
            do {
                try engine.start()
                player.play()
                print("[AudioStream] 🔄 Engine restarted")
            } catch {
                print("[AudioStream] ❌ Engine restart failed: \(error)")
                return
            }
        }

        let sampleCount = int16Data.count / 2  // Int16 = 2 bytes per sample
        guard sampleCount > 0 else { return }

        chunksPlayed += 1
        if chunksPlayed == 1 {
            // 首個封包診斷
            let firstSamples = int16Data.withUnsafeBytes { ptr -> [Int16] in
                let buf = ptr.bindMemory(to: Int16.self)
                return Array(buf.prefix(min(5, sampleCount)))
            }
            print("[AudioStream] 🔊 First chunk: \(sampleCount) samples, first values: \(firstSamples)")
            print("[AudioStream]    Engine running: \(engine.isRunning), Player playing: \(player.isPlaying)")
        } else if chunksPlayed % 50 == 0 {
            print("[AudioStream] 📊 Chunks played: \(chunksPlayed), samples this: \(sampleCount)")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                            frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let floatData = buffer.floatChannelData?[0] else { return }
        int16Data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        player.scheduleBuffer(buffer)
    }

    /// 從連線端點提取發送者 ID
    private static func extractSenderID(from connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint {
            return "field-\(host)"
        }
        return "lgap-stream"
    }
}

// MARK: - Helper

/// 用於在 closure 中傳遞可變 Data
private class DataBox {
    var data: Data
    let senderID: String
    init(_ data: Data, senderID: String = "lgap-stream") {
        self.data = data
        self.senderID = senderID
    }
}
