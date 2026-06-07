import LinkGuardV03MacUI
import SwiftUI

@main
struct LinkGuardSCCApp: App {
    private let shellState: MacSystemUIState

    init() {
        do {
            self.shellState = try MacSystemUIFactory.makeState(
                appID: .scc,
                deviceID: "MAC-SCC-LOCAL",
                displayName: "LinkGuard SCC Console"
            )
        } catch {
            fatalError("Unable to initialize LinkGuard-SCC: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MacCommandConsoleView(state: shellState)
                .frame(minWidth: 1120, minHeight: 720)
        }
        Settings {
            MacSystemSettingsView(settingsInfo: shellState.settingsInfo)
                .frame(width: 520, height: 360)
        }
    }
}
