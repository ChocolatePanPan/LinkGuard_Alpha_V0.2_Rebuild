import LinkGuardV03MacUI
import SwiftUI

@main
struct LinkGuardUCCApp: App {
    private let shellState: MacSystemUIState

    init() {
        do {
            self.shellState = try MacSystemUIFactory.makeState(
                appID: .ucc,
                deviceID: "MAC-UCC-LOCAL",
                displayName: "LinkGuard UCC Console"
            )
        } catch {
            fatalError("Unable to initialize LinkGuard-UCC: \(error)")
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
