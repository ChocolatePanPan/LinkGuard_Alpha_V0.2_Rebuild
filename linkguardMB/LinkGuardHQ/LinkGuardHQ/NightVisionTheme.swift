import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 夜視主題色彩系統
enum NV {
    static let green       = Color(red: 0.20, green: 0.86, blue: 0.38)
    static let greenMedium = Color(red: 0.13, green: 0.68, blue: 0.28)
    static let greenDim    = Color(red: 0.08, green: 0.44, blue: 0.20)
    static let greenFaint  = Color(red: 0.05, green: 0.26, blue: 0.13)
    static let nightVisionBG = Color(red: 0.012, green: 0.042, blue: 0.032)
    static let nightVisionChrome = Color(red: 0.018, green: 0.060, blue: 0.046)
    static let nightVisionSurface = Color(red: 0.035, green: 0.082, blue: 0.064)
    static let nightVisionRaisedSurface = Color(red: 0.050, green: 0.115, blue: 0.090)
    static let absoluteBlackBG = Color.black
    static let absoluteBlackSurface = Color(red: 0.035, green: 0.038, blue: 0.035)
    #if canImport(UIKit)
    static let bg = Color(UIColor { trait in
        themedBackgroundUIColor(isSystemDark: trait.userInterfaceStyle == .dark)
    })
    static let surface = Color(UIColor { trait in
        themedSurfaceUIColor(isSystemDark: trait.userInterfaceStyle == .dark)
    })
    #elseif canImport(AppKit)
    static let bg = Color(NSColor(name: nil) { appearance in
        themedBackgroundNSColor(isSystemDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    })
    static let surface = Color(NSColor(name: nil) { appearance in
        themedSurfaceNSColor(isSystemDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
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
    static let pagePadding: CGFloat = 20
    static let pageSpacing: CGFloat = 20
    static let panelSpacing: CGFloat = 12
    static let pageMaxWidth: CGFloat = 1180
    static let readablePageMaxWidth: CGFloat = 920
    static let statCardMinHeight: CGFloat = 76
    static let tagOpacity:  Double  = 0.15
    static let dotSize:     CGFloat = 8
    static let strokeWidth: CGFloat = 1

    static func pageBackground(appColorScheme: String, colorScheme: ColorScheme) -> Color {
        switch resolvedAppearance(appColorScheme: appColorScheme, colorScheme: colorScheme) {
        case .absoluteBlack:
            return absoluteBlackBG
        case .dark:
            return nightVisionBG
        case .light:
            return bg
        }
    }

    static func panelBackground(appColorScheme: String, colorScheme: ColorScheme) -> Color {
        surfaceBackground(appColorScheme: appColorScheme, colorScheme: colorScheme, opacity: 0.94)
    }

    static func surfaceBackground(appColorScheme: String, colorScheme: ColorScheme, opacity: Double = 1) -> Color {
        switch resolvedAppearance(appColorScheme: appColorScheme, colorScheme: colorScheme) {
        case .absoluteBlack:
            return absoluteBlackSurface.opacity(opacity)
        case .dark:
            return nightVisionSurface.opacity(opacity)
        case .light:
            return surface.opacity(opacity)
        }
    }

    static func navigationBackground(appColorScheme: String, colorScheme: ColorScheme) -> Color {
        switch resolvedAppearance(appColorScheme: appColorScheme, colorScheme: colorScheme) {
        case .absoluteBlack:
            return absoluteBlackBG
        case .dark:
            return nightVisionChrome
        case .light:
            return surface.opacity(0.96)
        }
    }

    static func navigationSelectionFill(appColorScheme: String, colorScheme: ColorScheme, accent: Color) -> Color {
        switch resolvedAppearance(appColorScheme: appColorScheme, colorScheme: colorScheme) {
        case .absoluteBlack:
            return Color.black
        case .dark:
            return accent.opacity(0.24)
        case .light:
            return accent.opacity(0.14)
        }
    }

    private static func resolvedAppearance(appColorScheme: String, colorScheme: ColorScheme) -> ResolvedAppearance {
        resolvedAppearance(appColorScheme: appColorScheme, isSystemDark: colorScheme == .dark)
    }

    private static func resolvedAppearance(appColorScheme: String, isSystemDark: Bool) -> ResolvedAppearance {
        switch appColorScheme {
        case "black":
            return .absoluteBlack
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return isSystemDark ? .dark : .light
        }
    }

    private static var storedAppColorScheme: String {
        UserDefaults.standard.string(forKey: "appColorScheme") ?? "dark"
    }

    #if canImport(UIKit)
    private static func themedBackgroundUIColor(isSystemDark: Bool) -> UIColor {
        switch resolvedAppearance(appColorScheme: storedAppColorScheme, isSystemDark: isSystemDark) {
        case .absoluteBlack:
            return .black
        case .dark:
            return UIColor(red: 0.012, green: 0.042, blue: 0.032, alpha: 1)
        case .light:
            return .systemBackground
        }
    }

    private static func themedSurfaceUIColor(isSystemDark: Bool) -> UIColor {
        switch resolvedAppearance(appColorScheme: storedAppColorScheme, isSystemDark: isSystemDark) {
        case .absoluteBlack:
            return UIColor(red: 0.035, green: 0.038, blue: 0.035, alpha: 1)
        case .dark:
            return UIColor(red: 0.035, green: 0.082, blue: 0.064, alpha: 1)
        case .light:
            return .secondarySystemGroupedBackground
        }
    }
    #elseif canImport(AppKit)
    private static func themedBackgroundNSColor(isSystemDark: Bool) -> NSColor {
        switch resolvedAppearance(appColorScheme: storedAppColorScheme, isSystemDark: isSystemDark) {
        case .absoluteBlack:
            return .black
        case .dark:
            return NSColor(red: 0.012, green: 0.042, blue: 0.032, alpha: 1)
        case .light:
            return .windowBackgroundColor
        }
    }

    private static func themedSurfaceNSColor(isSystemDark: Bool) -> NSColor {
        switch resolvedAppearance(appColorScheme: storedAppColorScheme, isSystemDark: isSystemDark) {
        case .absoluteBlack:
            return NSColor(red: 0.035, green: 0.038, blue: 0.035, alpha: 1)
        case .dark:
            return NSColor(red: 0.035, green: 0.082, blue: 0.064, alpha: 1)
        case .light:
            return .controlBackgroundColor
        }
    }

    static var windowBackgroundNSColor: NSColor {
        let isSystemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return themedBackgroundNSColor(isSystemDark: isSystemDark)
    }
    #endif

    private enum ResolvedAppearance {
        case light
        case dark
        case absoluteBlack
    }
}

struct HQPage<Content: View>: View {
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @Environment(\.colorScheme) private var colorScheme
    let maxWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = NV.pageMaxWidth,
         spacing: CGFloat = NV.pageSpacing,
         @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.vertical, NV.pagePadding)
            .padding(.horizontal, NV.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(NV.pageBackground(appColorScheme: appColorScheme, colorScheme: colorScheme).ignoresSafeArea())
    }
}

struct HQPageHeader: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color

    init(_ title: String,
         subtitle: String? = nil,
         icon: String,
         accent: Color = NV.green) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(accent)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title.bold())
                    .foregroundColor(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct HQPageTitleBar<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color
    @ViewBuilder let trailing: Trailing

    init(_ title: String,
         subtitle: String? = nil,
         icon: String,
         accent: Color = NV.green,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(accent)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title.bold())
                    .foregroundColor(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension HQPageTitleBar where Trailing == EmptyView {
    init(_ title: String,
         subtitle: String? = nil,
         icon: String,
         accent: Color = NV.green) {
        self.init(title, subtitle: subtitle, icon: icon, accent: accent) { EmptyView() }
    }
}

struct HQSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color
    @ViewBuilder let trailing: Trailing

    init(_ title: String,
         subtitle: String? = nil,
         icon: String,
         accent: Color = NV.green,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        HQPageTitleBar(title, subtitle: subtitle, icon: icon, accent: accent) {
            trailing
        }
        .padding(.horizontal, NV.pagePadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: NV.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension HQSectionHeader where Trailing == EmptyView {
    init(_ title: String,
         subtitle: String? = nil,
         icon: String,
         accent: Color = NV.green) {
        self.init(title, subtitle: subtitle, icon: icon, accent: accent) { EmptyView() }
    }
}

struct HQEmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let minHeight: CGFloat

    init(icon: String,
         title: String,
         subtitle: String? = nil,
         minHeight: CGFloat = 300) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.minHeight = minHeight
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(.secondary.opacity(0.65))
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundColor(.secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct HQPanel<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    @ViewBuilder let content: Content

    init(title: String,
         icon: String,
         accent: Color = NV.green,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NV.panelSpacing) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            content
        }
        .hqPanelChrome(accent: accent)
    }
}

extension View {
    func hqThemedPageBackground() -> some View {
        modifier(HQThemedPageBackgroundModifier())
    }

    func hqThemedSurfaceBackground(opacity: Double = 0.94) -> some View {
        modifier(HQThemedSurfaceBackgroundModifier(opacity: opacity))
    }

    func hqPanelChrome(accent: Color = NV.green) -> some View {
        modifier(HQPanelChromeModifier(accent: accent))
    }
}

private struct HQThemedPageBackgroundModifier: ViewModifier {
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(NV.pageBackground(appColorScheme: appColorScheme, colorScheme: colorScheme).ignoresSafeArea())
    }
}

private struct HQThemedSurfaceBackgroundModifier: ViewModifier {
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @Environment(\.colorScheme) private var colorScheme
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background(NV.surfaceBackground(appColorScheme: appColorScheme, colorScheme: colorScheme, opacity: opacity))
    }
}

private struct HQPanelChromeModifier: ViewModifier {
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(NV.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NV.panelBackground(appColorScheme: appColorScheme, colorScheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous)
                    .stroke(accent.opacity(0.30), lineWidth: NV.strokeWidth)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 10, x: 0, y: 4)
    }
}
