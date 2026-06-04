import SwiftUI

#if canImport(UIKit)
import UIKit

private struct KeyboardDismissGestureInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        context.coordinator.install(on: uiView.window)
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class InstallerView: UIView {
        var onMoveToWindow: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var gestureRecognizer: UITapGestureRecognizer?

        func install(on window: UIWindow?) {
            guard let window else { return }
            guard installedWindow !== window else { return }

            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)
            installedWindow = window
            gestureRecognizer = recognizer
        }

        func uninstall() {
            if let gestureRecognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(gestureRecognizer)
            }
            installedWindow = nil
            gestureRecognizer = nil
        }

        @objc private func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.isKeyboardInteractiveControl
        }
    }
}

private extension UIView {
    var isKeyboardInteractiveControl: Bool {
        var view: UIView? = self
        while let currentView = view {
            if currentView is UIControl || currentView is UITextView || currentView is UITextField {
                return true
            }
            view = currentView.superview
        }
        return false
    }
}
#endif

extension View {
    func dismissKeyboardOnBlankTap() -> some View {
        #if canImport(UIKit)
        background {
            KeyboardDismissGestureInstaller()
                .frame(width: 0, height: 0)
        }
        #else
        self
        #endif
    }
}