import AVFoundation
import Combine
import Foundation
import SwiftUI

/// 語音輸入管理器 — 錄音 + 上傳轉錄
@MainActor
final class VoiceInputManager: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case uploading(progress: Double)
        case done(text: String)
        case error(String)
    }

    @Published var state: State = .idle

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice_input.m4a")
    }

    // MARK: - Recording

    func startRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            state = .error(L("音訊 Session 設定失敗: %@", error.localizedDescription))
            return
        }
        #endif

        // macOS: 檢查麥克風權限
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            state = .error(L("麥克風權限被拒絕，請至系統設定 > 隱私權 > 麥克風開啟權限"))
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.state = .error(L("麥克風權限被拒絕"))
                    }
                }
            }
            return
        case .authorized:
            break
        @unknown default:
            break
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            state = .recording
        } catch {
            state = .error(L("錄音啟動失敗: %@", error.localizedDescription))
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Upload & Transcribe

    /// 停止錄音並上傳至轉錄伺服器
    /// - Parameter serverHost: 伺服器位址，例如 "192.168.1.100"
    func stopAndTranscribe(serverHost: String) {
        stopRecording()

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            state = .error(L("錄音檔案不存在"))
            return
        }

        guard !serverHost.isEmpty, serverHost != "localhost" else {
            state = .error(L("尚未連線指揮中心，無法上傳轉錄"))
            return
        }

        state = .uploading(progress: 0)

        Task {
            do {
                let text = try await upload(to: serverHost)
                state = .done(text: text)
            } catch {
                state = .error(L("轉錄失敗: %@", error.localizedDescription))
            }
        }
    }

    func reset() {
        state = .idle
        try? FileManager.default.removeItem(at: recordingURL)
    }

    // MARK: - HTTP Multipart Upload

    private func upload(to serverHost: String) async throws -> String {
        let host = serverHost.contains(":") ? "[\(serverHost)]" : serverHost
        guard let url = URL(string: "http://\(host):8003/transcribe") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: recordingURL)
        var body = Data()

        // file field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        // Track upload progress via delegate
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse response — expect {"text": "transcribed content"}
        struct TranscribeResponse: Decodable {
            let text: String
        }

        let decoded = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        try? FileManager.default.removeItem(at: recordingURL)
        return decoded.text
    }
}
