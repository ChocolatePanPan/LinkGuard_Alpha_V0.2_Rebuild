import SwiftUI

#if os(macOS)
import AppKit

@MainActor
final class HQExternalDashboardWindowManager: ObservableObject {
    private weak var viewModel: HQViewModel?
    private weak var l10n: L10n?
    private var colorScheme: ColorScheme?
    private var screenObserver: NSObjectProtocol?
    private var window: NSWindow?

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
        updateRootView()
        syncWindow()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        closeWindow()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func syncWindow() {
        guard let externalScreen else {
            closeWindow()
            return
        }
        guard viewModel != nil, l10n != nil else {
            closeWindow()
            return
        }

        if window == nil {
            createWindow(on: externalScreen)
        } else {
            window?.setFrame(externalScreen.frame, display: true)
            updateRootView()
            window?.orderFrontRegardless()
        }
    }

    private var externalScreen: NSScreen? {
        let mainScreen = NSScreen.main
        return NSScreen.screens.first { screen in
            guard let mainScreen else { return true }
            return screen !== mainScreen
        }
    }

    private func createWindow(on screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = L("外接大儀表板")
        window.backgroundColor = .black
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: rootView())
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    private func updateRootView() {
        guard let hostingController = window?.contentViewController as? NSHostingController<AnyView> else { return }
        hostingController.rootView = rootView()
    }

    private func rootView() -> AnyView {
        guard let viewModel, let l10n else { return AnyView(EmptyView()) }
        return AnyView(
            HQExternalDisplayDashboardView(vm: viewModel)
                .preferredColorScheme(colorScheme)
                .environment(\.locale, Locale(identifier: l10n.language))
                .environmentObject(l10n)
                .tint(NV.green)
        )
    }

    private func closeWindow() {
        window?.close()
        window = nil
    }
}
#endif