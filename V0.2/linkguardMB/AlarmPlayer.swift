import AVFoundation
import Foundation

/// 緊報音播放器 — 模擬國家級地震警報的雙頻交替警報聲
final class AlarmPlayer {

    static let shared = AlarmPlayer()

    private var audioPlayer: AVAudioPlayer?
    private var isPlaying = false
    private let lock = NSLock()

    private init() {}

    /// 播放警報音（循環，即使靜音模式也會響）
    func playAlarm() {
        play(mode: .evacuation)
    }

    /// 播放 SOS 專用警報音（救護車節奏）
    func playSOSAlarm() {
        play(mode: .sos)
    }

    private enum AlarmMode {
        case evacuation
        case sos
    }

    private func play(mode: AlarmMode) {
        lock.lock()
        guard !isPlaying else { lock.unlock(); return }
        isPlaying = true
        lock.unlock()

        // 必須在主線程操作 audio
        let work = { [self] in
            #if os(iOS)
            // 設定 audio session：即使靜音開關打開也會播放
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[AlarmPlayer] Audio session 設定失敗: \(error)")
            }
            #endif

            let data = (mode == .sos) ? generateSOSAlarmWAV() : generateAlarmWAV()
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.prepareToPlay()
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0
                let success = audioPlayer?.play() ?? false
                print("[AlarmPlayer] play() = \(success), duration = \(audioPlayer?.duration ?? 0)")
            } catch {
                print("[AlarmPlayer] 播放失敗: \(error)")
                isPlaying = false
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }

    /// 停止警報音
    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        lock.lock()
        isPlaying = false
        lock.unlock()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - 產生國家級警報 WAV

    /// 模擬台灣國家級警報（PWS / CMAS）音效
    ///
    /// 真實國家警報使用 ANSI 標準的 Attention Signal：
    /// - 853Hz + 960Hz 雙音同時播放（和弦）
    /// - 1 秒響 → 0.5 秒靜音 的節奏循環
    /// - 總長 6 秒（4 個循環），無限 loop 播放
    private func generateAlarmWAV() -> Data {
        let sampleRate: Double = 44100
        let duration: Double = 6.0
        let totalSamples = Int(sampleRate * duration)

        // ANSI Attention Signal 雙音和弦
        let freq1: Double = 853
        let freq2: Double = 960

        // 節奏：1 秒響 + 0.5 秒靜音 = 1.5 秒一個循環
        let onDuration: Double = 1.0
        let cycleDuration: Double = 1.5

        // 淡入淡出時間（消除 click noise）
        let fadeDuration: Double = 0.008

        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            let posInCycle = t.truncatingRemainder(dividingBy: cycleDuration)

            // 靜音段
            guard posInCycle < onDuration else { continue }

            // 方波疊加 (強烈泛音、刺耳且大聲)
            let tone1 = sin(2.0 * .pi * freq1 * t) > 0 ? 0.9 : -0.9
            let tone2 = sin(2.0 * .pi * freq2 * t) > 0 ? 0.9 : -0.9
            var mixed = (tone1 + tone2) * 0.5

            // 淡入
            if posInCycle < fadeDuration {
                mixed *= posInCycle / fadeDuration
            }
            // 淡出
            let distToEnd = onDuration - posInCycle
            if distToEnd < fadeDuration {
                mixed *= distToEnd / fadeDuration
            }

            samples[i] = Int16(clamping: Int(mixed * Double(Int16.max - 1)))
        }

        return createWAV(samples: samples, sampleRate: Int(sampleRate))
    }

    /// SOS 專用雙音交替警報（715Hz / 956Hz）— 與 HQ Mac 統一
    private func generateSOSAlarmWAV() -> Data {
        let sampleRate: Double = 44100
        let duration: Double = 4.8
        let totalSamples = Int(sampleRate * duration)

        let lowFreq: Double = 715
        let highFreq: Double = 956
        let cycle: Double = 2.4

        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            let pos = t.truncatingRemainder(dividingBy: cycle)
            let halfCycle = cycle / 2
            let freq = pos < halfCycle ? lowFreq : highFreq
            let tone = sin(2.0 * .pi * freq * t) * 0.8
            samples[i] = Int16(clamping: Int(tone * Double(Int16.max - 1)))
        }

        return createWAV(samples: samples, sampleRate: Int(sampleRate))
    }

    /// 組裝 WAV 檔案格式
    private func createWAV(samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })  // chunk size
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })   // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        return data
    }
}
