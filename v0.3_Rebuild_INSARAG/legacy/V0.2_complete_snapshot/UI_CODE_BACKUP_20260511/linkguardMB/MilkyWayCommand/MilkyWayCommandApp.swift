import SwiftUI

@main
struct MilkyWayCommandApp: App {
    @StateObject private var viewModel = MilkyWayCommandViewModel()

    var body: some Scene {
        WindowGroup {
            MilkyWayRootTabView(vm: viewModel)
        }
    }
}
