import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardTLApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .teamLeader,
                platform: .iPhone,
                deviceID: "IOS-TL-LOCAL",
                displayName: "LinkGuard TL"
            )
        }
    }
}