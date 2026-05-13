import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardEMTIPadApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .emtIPad,
                platform: .iPad,
                deviceID: "IPAD-EMT-LOCAL",
                displayName: "LinkGuard EMT iPad"
            )
        }
    }
}