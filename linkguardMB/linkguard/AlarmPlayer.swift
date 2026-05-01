import AVFoundation
import Foundation

/// Handles audio alarm playback for LinkGuard threat alerts.
class AlarmPlayer: NSObject {

    static let shared = AlarmPlayer()

    private var audioPlayer: AVAudioPlayer?
    private(set) var isPlaying: Bool = false

    override private init() {
        super.init()
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
#if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AlarmPlayer: Failed to configure audio session – \(error)")
        }
#endif
    }

    // MARK: - Playback

    /// Start playing an alarm sound. If a sound file is not found, a system beep is used.
    /// - Parameters:
    ///   - soundName: The name of the sound resource (without extension). Defaults to "alarm".
    ///   - fileExtension: The file extension. Defaults to "mp3".
    ///   - loops: Number of times to loop; pass -1 to loop indefinitely.
    func startAlarm(named soundName: String = "alarm",
                    fileExtension: String = "mp3",
                    loops: Int = -1) {
        guard !isPlaying else { return }

        if let url = Bundle.main.url(forResource: soundName, withExtension: fileExtension) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = loops
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                isPlaying = true
            } catch {
                print("AlarmPlayer: Failed to initialize audio player – \(error)")
                fallbackBeep()
            }
        } else {
            print("AlarmPlayer: Sound file '\(soundName).\(fileExtension)' not found in bundle.")
            fallbackBeep()
        }
    }

    /// Stop the currently playing alarm.
    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    // MARK: - Helpers

    private func fallbackBeep() {
#if os(macOS)
        NSSound.beep()
#endif
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate
extension AlarmPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        if let error = error {
            print("AlarmPlayer: Decode error – \(error)")
        }
    }
}
