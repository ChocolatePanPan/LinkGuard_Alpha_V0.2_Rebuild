import LinkGuardV03Core
import SwiftUI

enum FieldTheme {
    static let pageBackground = Color(red: 0.055, green: 0.065, blue: 0.058)
    static let chrome = Color(red: 0.075, green: 0.092, blue: 0.082)
    static let surface = Color(red: 0.095, green: 0.122, blue: 0.108)
    static let raisedSurface = Color(red: 0.125, green: 0.158, blue: 0.140)
    static let green = Color(red: 0.20, green: 0.86, blue: 0.38)
    static let greenDim = Color(red: 0.08, green: 0.44, blue: 0.20)
    static let danger = Color(red: 0.82, green: 0.22, blue: 0.22)
    static let warning = Color(red: 0.72, green: 0.58, blue: 0.12)
    static let info = Color(red: 0.10, green: 0.68, blue: 0.55)
    static let command = Color(red: 0.25, green: 0.40, blue: 0.72)
    static let team = Color(red: 0.10, green: 0.56, blue: 0.72)
    static let medical = Color(red: 0.72, green: 0.25, blue: 0.25)
    static let textOnColor = Color.white
    static let cardRadius: CGFloat = 12
    static let compactRadius: CGFloat = 8
    static let pagePadding: CGFloat = 16
    static let panelSpacing: CGFloat = 12
}

struct FieldPanel<Content: View>: View {
    let title: String?
    let systemImage: String?
    let accent: Color
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        accent: Color = FieldTheme.green,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldTheme.surface, in: RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
                .stroke(accent.opacity(0.24), lineWidth: 1)
        )
    }
}

struct FieldStatusPill: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(accent)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
    }
}

struct FieldMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
    }
}

struct FieldActionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isEnabled ? accent : .secondary)
                        .frame(width: 34, height: 34)
                        .background((isEnabled ? accent : Color.secondary).opacity(0.14), in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
                    Spacer(minLength: 0)
                    Image(systemName: isEnabled ? "arrow.up.right.circle.fill" : "lock.circle")
                        .font(.caption)
                        .foregroundStyle(isEnabled ? accent : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
                    .stroke((isEnabled ? accent : Color.secondary).opacity(isEnabled ? 0.34 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

struct FieldTimelineRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color
    let trailing: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
    }
}

struct FieldAdaptiveGrid<Content: View>: View {
    let minimum: CGFloat
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(minimum: CGFloat = 156, spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.minimum = minimum
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}

extension PriorityLevel {
    var fieldAccentColor: Color {
        switch self {
        case .routine:
            return .secondary
        case .low:
            return FieldTheme.info
        case .medium:
            return FieldTheme.green
        case .high:
            return FieldTheme.warning
        case .critical:
            return FieldTheme.danger
        }
    }

    var fieldLabel: String {
        switch self {
        case .routine:
            return "routine"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .critical:
            return "critical"
        }
    }
}