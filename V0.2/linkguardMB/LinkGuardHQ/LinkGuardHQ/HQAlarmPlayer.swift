import Foundation
import AVFoundation

/// Mac HQ 專用警報播放器
/// - SOS 使用救護車節奏音
/// - 與一般命令/撤離警報分離
final class HQAlarmPlayer {

    static let shared = HQAlarmPlayer()

    private var audioPlayer: AVAudioPlayer?
    private var isPlaying = false
    private let lock = NSLock()

    private init() {}

    func playSOSAlarm() {
        lock.lock()
        guard !isPlaying else { lock.unlock(); return }
        isPlaying = true
        lock.unlock()

        let data = generateSOSAlarmWAV()
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 1.0
            _ = audioPlayer?.play()
        } catch {
            print("[HQAlarmPlayer] 播放 SOS 警報失敗: \(error)")
            isPlaying = false
        }
    }

    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        lock.lock()
        isPlaying = false
        lock.unlock()
    }

    /// SOS 專用雙音交替警報（715Hz / 956Hz）
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

    private func createWAV(samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        return data
    }
}
