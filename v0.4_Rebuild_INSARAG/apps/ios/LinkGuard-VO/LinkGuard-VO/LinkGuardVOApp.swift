import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardVOApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .volunteer,
                platform: .iPhone,
                deviceID: "IOS-VO-LOCAL",
                displayName: "LinkGuard VO"
            )
        }
    }
}