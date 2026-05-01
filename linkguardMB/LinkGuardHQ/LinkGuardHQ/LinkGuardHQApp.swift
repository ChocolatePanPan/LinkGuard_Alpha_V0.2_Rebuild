import SwiftUI

@main
struct LinkGuardHQApp: App {
    @StateObject private var viewModel = HQViewModel()
    @StateObject private var l10n = L10n.shared
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            HQDashboardView(vm: viewModel)
                .onAppear {
                    // 只在 server 模式下啟動本地伺服器；
                    // peer 模式（iPad 預設）不啟動，僅連接 Mac HQ。
                    if viewModel.hqRole == .server {
                        viewModel.startServer()
                        #if os(macOS)
                        // 嵌入模式時自動啟動 Python 後端 sidecar
                        if viewModel.backendMode == .embedded {
                            viewModel.ensureMacLocalBackend()
                        }
                        #endif
                    }
                }
                .preferredColorScheme(colorScheme)
                .environment(\.locale, Locale(identifier: l10n.language))
                .tint(NV.green)
                .environmentObject(viewModel.udpAudioServer)
                .environmentObject(l10n)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
