import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit

@MainActor
final class HQNotificationCueManager: ObservableObject {
    static let shared = HQNotificationCueManager()

    enum Keys {
        static let statusUpdatesEnabled = "hq.notifications.statusUpdates.enabled"
        static let statusSoundEnabled = "hq.notifications.statusUpdates.soundEnabled"
        static let statusFlashEnabled = "hq.notifications.statusUpdates.flashEnabled"
    }

    @Published private(set) var flashToken = UUID()

    private var audioPlayer: AVAudioPlayer?
    private var lastCueAt = Date.distantPast
    private let minimumCueInterval: TimeInterval = 0.2
    private let soundResourceName = "f1_team_radio"
    private let soundResourceExtension = "mp3"

    private init() {}

    var statusUpdatesEnabled: Bool {
        boolValue(forKey: Keys.statusUpdatesEnabled, defaultValue: true)
    }

    var statusSoundEnabled: Bool {
        boolValue(forKey: Keys.statusSoundEnabled, defaultValue: true)
    }

    var statusFlashEnabled: Bool {
        boolValue(forKey: Keys.statusFlashEnabled, defaultValue: true)
    }

    func triggerStatusUpdateCue() {
        guard statusUpdatesEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCueAt) >= minimumCueInterval else { return }
        lastCueAt = now

        if statusSoundEnabled {
            playStatusSound()
        }
        if statusFlashEnabled {
            flashToken = UUID()
        }
    }

    func triggerFieldEventCue() {
        triggerStatusUpdateCue()
    }

    func previewStatusUpdateCue() {
        if statusSoundEnabled {
            playStatusSound()
        }
        if statusFlashEnabled {
            flashToken = UUID()
        }
    }

    func previewFieldEventCue() {
        previewStatusUpdateCue()
    }

    private func playStatusSound() {
        if audioPlayer == nil {
            audioPlayer = makeAudioPlayer()
        }
        guard let audioPlayer else {
            NSSound.beep()
            return
        }
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        }
        audioPlayer.currentTime = 0
        audioPlayer.prepareToPlay()
        audioPlayer.play()
    }

    private func makeAudioPlayer() -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: soundResourceName, withExtension: soundResourceExtension) else {
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            return player
        } catch {
            print("[NotificationCue] Failed to load sound: \(error)")
            return nil
        }
    }

    private func boolValue(forKey key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

struct HQNotificationFlashOverlay: View {
    @ObservedObject var manager: HQNotificationCueManager
    @State private var isVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Rectangle()
            .strokeBorder(NV.warning.opacity(isVisible ? 0.95 : 0), lineWidth: isVisible ? 7 : 3)
            .shadow(color: NV.warning.opacity(isVisible ? 0.75 : 0), radius: isVisible ? 24 : 0)
            .padding(5)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: isVisible)
            .onChange(of: manager.flashToken) { _, _ in
                pulse()
            }
            .onDisappear {
                hideTask?.cancel()
                hideTask = nil
            }
    }

    private func pulse() {
        hideTask?.cancel()
        isVisible = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                isVisible = false
            }
        }
    }
}

#endif