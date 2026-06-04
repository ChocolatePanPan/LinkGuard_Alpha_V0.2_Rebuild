import LinkGuardV03Core
import LinkGuardV03FieldUI
import SwiftUI

@main
struct LinkGuardIPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            FieldAppShellView(unifiedIPhoneDisplayName: "LinkGuard iPhone")
        }
    }
}
