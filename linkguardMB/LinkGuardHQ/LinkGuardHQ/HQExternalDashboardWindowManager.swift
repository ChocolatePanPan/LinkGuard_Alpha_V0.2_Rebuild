import SwiftUI

#if os(macOS)
import AppKit

@MainActor
final class HQExternalDashboardWindowManager: ObservableObject {
    private weak var viewModel: HQViewModel?
    private weak var l10n: L10n?
    private var colorScheme: ColorScheme?
    private var screenObserver: NSObjectProtocol?
    private var windows: [ExternalDisplayRole: NSWindow] = [:]
    @Published private(set) var externalScreenCount: Int = 0
    private var enabled: Bool = true

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if enabled {
            syncWindow()
        } else {
            closeAllWindows()
        }
    }
    func start(viewModel: HQViewModel, l10n: L10n, colorScheme: ColorScheme?) {
        self.viewModel = viewModel
        self.l10n = l10n
        self.colorScheme = colorScheme

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncWindow()
                }
            }
        }

        syncWindow()
    }

    func refresh(colorScheme: ColorScheme?) {
        self.colorScheme = colorScheme
        updateRootViews()
        syncWindow()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        closeAllWindows()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func syncWindow() {
        externalScreenCount = externalScreens.count
        let screenAssignments = Array(zip(ExternalDisplayRole.allCases, externalScreens))
        let activeRoles = Set(screenAssignments.map { $0.0 })

        guard viewModel != nil, l10n != nil, enabled else {
            closeAllWindows()
            return
        }

        for role in ExternalDisplayRole.allCases where !activeRoles.contains(role) {
            closeWindow(for: role)
        }

        for (role, screen) in screenAssignments {
            syncWindow(for: role, on: screen)
        }
    }

    private var externalScreens: [NSScreen] {
        let mainScreen = NSScreen.main
        return NSScreen.screens.filter { screen in
            guard let mainScreen else { return true }
            return screen !== mainScreen
        }
    }

    private func syncWindow(for role: ExternalDisplayRole, on screen: NSScreen) {
        if windows[role] == nil {
            createWindow(for: role, on: screen)
            return
        }

        windows[role]?.setFrame(screen.frame, display: true)
        updateRootView(for: role)
        windows[role]?.orderFrontRegardless()
    }

    private func createWindow(for role: ExternalDisplayRole, on screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = role.title
        window.backgroundColor = NV.windowBackgroundNSColor
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: rootView(for: role))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        windows[role] = window
    }

    private func updateRootViews() {
        for role in windows.keys {
            updateRootView(for: role)
        }
    }

    private func updateRootView(for role: ExternalDisplayRole) {
        guard let hostingController = windows[role]?.contentViewController as? NSHostingController<AnyView> else { return }
        hostingController.rootView = rootView(for: role)
    }

    private func rootView(for role: ExternalDisplayRole) -> AnyView {
        guard let viewModel, let l10n else { return AnyView(EmptyView()) }

        switch role {
        case .dashboard:
            return AnyView(
                HQExternalDisplayDashboardView(vm: viewModel)
                    .preferredColorScheme(colorScheme)
                    .environment(\.locale, Locale(identifier: l10n.language))
                    .environmentObject(l10n)
                    .tint(NV.green)
            )
        case .victimMap:
            return AnyView(
                HQExternalVictimMapDisplayView(vm: viewModel)
                    .preferredColorScheme(colorScheme)
                    .environment(\.locale, Locale(identifier: l10n.language))
                    .environmentObject(l10n)
                    .tint(NV.green)
            )
        }
    }

    private func closeWindow(for role: ExternalDisplayRole) {
        windows[role]?.close()
        windows[role] = nil
    }

    private func closeAllWindows() {
        for role in ExternalDisplayRole.allCases {
            closeWindow(for: role)
        }
    }
}

private enum ExternalDisplayRole: CaseIterable, Hashable {
    case dashboard
    case victimMap

    var title: String {
        switch self {
        case .dashboard:
            return L("外接大儀表板")
        case .victimMap:
            return L("外接受困者地圖")
        }
    }
}
#endif