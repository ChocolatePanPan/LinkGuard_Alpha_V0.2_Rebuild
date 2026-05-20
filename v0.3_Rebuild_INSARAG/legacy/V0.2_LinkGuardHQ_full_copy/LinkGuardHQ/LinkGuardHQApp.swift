import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct LinkGuardHQApp: App {
    @StateObject private var viewModel = HQViewModel()
    @StateObject private var l10n = L10n.shared
    #if os(macOS)
    @StateObject private var externalDashboardManager = HQExternalDashboardWindowManager()
    @StateObject private var notificationCueManager = HQNotificationCueManager.shared
    @StateObject private var spacebarPTT = HQSpacebarPTTMonitor()
    #endif
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.uiScale") private var uiScale: Double = 1.0
    @AppStorage("hq.externalDisplayEnabled") private var externalDisplayEnabled: Bool = true

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
                    externalDashboardManager.setEnabled(externalDisplayEnabled)
                    spacebarPTT.attach(viewModel: viewModel)
                    #endif
                }
                #if os(macOS)
                .onChange(of: appColorScheme) { _, _ in
                    externalDashboardManager.refresh(colorScheme: colorScheme)
                }
                .onChange(of: l10n.language) { _, _ in
                    externalDashboardManager.refresh(colorScheme: colorScheme)
                }
                .onChange(of: externalDisplayEnabled) { _, newVal in
                    externalDashboardManager.setEnabled(newVal)
                }
                #endif
                .preferredColorScheme(colorScheme)
                .task(id: viewModel.hqRole) {
                    await Task.yield()
                    guard viewModel.hqRole == .server else { return }
                    viewModel.startServer()
                }
                .environment(\.locale, Locale(identifier: l10n.language))
                .tint(NV.green)
                .environmentObject(viewModel.udpAudioServer)
                .environmentObject(l10n)
            } // HQZoomContainer
            #if os(macOS)
            .overlay {
                HQNotificationFlashOverlay(manager: notificationCueManager)
            }
            #endif
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

#if os(macOS)
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
#endif

#if os(macOS)
/// 全域空白鍵 PTT 監聽器：
/// - 任意頁面按住 Space → 觸發 HQ 廣播（startHQPushToTalk）
/// - 放開 Space → 結束（stopHQPushToTalk）
/// - 若目前 firstResponder 是 NSText / NSTextView（使用者正在輸入文字），
///   則放行讓鍵盤事件正常進入文字框、不觸發 PTT。
@MainActor
final class HQSpacebarPTTMonitor: ObservableObject {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private weak var viewModel: HQViewModel?
    private var pttHeld = false
    private static let spaceKeyCode: UInt16 = 49

    func attach(viewModel: HQViewModel) {
        self.viewModel = viewModel
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == Self.spaceKeyCode else { return event }
            if Self.isTextEditingFocus() { return event }
            // 自動重複的 keyDown 直接吞掉避免重複呼叫
            if event.isARepeat {
                return nil
            }
            if !self.pttHeld {
                self.pttHeld = true
                self.viewModel?.startHQPushToTalk()
            }
            return nil   // 攔截，不再進入 SwiftUI 元件
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == Self.spaceKeyCode else { return event }
            if Self.isTextEditingFocus() {
                // 若使用者剛從文字框離開、但仍按住空白鍵，保險地確保不卡住
                if self.pttHeld {
                    self.pttHeld = false
                    self.viewModel?.stopHQPushToTalk()
                }
                return event
            }
            if self.pttHeld {
                self.pttHeld = false
                self.viewModel?.stopHQPushToTalk()
            }
            return nil
        }
    }

    deinit {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
    }

    private static func isTextEditingFocus() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSText || responder is NSTextView { return true }
        // SwiftUI TextField 內部通常是 NSTextView 的子類別，上述判斷已涵蓋
        return false
    }
}
#endif
