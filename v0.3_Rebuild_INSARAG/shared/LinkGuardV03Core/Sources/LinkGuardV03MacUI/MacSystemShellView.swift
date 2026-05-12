import LinkGuardV03Core
import SwiftUI

public struct MacSystemShellView: View {
    private let state: MacSystemUIState
    @State private var selectedSection: ICSSection?

    public init(state: MacSystemUIState) {
        self.state = state
        self._selectedSection = State(initialValue: state.navigationItems.first?.section)
    }

    public var body: some View {
        HStack(spacing: 0) {
            LegacyV02Sidebar(
                state: state,
                selectedSection: Binding(
                    get: { selectedSection ?? state.navigationItems.first?.section },
                    set: { selectedSection = $0 }
                )
            )
            Divider().overlay(LegacyV02NV.greenDim)
            ScrollView {
                VStack(alignment: .leading, spacing: LegacyV02NV.pageSpacing) {
                    LegacyV02Header(state: state)
                    LegacyV02MetricGrid(metrics: state.metrics)
                    LegacyV02OperationalGrid(state: state, selectedModule: selectedModule)
                    LegacyV02SettingsPanel(settingsInfo: state.settingsInfo)
                }
                .padding(.vertical, LegacyV02NV.pagePadding)
                .padding(.horizontal, LegacyV02NV.pagePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(LegacyV02NV.bg.ignoresSafeArea())
        }
        .background(LegacyV02NV.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(LegacyV02NV.green)
    }

    private var selectedModule: MacInheritedModule? {
        let selected = selectedSection ?? state.navigationItems.first?.section
        return state.inheritedModules.first { $0.section == selected }
    }
}

private struct LegacyV02Sidebar: View {
    let state: MacSystemUIState
    @Binding var selectedSection: ICSSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 44, alignment: .leading)
                Text(state.runtime.profile.displayName)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundColor(LegacyV02NV.green)
                Text(state.runtime.device.displayName)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.navigationItems) { item in
                    Button {
                        selectedSection = item.section
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: legacyIcon(for: item.section, fallback: item.systemImageName))
                                .frame(width: 20)
                            Text(legacyTitle(for: item.section, fallback: item.title))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(selectedSection == item.section ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selectedSection == item.section ? LegacyV02NV.green.opacity(0.24) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedSection == item.section ? LegacyV02NV.green.opacity(0.38) : Color.clear, lineWidth: LegacyV02NV.strokeWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                statusChip("VERSION", state.versionInfo.displayVersion, ok: true)
                statusChip("TAG", state.versionInfo.gitTag, ok: true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 236)
        .background(LegacyV02NV.chrome)
    }
}

private struct LegacyV02Header: View {
    let state: MacSystemUIState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 152, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Label(headerTitle, systemImage: "square.grid.3x3.fill")
                    .font(.title.weight(.bold))
                    .foregroundColor(.primary)
                Text(state.subtitle)
                    .font(.subheadline.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                statusChip("SERVER", "READY", ok: true)
                statusChip("MODE", state.runtime.profile.commandAuthority.rawValue.description, ok: true)
                statusChip("BUILD", String(state.versionInfo.buildNumber), ok: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LegacyV02NV.surface)
        .clipShape(RoundedRectangle(cornerRadius: LegacyV02NV.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyV02NV.cardRadius, style: .continuous)
                .stroke(LegacyV02NV.green.opacity(0.24), lineWidth: LegacyV02NV.strokeWidth)
        )
    }

    private var headerTitle: String {
        state.runtime.device.appID == .ucc ? "HQ 大儀表板" : "現場指揮儀表板"
    }
}

private struct LegacyV02MetricGrid: View {
    let metrics: [MacMetricTile]
    private let columns = Array(repeating: GridItem(.flexible(minimum: 140), spacing: LegacyV02NV.panelSpacing), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: LegacyV02NV.panelSpacing) {
            ForEach(metrics.prefix(10)) { metric in
                HStack(spacing: 10) {
                    Image(systemName: metric.systemImageName)
                        .font(.title3)
                        .foregroundColor(metricColor(metric.accentName))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.value)
                            .font(.title2.monospacedDigit().bold())
                        Text(metric.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(LegacyV02NV.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(metricColor(metric.accentName).opacity(0.28), lineWidth: LegacyV02NV.strokeWidth)
                )
            }
        }
    }
}

private struct LegacyV02OperationalGrid: View {
    let state: MacSystemUIState
    let selectedModule: MacInheritedModule?
    private let columns = [
        GridItem(.flexible(minimum: 360), spacing: LegacyV02NV.panelSpacing, alignment: .top),
        GridItem(.flexible(minimum: 360), spacing: LegacyV02NV.panelSpacing, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: LegacyV02NV.panelSpacing) {
            LegacyV02Panel(title: selectedModule?.title ?? "系統就緒度", icon: selectedModule?.systemImageName ?? "checkmark.seal.fill", minHeight: 184) {
                if let selectedModule {
                    VStack(alignment: .leading, spacing: 8) {
                        readinessRow("模組紀錄", detail: "\(selectedModule.recordCount)", ok: true)
                        readinessRow("權限", detail: selectedModule.enabledPermissions.map(\.rawValue).joined(separator: " / "), ok: selectedModule.enabledPermissions.isEmpty == false)
                        readinessRow("繼承來源", detail: selectedModule.inheritedFrom.joined(separator: " / "), ok: true)
                    }
                }
            }

            LegacyV02Panel(title: "待處理重點", icon: "exclamationmark.triangle.fill", minHeight: 184) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.quickActions.prefix(7)) { action in
                        infoRow(icon: action.systemImageName, color: action.isEnabled ? LegacyV02NV.green : LegacyV02NV.warning, title: action.title, detail: action.permission.rawValue, trailing: action.messageType?.rawValue ?? "LOCAL")
                    }
                }
            }

            LegacyV02Panel(title: "傳輸鏈路", icon: "antenna.radiowaves.left.and.right", minHeight: 220) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.transportRoutes.filter { $0.canSend || $0.receives }) { route in
                        infoRow(icon: route.canSend ? "arrow.up.circle" : "arrow.down.circle", color: route.canSend ? LegacyV02NV.green : LegacyV02NV.info, title: route.messageType.rawValue, detail: route.policy.rawValue, trailing: route.receives ? "RECV" : "RELAY")
                    }
                }
            }

            LegacyV02Panel(title: "最近動態", icon: "clock.arrow.circlepath", minHeight: 220) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "checkmark.seal.fill", color: LegacyV02NV.green, title: "Shared Runtime", detail: state.runtime.blueprint.homeSurface.rawValue, trailing: "READY")
                    infoRow(icon: "externaldrive.connected.to.line.below", color: LegacyV02NV.info, title: "Outbound Queue", detail: "\(state.runtime.outboundQueue.entries.count) messages", trailing: "SYNC")
                    infoRow(icon: "tag.fill", color: LegacyV02NV.reinforce, title: "Version Tag", detail: state.versionInfo.gitTag, trailing: state.versionInfo.releaseChannel.rawValue.uppercased())
                }
            }
        }
    }
}

