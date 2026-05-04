import SwiftUI

@main
struct MilkyWayCommandApp: App {
    @StateObject private var viewModel = MilkyWayCommandViewModel()

    var body: some Scene {
        WindowGroup {
            MilkyWayCommandCenterView(vm: viewModel)
                .preferredColorScheme(.dark)
                .tint(MWTheme.green)
        }
    }
}
