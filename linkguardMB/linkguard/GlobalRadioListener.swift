import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// =====================================================
//  Global Radio Listener — Plan v2 Phase B
//
//  目的：HQ 廣播電台音訊應在前線 App **任何位置都能聽到**
//       （含背景、鎖屏），而非只有 Radio Tab 開啟時才播放。
//
//  作法：
//   1. App 啟動時呼叫 GlobalRadioListener.shared.activate()。
//   2. AVAudioSession.playback + .mixWithOthers，確保
//      鎖屏 / 背景可繼續播放（需配合 Info.plist UIBackgroundModes audio）。
//   3. 監聽 audio interruption 事件，被打斷後自動重新啟用。
//   4. 實際的音訊串流播放仍由 LinkGuardViewModel.playRadioAudio
//      （onReportSummary 觸發），此處只負責「保持音訊管線常開」。
// =====================================================

final class GlobalRadioListener {
    static let shared = GlobalRadioListener()

    private(set) var isActive: Bool = false
    private var observersInstalled: Bool = false

    private init() {}

    /// 在 App 啟動時呼叫一次即可。重複呼叫會 no-op。
    func activate() {
        guard !isActive else { return }
        configureAudioSession()
        installObservers()
        isActive = true
        print("[GlobalRadio] ✅ Activated — background/lock-screen audio enabled")
    }

    /// 一般情況下不需呼叫；測試或下線時可主動關閉。
    func deactivate() {
        guard isActive else { return }
#if os(iOS)
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
#endif
        isActive = false
        print("[GlobalRadio] 🛑 Deactivated")
    }

    // MARK: - 私有

    private func configureAudioSession() {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback：背景/鎖屏可播放
            // .mixWithOthers：不會打斷其他音訊（地圖導航、警報音）
            // .duckOthers：HQ 廣播時稍微壓低其他音量
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("[GlobalRadio] ⚠️ AVAudioSession 設定失敗: \(error)")
        }
#endif
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
#if os(iOS)
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self,
                       selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self,
                       selector: #selector(handleAppForeground),
                       name: UIApplication.willEnterForegroundNotification,
                       object: nil)
#endif
    }

#if os(iOS)
    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            print("[GlobalRadio] ⏸️ interruption began (call/siri)")
        case .ended:
            // interruption 結束後自動恢復
            try? AVAudioSession.sharedInstance().setActive(true)
            print("[GlobalRadio] ▶️ interruption ended — resumed")
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // 耳機拔出 / 藍牙切換 → 重新確保 active，避免靜音
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    @objc private func handleAppForeground() {
        // 進入前景重新確認 session 狀態
        try? AVAudioSession.sharedInstance().setActive(true)
    }
#endif
}
