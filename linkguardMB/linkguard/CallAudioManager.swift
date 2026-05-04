import Foundation
import Network
import AVFoundation
import Combine

final class CallAudioManager: ObservableObject {
    @Published var isSessionActive = false
    @Published var isTransmitting = false
    @Published var isReceiving = false
    @Published var isMuted = false
    @Published var connectionError: String?

    private var callID = ""
    private var serverHost = ""
    private var deviceID = ""

    private var sendConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.linkguard.call.audio", qos: .userInteractive)

    private var captureEngine: AVAudioEngine?
    private var captureConverter: AVAudioConverter?
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: false)!
    #if os(iOS)
    private var isUsingCallKitActivatedSession = false
    #endif

    private var sequence: UInt32 = 0

    private static let lgbdMagic: UInt32 = 0x4C474244
    private static let sampleRate: Double = 16000
    private static let hqUDPPort: UInt16 = 9001

    #if os(iOS)
    func configureForActivatedCallSession(_ session: AVAudioSession) {
        do {
            try configureCallAudioSession(session, activate: false)
            isUsingCallKitActivatedSession = true
            logCurrentRoute(session, prefix: "CallKit activated")
        } catch {
            connectionError = L("音訊初始化失敗")
            print("[CallAudio] CallKit audio session config error: \(error)")
        }
    }
    #endif

    func startSession(callID: String, serverHost: String, deviceID: String) {
        let cleanHost = Self.cleanHost(serverHost)
        guard !cleanHost.isEmpty, cleanHost != "localhost" else {
            connectionError = L("未連線 Mac HQ，無法通話")
            return
        }

        self.callID = callID
        self.serverHost = cleanHost
        self.deviceID = deviceID
        connectionError = nil
        isMuted = false
        isSessionActive = true

        #if os(iOS)
        if !isUsingCallKitActivatedSession {
            do {
                try configureCallAudioSession(AVAudioSession.sharedInstance(), activate: true)
            } catch {
                connectionError = L("音訊初始化失敗")
                print("[CallAudio] fallback audio session error: \(error)")
                return
            }
        }
        #endif
        startPlaybackEngine()
        ensureSendConnection(sendRegistrationWhenReady: true)
        startTransmitting()
    }

    func stopSession() {
        stopTransmitting()
        sendConnection?.cancel()
        sendConnection = nil
        stopPlaybackEngine()

        DispatchQueue.main.async {
            self.isSessionActive = false
            self.isReceiving = false
            self.isMuted = false
            self.connectionError = nil
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    func startTransmitting() {
        guard isSessionActive, !isTransmitting else { return }
        guard !serverHost.isEmpty else {
            connectionError = L("未連線 Mac HQ，無法通話")
            return
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission != .granted {
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startTransmitting()
                    } else {
                        self?.connectionError = L("需要麥克風權限，請至設定開啟")
                    }
                }
            }
            return
        }
        #endif

        ensureSendConnection(sendRegistrationWhenReady: false)
        guard let connection = sendConnection else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        #if os(iOS)
        try? inputNode.setVoiceProcessingEnabled(true)
        #endif
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: Self.sampleRate,
                                               channels: 1,
                                               interleaved: true),
              let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            connectionError = L("音訊格式初始化失敗")
            return
        }
        captureConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if self.isMuted { return }

            let ratio = Self.sampleRate / nativeFormat.sampleRate
            let frameCapacity = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio))
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error,
                  error == nil,
                  outputBuffer.frameLength > 0,
                  let channels = outputBuffer.int16ChannelData else { return }

            let pcmData = Data(bytes: channels[0], count: Int(outputBuffer.frameLength) * 2)
            self.sendPCMFrame(pcmData, over: connection)
        }

        do {
            try engine.start()
            captureEngine = engine
            DispatchQueue.main.async { self.isTransmitting = true }
        } catch {
            inputNode.removeTap(onBus: 0)
            connectionError = L("錄音啟動失敗")
        }
    }

    func stopTransmitting() {
        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine?.stop()
        captureEngine = nil
        captureConverter = nil
        DispatchQueue.main.async { self.isTransmitting = false }
    }

    private func ensureSendConnection(sendRegistrationWhenReady: Bool) {
        if sendConnection != nil { return }
        guard let port = NWEndpoint.Port(rawValue: Self.hqUDPPort) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(serverHost), port: port, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if sendRegistrationWhenReady {
                    self.sendRegistrationPacket(over: connection)
                }
                // 同一條 UDP socket 雙向使用：HQ 反向送回的中繼音訊會回到這裡
                self.receiveFromHQ(on: connection)
            case .failed(let error):
                DispatchQueue.main.async { self.connectionError = error.localizedDescription }
            default:
                break
            }
        }
        connection.start(queue: queue)
        sendConnection = connection
    }

    private func receiveFromHQ(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let packet = self.parseLGBDPacket(data), packet.deviceID != self.deviceID {
                self.playPCMChunk(packet.audioData)
                DispatchQueue.main.async { self.isReceiving = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.isReceiving = false
                }
            }
            if error == nil {
                self.receiveFromHQ(on: connection)
            }
        }
    }

    private func sendRegistrationPacket(over connection: NWConnection) {
        let silence = Data(repeating: 0, count: 320)
        sendPCMFrame(silence, over: connection)
    }

    private func sendPCMFrame(_ pcmData: Data, over connection: NWConnection) {
        var packet = Data()
        var magic = Self.lgbdMagic.bigEndian
        withUnsafeBytes(of: &magic) { packet.append(contentsOf: $0) }

        let idData = deviceID.data(using: .utf8) ?? Data()
        var idLength = UInt16(idData.count).bigEndian
        withUnsafeBytes(of: &idLength) { packet.append(contentsOf: $0) }
        packet.append(idData)

        sequence &+= 1
        var packetSequence = sequence.bigEndian
        withUnsafeBytes(of: &packetSequence) { packet.append(contentsOf: $0) }

        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        var timestamp = millis.bigEndian
        withUnsafeBytes(of: &timestamp) { packet.append(contentsOf: $0) }
        packet.append(pcmData)

        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private struct LGBDPacket {
        let deviceID: String
        let audioData: Data
    }

    private func parseLGBDPacket(_ data: Data) -> LGBDPacket? {
        guard data.count >= 18 else { return nil }
        let magic = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard magic == Self.lgbdMagic else { return nil }
        let idLength = data.subdata(in: 4..<6).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        let idStart = 6
        let idEnd = idStart + Int(idLength)
        let headerEnd = idEnd + 12
        guard data.count >= headerEnd else { return nil }
        guard let sender = String(data: data.subdata(in: idStart..<idEnd), encoding: .utf8) else { return nil }
        return LGBDPacket(deviceID: sender, audioData: data.subdata(in: headerEnd..<data.count))
    }

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
            print("[CallAudio] Playback engine error: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        playerNode?.stop()
        playbackEngine?.stop()
        playerNode = nil
        playbackEngine = nil
        #if os(iOS)
        let shouldDeactivate = !isUsingCallKitActivatedSession
        isUsingCallKitActivatedSession = false
        if shouldDeactivate {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    #if os(iOS)
    private func configureCallAudioSession(_ session: AVAudioSession, activate: Bool) throws {
        try session.setCategory(.playAndRecord,
                                mode: .voiceChat,
                                options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setPreferredSampleRate(Self.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        if activate {
            try session.setActive(true)
        }
        logCurrentRoute(session, prefix: activate ? "fallback active" : "configured")
    }

    private func logCurrentRoute(_ session: AVAudioSession, prefix: String) {
        let inputs = session.currentRoute.inputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        let outputs = session.currentRoute.outputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        print("[CallAudio] \(prefix) route input=\(inputs) output=\(outputs)")
    }
    #endif

    private func playPCMChunk(_ int16Data: Data) {
        guard let player = playerNode, let engine = playbackEngine else { return }
        if !engine.isRunning {
            try? engine.start()
            player.play()
        }
        let sampleCount = int16Data.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                            frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let floatData = buffer.floatChannelData?[0] else { return }
        int16Data.withUnsafeBytes { raw in
            let int16 = raw.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                floatData[index] = Float(Int16(littleEndian: int16[index])) / 32768.0
            }
        }
        player.scheduleBuffer(buffer)
    }

    private static func cleanHost(_ host: String) -> String {
        var clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let percent = clean.firstIndex(of: "%") {
            clean = String(clean[clean.startIndex..<percent])
        }
        if clean.hasPrefix("::ffff:") {
            clean = String(clean.dropFirst(7))
        }
        return clean
    }
}
