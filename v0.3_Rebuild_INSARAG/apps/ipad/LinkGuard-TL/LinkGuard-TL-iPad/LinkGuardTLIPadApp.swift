import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardTLIPadApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .teamLeaderIPad,
                platform: .iPad,
                deviceID: "IPAD-TL-LOCAL",
                displayName: "LinkGuard TL iPad"
            )
        }
    }
}