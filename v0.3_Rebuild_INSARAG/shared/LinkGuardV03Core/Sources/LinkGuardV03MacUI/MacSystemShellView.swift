import LinkGuardV03Core
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct MacSystemShellView: View {
    @State private var macState: MacSystemUIState
    @StateObject private var viewModel = HQViewModel()
    @StateObject private var l10n = L10n.shared
    #if os(macOS)
    @StateObject private var externalDashboardManager = HQExternalDashboardWindowManager()
    @StateObject private var notificationCueManager = HQNotificationCueManager.shared
    @StateObject private var spacebarPTT = HQSpacebarPTTMonitor()
    @StateObject private var syncReceiver = MacSyncReceiver()
    #endif
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.uiScale") private var uiScale: Double = 1.0
    @AppStorage("hq.externalDisplayEnabled") private var externalDisplayEnabled: Bool = true

    public init(state: MacSystemUIState) {
        _macState = State(initialValue: state)
    }

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark", "black": return .dark
        default: return nil
        }
    }

    public var body: some View {
        HQZoomContainer(scale: uiScale) {
            HQDashboardView(vm: viewModel)
                .onAppear {
                    if viewModel.hqRole == .server {
                        viewModel.startServer()
                    }
                    #if os(macOS)
                    startSyncReceiverIfNeeded()
                    externalDashboardManager.start(viewModel: viewModel, l10n: l10n, colorScheme: colorScheme)
                    externalDashboardManager.setEnabled(externalDisplayEnabled)
                    spacebarPTT.attach(viewModel: viewModel)
                    #endif
                }
                #if os(macOS)
                .onDisappear {
                    syncReceiver.stop()
                }
                #endif
                #if os(macOS)
                .onChange(of: appColorScheme) { _, _ in
                    externalDashboardManager.refresh(colorScheme: colorScheme)
                }
                .onChange(of: l10n.language) { _, _ in
                    externalDashboardManager.refresh(colorScheme: colorScheme)
                }
                .onChange(of: externalDisplayEnabled) { _, newValue in
                    externalDashboardManager.setEnabled(newValue)
                }
                #endif
                .preferredColorScheme(colorScheme)
                .environment(\.locale, Locale(identifier: l10n.language))
                .tint(NV.green)
                .environmentObject(viewModel.udpAudioServer)
                .environmentObject(l10n)
        }
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            if let architecture = macState.uccICSArchitecture {
                MacUCCICSArchitecturePanel(architecture: architecture)
                    .frame(width: 390)
                    .padding(.top, 18)
                    .padding(.leading, 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if macState.runtime.device.appID == .scc {
                MacSOSAlertPanelView(
                    items: macState.sosAlertItems,
                    isReceiverRunning: syncReceiver.isRunning,
                    receiverPort: syncReceiver.port,
                    receiverError: syncReceiver.lastError
                )
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
        }
        .overlay {
            HQNotificationFlashOverlay(manager: notificationCueManager)
        }
        #endif
    }

    #if os(macOS)
    private func startSyncReceiverIfNeeded() {
        guard macState.runtime.device.appID == .scc else { return }
        syncReceiver.start { batch, receivedAt in
            macState.receive(batch, receivedAt: receivedAt)
        }
    }
    #endif

}

public struct MacSystemSettingsView: View {
    private let settingsInfo: LinkGuardAppSettingsInfo

    public init(settingsInfo: LinkGuardAppSettingsInfo) {
        self.settingsInfo = settingsInfo
    }

    public var body: some View {
        HQPage(maxWidth: NV.readablePageMaxWidth, spacing: NV.pageSpacing) {
            HQPageTitleBar("v0.3 設定", icon: "gearshape.fill", accent: NV.info)
            HQPanel(title: "版本", icon: "tag.fill", accent: NV.green) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 8) {
                    ForEach(settingsInfo.items) { item in
                        GridRow {
                            Text(item.title)
                                .foregroundColor(.secondary)
                            Text(item.value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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

#if os(macOS)
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
            if event.isARepeat { return nil }
            if !self.pttHeld {
                self.pttHeld = true
                self.viewModel?.startHQPushToTalk()
            }
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == Self.spaceKeyCode else { return event }
            if Self.isTextEditingFocus() {
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
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
    }

    private static func isTextEditingFocus() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSText || responder is NSTextView
    }
}
#endif