private struct LegacyV02Panel<Content: View>: View {
    let title: String
    let icon: String
    let minHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)
            content
        }
        .padding(LegacyV02NV.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(LegacyV02NV.surface)
        .clipShape(RoundedRectangle(cornerRadius: LegacyV02NV.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyV02NV.cardRadius, style: .continuous)
                .stroke(LegacyV02NV.green.opacity(0.18), lineWidth: LegacyV02NV.strokeWidth)
        )
    }
}

private struct LegacyV02SettingsPanel: View {
    let settingsInfo: LinkGuardAppSettingsInfo

    var body: some View {
        LegacyV02Panel(title: "設定", icon: "gearshape.fill", minHeight: 132) {
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
}

public struct MacSystemSettingsView: View {
    private let settingsInfo: LinkGuardAppSettingsInfo

    public init(settingsInfo: LinkGuardAppSettingsInfo) {
        self.settingsInfo = settingsInfo
    }

    public var body: some View {
        LegacyV02SettingsPanel(settingsInfo: settingsInfo)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LegacyV02NV.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

private func statusChip(_ label: String, _ value: String, ok: Bool) -> some View {
    HStack(spacing: 6) {
        Circle().fill(ok ? LegacyV02NV.green : LegacyV02NV.danger).frame(width: 8, height: 8)
        Text("\(label) ▸ \(value)")
            .font(.caption.monospaced())
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(LegacyV02NV.raisedSurface)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
}

private func readinessRow(_ title: String, detail: String, ok: Bool) -> some View {
    HStack(spacing: 8) {
        Circle()
            .fill(ok ? LegacyV02NV.green : LegacyV02NV.warning)
            .frame(width: 8, height: 8)
        Text(title)
            .font(.caption.bold())
        Spacer(minLength: 8)
        Text(detail.isEmpty ? "--" : detail)
            .font(.caption.monospaced())
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
}

private func infoRow(icon: String, color: Color, title: String, detail: String, trailing: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.caption)
            .foregroundColor(color)
            .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text(trailing)
            .font(.caption2.monospaced())
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
    .padding(8)
    .background(LegacyV02NV.bg.opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
}

private func metricColor(_ name: String) -> Color {
    switch name {
    case "red": return LegacyV02NV.danger
    case "orange": return LegacyV02NV.reinforce
    case "yellow": return LegacyV02NV.warning
    case "blue", "indigo": return LegacyV02NV.command
    case "teal": return LegacyV02NV.info
    case "purple": return Color(red: 0.42, green: 0.12, blue: 0.65)
    case "gray": return .secondary
    default: return LegacyV02NV.green
    }
}

private func legacyTitle(for section: ICSSection, fallback: String) -> String {
    switch section {
    case .command: return "指揮決策"
    case .operations: return "災害狀態"
    case .planning: return "會報系統"
    case .logistics: return "資源管理"
    case .finance: return "統計儀表板"
    case .medical: return "傷患預警"
    case .afterActionReview: return "事件日誌"
    }
}

private func legacyIcon(for section: ICSSection, fallback: String) -> String {
    switch section {
    case .command: return "brain.head.profile"
    case .operations: return "building.2"
    case .planning: return "doc.text.fill"
    case .logistics: return "shippingbox"
    case .finance: return "chart.bar.xaxis"
    case .medical: return "heart.text.square"
    case .afterActionReview: return "clock.arrow.circlepath"
    }
}
