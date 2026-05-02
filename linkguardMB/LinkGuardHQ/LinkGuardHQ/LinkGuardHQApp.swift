import SwiftUI

@main
struct LinkGuardHQApp: App {
    @StateObject private var viewModel = HQViewModel()
    @StateObject private var l10n = L10n.shared
    #if os(macOS)
    @StateObject private var externalDashboardManager = HQExternalDashboardWindowManager()
    #endif
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.uiScale") private var uiScale: Double = 1.0

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark", "black": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            HQZoomContainer(scale: uiScale) {
                HQDashboardView(vm: viewModel)
                    .onAppear {
                        // 只在 server 模式下啟動本地伺服器；
                        // peer 模式（iPad 預設）不啟動，僅連接 Mac HQ。
                        if viewModel.hqRole == .server {
                            viewModel.startServer()
                        }
                        #if os(macOS)
                        externalDashboardManager.start(viewModel: viewModel, l10n: l10n, colorScheme: colorScheme)
                        #endif
                    }
                    #if os(macOS)
                    .onChange(of: appColorScheme) { _ in
                        externalDashboardManager.refresh(colorScheme: colorScheme)
                    }
                    .onChange(of: l10n.language) { _ in
                        externalDashboardManager.refresh(colorScheme: colorScheme)
                    }
                    #endif
                    .preferredColorScheme(colorScheme)
                    .environment(\.locale, Locale(identifier: l10n.language))
                    .tint(NV.green)
                    .environmentObject(viewModel.udpAudioServer)
                    .environmentObject(l10n)
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu(L("介面縮放")) {
                Button(L("放大")) { adjustUIScale(by: 0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button(L("縮小")) { adjustUIScale(by: -0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button(L("重設縮放")) { uiScale = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
        #endif
    }

    private func adjustUIScale(by delta: Double) {
        let rounded = ((uiScale + delta) * 10).rounded() / 10
        uiScale = min(max(rounded, 0.8), 1.4)
    }
}

private struct HQZoomContainer<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: () -> Content

    private var clampedScale: CGFloat {
        CGFloat(min(max(scale, 0.8), 1.4))
    }

    var body: some View {
        GeometryReader { proxy in
            content()
                .frame(width: proxy.size.width / clampedScale,
                       height: proxy.size.height / clampedScale,
                       alignment: .topLeading)
                .scaleEffect(clampedScale, anchor: .topLeading)
                .frame(width: proxy.size.width,
                       height: proxy.size.height,
                       alignment: .topLeading)
                .clipped()
        }
    }
}
