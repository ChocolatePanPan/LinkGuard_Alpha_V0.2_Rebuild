import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardTEApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .teamMember,
                platform: .iPhone,
                deviceID: "IOS-TE-LOCAL",
                displayName: "LinkGuard TE",
                defaultIdentityCode: "TE-01"
            )
        }
    }
}
