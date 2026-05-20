import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardSCCIPadApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .sccIPad,
                platform: .iPad,
                deviceID: "IPAD-SCC-LOCAL",
                displayName: "LinkGuard SCC iPad"
            )
        }
    }
}