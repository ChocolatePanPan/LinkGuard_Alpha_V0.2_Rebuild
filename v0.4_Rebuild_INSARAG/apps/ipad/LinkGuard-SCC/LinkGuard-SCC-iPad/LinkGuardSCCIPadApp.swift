import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct LinkGuardSCCIPadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @StateObject private var l10n = L10n.shared

    init() {
        GlobalRadioListener.shared.activate()
    }

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .preferredColorScheme(colorScheme)
            .environment(\.locale, Locale(identifier: l10n.language))
            .environmentObject(l10n)
            .tint(NV.green)
            .onChange(of: scenePhase) { _, newPhase in
                AppBackgroundKeepAlive.shared.handleScenePhase(newPhase)
            }
        }
    }
}

final class AppBackgroundKeepAlive {
    static let shared = AppBackgroundKeepAlive()

    #if canImport(UIKit)
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    private init() {}

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            beginBackgroundTask()
        case .active:
            endBackgroundTask()
        default:
            break
        }
    }

    private func beginBackgroundTask() {
        #if canImport(UIKit)
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "LinkGuardRealtimeKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        print("[AppBackground] keep-alive started, remaining=\(UIApplication.shared.backgroundTimeRemaining)")
        #endif
    }

    private func endBackgroundTask() {
        #if canImport(UIKit)
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
        print("[AppBackground] keep-alive ended")
        #endif
    }
}
