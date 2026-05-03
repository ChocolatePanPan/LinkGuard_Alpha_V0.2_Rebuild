import Foundation
import Network
import AVFoundation

final class HQCallAudioManager: ObservableObject {
    @Published var isSessionActive = false
    @Published var isTransmitting = false
    @Published var isMuted = false
    @Published var connectionError: String?

    private var callID = ""
    private var deviceID = "HQ"
    private var sendConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.linkguard.hq.call.audio", qos: .userInteractive)

    private var captureEngine: AVAudioEngine?
    private var captureConverter: AVAudioConverter?
    private var sequence: UInt32 = 0

    private static let lgbdMagic: UInt32 = 0x4C474244
    private static let sampleRate: Double = 16000
    private static let hqUDPPort: UInt16 = 9001

    func startSession(callID: String, deviceID: String = "HQ") {
        self.callID = callID
        self.deviceID = deviceID
        connectionError = nil
        isMuted = false
        isSessionActive = true
        ensureSendConnection(sendRegistrationWhenReady: true)
        startTransmitting()
    }

    func stopSession() {
        stopTransmitting()
        sendConnection?.cancel()
        sendConnection = nil
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.isMuted = false
            self.connectionError = nil
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func startTransmitting() {
        guard isSessionActive, !isTransmitting else { return }
        ensureSendConnection(sendRegistrationWhenReady: false)
        guard let connection = sendConnection else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
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
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if sendRegistrationWhenReady {
                    self.sendRegistrationPacket(over: connection)
                }
            case .failed(let error):
                DispatchQueue.main.async { self.connectionError = error.localizedDescription }
            default:
                break
            }
        }
        connection.start(queue: queue)
        sendConnection = connection
    }

    private func sendRegistrationPacket(over connection: NWConnection) {
        sendPCMFrame(Data(repeating: 0, count: 320), over: connection)
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
}
