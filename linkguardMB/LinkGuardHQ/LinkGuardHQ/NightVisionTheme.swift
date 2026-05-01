import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 夜視主題色彩系統
enum NV {
    static let green       = Color(red: 0.08, green: 0.72, blue: 0.25)
    static let greenMedium = Color(red: 0.06, green: 0.58, blue: 0.18)
    static let greenDim    = Color(red: 0.04, green: 0.38, blue: 0.12)
    static let greenFaint  = Color(red: 0.03, green: 0.22, blue: 0.07)
    #if canImport(UIKit)
    static let bg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : .systemBackground
    })
    static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
            : .secondarySystemGroupedBackground
    })
    #elseif canImport(AppKit)
    static let bg = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0, green: 0, blue: 0, alpha: 1)
            : .windowBackgroundColor
    })
    static let surface = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
            : .controlBackgroundColor
    })
    #endif
    static let danger      = Color(red: 0.82, green: 0.22, blue: 0.22)
    static let warning     = Color(red: 0.72, green: 0.58, blue: 0.12)
    static let heartRate   = Color(red: 0.72, green: 0.25, blue: 0.25)
    static let info        = Color(red: 0.10, green: 0.68, blue: 0.55)
    static let simulation  = Color(red: 0.42, green: 0.12, blue: 0.65)
    static let command     = Color(red: 0.25, green: 0.40, blue: 0.72)
    static let team        = Color(red: 0.10, green: 0.56, blue: 0.72)
    static let reinforce   = Color(red: 0.82, green: 0.50, blue: 0.08)
    static let textOnColor = Color.white

    // MARK: - 設計 Token
    static let cardRadius:  CGFloat = 12
    static let tagRadius:   CGFloat = 4
    static let cardPadding: CGFloat = 12
    static let tagOpacity:  Double  = 0.15
    static let dotSize:     CGFloat = 8
    static let strokeWidth: CGFloat = 1
}
