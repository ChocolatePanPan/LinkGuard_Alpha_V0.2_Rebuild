import SwiftUI

@main
struct linkguardApp: App {

    @StateObject private var commandEngine = CommandEngine.shared

    init() {
        NotificationManager.shared.requestAuthorization { granted, error in
            if let error {
                print("linkguardApp: Notification permission error – \(error)")
            } else {
                print("linkguardApp: Notification permission granted = \(granted)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(commandEngine)
        }
#if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LinkGuard") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
#endif
    }
}
