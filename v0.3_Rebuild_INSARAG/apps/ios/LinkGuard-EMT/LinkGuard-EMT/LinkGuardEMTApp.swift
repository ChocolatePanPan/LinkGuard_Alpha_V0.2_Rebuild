import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardEMTApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(
                appID: .emt,
                platform: .iPhone,
                deviceID: "IOS-EMT-LOCAL",
                displayName: "LinkGuard EMT"
            )
        }
    }
}