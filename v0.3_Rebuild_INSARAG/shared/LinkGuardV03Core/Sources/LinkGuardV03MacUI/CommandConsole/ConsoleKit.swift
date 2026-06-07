import SwiftUI
import LinkGuardV03Core

// MARK: - v0.3 Command Console design system
//
// Self-contained design primitives for the LinkGuard-UCC / LinkGuard-SCC v0.3
// command consoles. Deliberately independent of the copied v0.2 HQ theme so the
// console is a genuine v0.3 product surface rather than a re-skin.

public enum CCTheme {
    public static let background = Color(.sRGB, red: 0.05, green: 0.07, blue: 0.09, opacity: 1)
    public static let surface = Color(.sRGB, red: 0.09, green: 0.12, blue: 0.15, opacity: 1)
    public static let raised = Color(.sRGB, red: 0.12, green: 0.16, blue: 0.20, opacity: 1)
    public static let sidebar = Color(.sRGB, red: 0.07, green: 0.09, blue: 0.12, opacity: 1)
    public static let stroke = Color.white.opacity(0.08)

    public static let accent = Color(.sRGB, red: 0.30, green: 0.78, blue: 0.62, opacity: 1)   // teal-green
    public static let command = Color(.sRGB, red: 0.40, green: 0.62, blue: 0.95, opacity: 1)
    public static let warning = Color(.sRGB, red: 0.98, green: 0.74, blue: 0.27, opacity: 1)
    public static let danger = Color(.sRGB, red: 0.95, green: 0.38, blue: 0.38, opacity: 1)
    public static let info = Color(.sRGB, red: 0.45, green: 0.72, blue: 0.90, opacity: 1)
    public static let muted = Color.white.opacity(0.55)

    public static func sectionTint(_ section: ICSSection) -> Color {
        switch section {
        case .command: return command
        case .operations: return accent
        case .planning: return info
        case .logistics: return Color(.sRGB, red: 0.78, green: 0.62, blue: 0.95, opacity: 1)
        case .finance: return Color(.sRGB, red: 0.55, green: 0.75, blue: 0.55, opacity: 1)
        case .medical: return Color(.sRGB, red: 0.95, green: 0.55, blue: 0.62, opacity: 1)
        case .afterActionReview: return Color.white.opacity(0.6)
        }
    }

    public static func priorityColor(_ priority: PriorityLevel) -> Color {
        switch priority {
        case .critical: return danger
        case .high: return warning
        case .medium: return info
        case .low: return accent
        case .routine: return muted
        }
    }

    public static func sectionName(_ section: ICSSection) -> String {
        switch section {
        case .command: return "指揮 Command"
        case .operations: return "作業 Operations"
        case .planning: return "計畫 Planning"
        case .logistics: return "後勤 Logistics"
        case .finance: return "財務 Finance"
        case .medical: return "醫療 Medical"
        case .afterActionReview: return "復盤 AAR"
        }
    }
}

// MARK: - Access badge (● primary / ○ limited / ✕ none)

public struct AccessBadge: View {
    public let level: FeatureAccessLevel
    public var compact: Bool = false

    public init(level: FeatureAccessLevel, compact: Bool = false) {
        self.level = level
        self.compact = compact
    }

    private var symbol: String {
        switch level {
        case .primary: return "●"
        case .limited: return "○"
        case .none: return "✕"
        }
    }

    private var color: Color {
        switch level {
        case .primary: return CCTheme.accent
        case .limited: return CCTheme.warning
        case .none: return CCTheme.muted
        }
    }

    private var label: String {
        switch level {
        case .primary: return "完整權限"
        case .limited: return "部分權限"
        case .none: return "無權限"
        }
    }

    public var body: some View {
        if compact {
            Text(symbol).font(.caption2.bold()).foregroundColor(color)
        } else {
            HStack(spacing: 4) {
                Text(symbol).font(.caption2.bold())
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Panels & cards

public struct ConsolePanel<Content: View>: View {
    let title: String
    var systemImage: String?
    var accent: Color
    @ViewBuilder var content: () -> Content

    public init(_ title: String, systemImage: String? = nil, accent: Color = CCTheme.accent, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundColor(accent).font(.subheadline.bold())
                }
                Text(title).font(.subheadline.weight(.bold)).foregroundColor(.white.opacity(0.92))
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CCTheme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

public struct ConsoleStatTile: View {
    let title: String
    let value: String
    var systemImage: String
    var accent: Color
    var caption: String?

    public init(title: String, value: String, systemImage: String, accent: Color = CCTheme.accent, caption: String? = nil) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.accent = accent
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundColor(accent).font(.caption)
                Text(title).font(.caption2.weight(.semibold)).foregroundColor(CCTheme.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.white)
            if let caption {
                Text(caption).font(.caption2).foregroundColor(CCTheme.muted).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(CCTheme.raised)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CCTheme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

public struct ConsoleStatGrid: View {
    let tiles: [ConsoleStatTile]
    var columns: Int

    public init(columns: Int = 4, tiles: [ConsoleStatTile]) {
        self.columns = columns
        self.tiles = tiles
    }

    public var body: some View {
        let layout = Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
        LazyVGrid(columns: layout, spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
        }
    }
}

public struct ConsoleTag: View {
    let text: String
    var color: Color
    public init(_ text: String, color: Color = CCTheme.muted) {
        self.text = text
        self.color = color
    }
    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

public struct ConsoleRow: View {
    let title: String
    var subtitle: String?
    var leadingSystemImage: String?
    var leadingColor: Color
    var trailing: AnyView?

    public init(title: String, subtitle: String? = nil, leadingSystemImage: String? = nil, leadingColor: Color = CCTheme.accent, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.leadingSystemImage = leadingSystemImage
        self.leadingColor = leadingColor
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .foregroundColor(leadingColor)
                    .font(.callout)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundColor(.white.opacity(0.95)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundColor(CCTheme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(CCTheme.raised.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CCTheme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

public struct ConsoleEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    public init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundColor(CCTheme.muted)
            Text(title).font(.callout.weight(.semibold)).foregroundColor(.white.opacity(0.85))
            if let message {
                Text(message).font(.caption).foregroundColor(CCTheme.muted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(CCTheme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A short status note used by modules whose full capability depends on an external
/// integration (radio/PTT, LoRa, PWS, EMIC, AI model, device provisioning). It shows
/// the live snapshot data the module already drives, plus what the integration adds.
public struct ConsoleIntegrationNote: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color

    public init(systemImage: String, title: String, detail: String, tint: Color = CCTheme.info) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundColor(tint).font(.callout)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.bold)).foregroundColor(tint)
                Text(detail).font(.caption2).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Formatting helpers

public enum ConsoleFormat {
    public static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    public static func time(_ date: Date) -> String { timeOnly.string(from: date) }
    public static func stamp(_ date: Date) -> String { dayTime.string(from: date) }

    public static func coordinate(_ c: GeoCoordinate?) -> String {
        guard let c else { return "—" }
        return String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }
}

public extension PriorityLevel {
    var consoleLabel: String {
        switch self {
        case .critical: return "危急"
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        case .routine: return "例行"
        }
    }
}
