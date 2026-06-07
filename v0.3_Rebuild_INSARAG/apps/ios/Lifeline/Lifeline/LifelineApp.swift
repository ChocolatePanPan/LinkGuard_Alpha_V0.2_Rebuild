import LinkGuardV03Core
import SwiftUI

@main
struct LifelineApp: App {
    var body: some Scene {
        WindowGroup {
            LifelineRootView()
        }
    }
}

private struct LifelineRootView: View {
    @State private var selectedTab: LifelineTab = .overview
    @State private var queuedReports = 2
    @State private var connectionState: LifelineConnectionState = .ready
    @State private var selectedModule: CommandConsoleModule?

    private let modules = CommandConsoleCatalog.uccModules
    private let version = LinkGuardVersionInfo.current

    private var primaryModules: [CommandConsoleModule] {
        modules.filter { $0.accessLevel == .primary }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
                        heroPanel
                        quickActionsPanel
                        readinessPanel
                        sectionSummaryPanel
                    }
                    .padding(LifelineTheme.pagePadding)
                }
                .background(LifelineTheme.pageBackground.ignoresSafeArea())
                .navigationTitle("Lifeline")
                .toolbar { versionToolbar }
            }
            .tag(LifelineTab.overview)
            .tabItem { Label(LifelineTab.overview.title, systemImage: LifelineTab.overview.systemImage) }

            NavigationStack {
                LifelineModuleListView(modules: modules) { module in
                    selectedModule = module
                }
                .background(LifelineTheme.pageBackground.ignoresSafeArea())
                .navigationTitle("UCC 模組")
                .toolbar { versionToolbar }
            }
            .tag(LifelineTab.modules)
            .tabItem { Label(LifelineTab.modules.title, systemImage: LifelineTab.modules.systemImage) }

            NavigationStack {
                LifelineReportView(queuedReports: $queuedReports)
                    .background(LifelineTheme.pageBackground.ignoresSafeArea())
                    .navigationTitle("現場回報")
                    .toolbar { versionToolbar }
            }
            .tag(LifelineTab.report)
            .tabItem { Label(LifelineTab.report.title, systemImage: LifelineTab.report.systemImage) }

            NavigationStack {
                LifelineSyncView(
                    connectionState: $connectionState,
                    queuedReports: queuedReports,
                    modules: modules,
                    version: version
                )
                .background(LifelineTheme.pageBackground.ignoresSafeArea())
                .navigationTitle("Lifeline-HQ")
                .toolbar { versionToolbar }
            }
            .tag(LifelineTab.sync)
            .tabItem { Label(LifelineTab.sync.title, systemImage: LifelineTab.sync.systemImage) }
        }
        .tint(LifelineTheme.green)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedModule) { module in
            LifelineModuleDetailView(module: module)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var versionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Text(version.displayVersion)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var heroPanel: some View {
        LifelinePanel(accent: LifelineTheme.green) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LifelineTheme.green.opacity(0.18))
                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(LifelineTheme.green)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lifeline")
                            .font(.title.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("UCC v0.2 field companion")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LifelineTheme.green)
                        Text("連線對象：Lifeline-HQ / UCC 指揮端")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    LifelineStatusPill(
                        title: connectionState.title,
                        systemImage: connectionState.systemImage,
                        accent: connectionState.accent
                    )
                    LifelineStatusPill(
                        title: "\(modules.count) UCC 模組",
                        systemImage: "rectangle.3.group.fill",
                        accent: LifelineTheme.info
                    )
                    LifelineStatusPill(
                        title: "\(queuedReports) 待同步",
                        systemImage: "tray.full.fill",
                        accent: queuedReports == 0 ? LifelineTheme.green : LifelineTheme.warning
                    )
                }
            }
        }
    }

    private var quickActionsPanel: some View {
        LifelinePanel("快速操作", systemImage: "bolt.fill", accent: LifelineTheme.command) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                LifelineActionButton(title: "SOS", detail: "送往 UCC 總覽", systemImage: "sos.circle.fill", accent: LifelineTheme.danger) {
                    queuedReports += 1
                    connectionState = .attention
                }
                LifelineActionButton(title: "災情", detail: "新增現場摘要", systemImage: "building.2.crop.circle.fill", accent: LifelineTheme.warning) {
                    queuedReports += 1
                }
                LifelineActionButton(title: "傷患", detail: "回報人數狀態", systemImage: "cross.case.fill", accent: LifelineTheme.medical) {
                    queuedReports += 1
                }
                LifelineActionButton(title: "電台", detail: "標記語音紀錄", systemImage: "antenna.radiowaves.left.and.right", accent: LifelineTheme.info) {
                    queuedReports += 1
                }
            }
        }
    }

    private var readinessPanel: some View {
        LifelinePanel("UCC 對應狀態", systemImage: "checkmark.shield.fill", accent: LifelineTheme.green) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                LifelineMetricTile(title: "完整權限", value: "\(primaryModules.count)", systemImage: "checkmark.seal.fill", accent: LifelineTheme.green)
                LifelineMetricTile(title: "可用模組", value: "\(modules.filter(\.isAvailable).count)", systemImage: "square.grid.3x3.fill", accent: LifelineTheme.info)
                LifelineMetricTile(title: "指揮端", value: "UCC", systemImage: "person.badge.key.fill", accent: LifelineTheme.command)
                LifelineMetricTile(title: "HQ 名稱", value: "Lifeline-HQ", systemImage: "desktopcomputer", accent: LifelineTheme.warning)
            }
        }
    }

    private var sectionSummaryPanel: some View {
        LifelinePanel("ICS 分區", systemImage: "point.3.connected.trianglepath.dotted", accent: LifelineTheme.info) {
            VStack(spacing: 9) {
                ForEach(sectionSummaries) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.section.systemImage)
                            .foregroundStyle(item.section.accent)
                            .frame(width: 30, height: 30)
                            .background(item.section.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.section.title)
                                .font(.subheadline.weight(.bold))
                            Text(item.modules.map(\.title).joined(separator: "、"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text("\(item.modules.count)")
                            .font(.headline.monospacedDigit())
                    }
                    .padding(10)
                    .background(LifelineTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var sectionSummaries: [LifelineSectionSummary] {
        ICSSection.allCases.compactMap { section in
            let items = modules.filter { $0.section == section }
            guard items.isEmpty == false else { return nil }
            return LifelineSectionSummary(section: section, modules: items)
        }
    }
}

private enum LifelineTab: String, CaseIterable, Hashable {
    case overview
    case modules
    case report
    case sync

    var title: String {
        switch self {
        case .overview: return "總覽"
        case .modules: return "模組"
        case .report: return "回報"
        case .sync: return "同步"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .modules: return "rectangle.3.group.fill"
        case .report: return "square.and.pencil"
        case .sync: return "antenna.radiowaves.left.and.right.circle.fill"
        }
    }
}

private enum LifelineConnectionState: String, CaseIterable, Hashable {
    case ready
    case syncing
    case attention

    var title: String {
        switch self {
        case .ready: return "待命"
        case .syncing: return "同步中"
        case .attention: return "需確認"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .attention: return "exclamationmark.triangle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .ready: return LifelineTheme.green
        case .syncing: return LifelineTheme.info
        case .attention: return LifelineTheme.warning
        }
    }
}

private struct LifelineModuleListView: View {
    let modules: [CommandConsoleModule]
    let onSelect: (CommandConsoleModule) -> Void

    @State private var searchText = ""
    @State private var selectedSection: ICSSection?

    private var filteredModules: [CommandConsoleModule] {
        modules.filter { module in
            let matchesSection = selectedSection.map { module.section == $0 } ?? true
            let matchesSearch = searchText.isEmpty ||
                module.title.localizedCaseInsensitiveContains(searchText) ||
                module.capability.localizedCaseInsensitiveContains(searchText) ||
                module.purpose.localizedCaseInsensitiveContains(searchText)
            return matchesSection && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
                sectionFilter
                ForEach(filteredModules) { module in
                    Button {
                        onSelect(module)
                    } label: {
                        LifelineModuleCard(module: module)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(LifelineTheme.pagePadding)
        }
        .searchable(text: $searchText, prompt: "搜尋 UCC 模組")
    }

    private var sectionFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LifelineFilterChip(title: "全部", isSelected: selectedSection == nil, accent: LifelineTheme.green) {
                    selectedSection = nil
                }
                ForEach(ICSSection.allCases, id: \.self) { section in
                    LifelineFilterChip(title: section.title, isSelected: selectedSection == section, accent: section.accent) {
                        selectedSection = section
                    }
                }
            }
        }
    }
}

private struct LifelineReportView: View {
    @Binding var queuedReports: Int

    @State private var selectedReportType: LifelineReportType = .situation
    @State private var title = ""
    @State private var detail = ""
    @State private var severity = 2.0
    @State private var includesLocation = true
    @State private var lastQueuedText = "尚未送出"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
                LifelinePanel("回報類型", systemImage: "square.grid.2x2.fill", accent: selectedReportType.accent) {
                    Picker("回報類型", selection: $selectedReportType) {
                        ForEach(LifelineReportType.allCases, id: \.self) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LifelinePanel("內容", systemImage: "doc.text.fill", accent: LifelineTheme.info) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("標題", text: $title)
                            .textFieldStyle(.roundedBorder)
                        TextField("摘要", text: $detail, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                        Toggle(isOn: $includesLocation) {
                            Label("附加 GPS / Worksite", systemImage: "location.fill")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("緊急程度 \(Int(severity))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: $severity, in: 1...5, step: 1)
                        }
                    }
                }

                Button {
                    queuedReports += 1
                    let reportTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    lastQueuedText = reportTitle.isEmpty ? "\(selectedReportType.title) 已加入待同步" : "\(reportTitle) 已加入待同步"
                    title = ""
                    detail = ""
                } label: {
                    Label("加入 Lifeline-HQ 待同步", systemImage: "tray.and.arrow.up.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedReportType.accent)

                LifelinePanel("同步佇列", systemImage: "tray.full.fill", accent: queuedReports == 0 ? LifelineTheme.green : LifelineTheme.warning) {
                    LifelineTimelineRow(
                        title: "\(queuedReports) 筆待同步",
                        detail: lastQueuedText,
                        systemImage: "clock.arrow.circlepath",
                        accent: queuedReports == 0 ? LifelineTheme.green : LifelineTheme.warning
                    )
                }
            }
            .padding(LifelineTheme.pagePadding)
        }
    }
}

private struct LifelineSyncView: View {
    @Binding var connectionState: LifelineConnectionState
    let queuedReports: Int
    let modules: [CommandConsoleModule]
    let version: LinkGuardVersionInfo

    @State private var endpoint = "http://lifeline-hq.local:8080/sync"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
                LifelinePanel("指揮端", systemImage: "desktopcomputer", accent: connectionState.accent) {
                    VStack(spacing: 10) {
                        LifelineTimelineRow(
                            title: "Lifeline-HQ",
                            detail: "_linkguard-hq._tcp / UCC command console",
                            systemImage: "antenna.radiowaves.left.and.right",
                            accent: connectionState.accent
                        )
                        TextField("同步端點", text: $endpoint)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    connectionState = .syncing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        connectionState = queuedReports == 0 ? .ready : .attention
                    }
                } label: {
                    Label("測試 Lifeline-HQ 連線", systemImage: "bolt.horizontal.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(connectionState.accent)

                LifelinePanel("同步契約", systemImage: "checklist.checked", accent: LifelineTheme.green) {
                    VStack(spacing: 9) {
                        LifelineTimelineRow(
                            title: "UCC catalog",
                            detail: "讀取 \(modules.count) 個 CommandConsoleCatalog.uccModules",
                            systemImage: "rectangle.3.group.fill",
                            accent: LifelineTheme.green
                        )
                        LifelineTimelineRow(
                            title: "版本",
                            detail: "\(version.series) / \(version.displayVersion)",
                            systemImage: "tag.fill",
                            accent: LifelineTheme.info
                        )
                        LifelineTimelineRow(
                            title: "離線佇列",
                            detail: "\(queuedReports) 筆等待上傳 Lifeline-HQ",
                            systemImage: "tray.full.fill",
                            accent: queuedReports == 0 ? LifelineTheme.green : LifelineTheme.warning
                        )
                    }
                }
            }
            .padding(LifelineTheme.pagePadding)
        }
    }
}

private struct LifelineModuleDetailView: View {
    let module: CommandConsoleModule

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
                    LifelinePanel(accent: module.section.accent) {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: module.systemImageName)
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(module.section.accent)
                                .frame(width: 64, height: 64)
                                .background(module.section.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                            Text(module.title)
                                .font(.title2.weight(.bold))
                            Text(module.phaseLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(module.section.accent)
                        }
                    }

                    LifelinePanel("模組目的", systemImage: "scope", accent: LifelineTheme.info) {
                        VStack(spacing: 9) {
                            LifelineTimelineRow(title: "功能", detail: module.capability, systemImage: "gearshape.2.fill", accent: LifelineTheme.info)
                            LifelineTimelineRow(title: "目的", detail: module.purpose, systemImage: "target", accent: LifelineTheme.green)
                            LifelineTimelineRow(title: "ICS", detail: module.section.title, systemImage: module.section.systemImage, accent: module.section.accent)
                            LifelineTimelineRow(title: "權限", detail: module.accessLevel.title, systemImage: module.accessLevel.systemImage, accent: module.accessLevel.accent)
                        }
                    }
                }
                .padding(LifelineTheme.pagePadding)
            }
            .background(LifelineTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("模組細節")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .tint(LifelineTheme.green)
    }
}

private struct LifelineModuleCard: View {
    let module: CommandConsoleModule

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: module.systemImageName)
                .font(.headline.weight(.bold))
                .foregroundStyle(module.section.accent)
                .frame(width: 42, height: 42)
                .background(module.section.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(module.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text("P\(module.phaseNumber)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(module.section.accent)
                }
                Text(module.capability)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    LifelineStatusPill(title: module.section.title, systemImage: module.section.systemImage, accent: module.section.accent)
                    LifelineStatusPill(title: module.accessLevel.title, systemImage: module.accessLevel.systemImage, accent: module.accessLevel.accent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifelineTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(module.section.accent.opacity(0.22), lineWidth: 1))
    }
}

private struct LifelinePanel<Content: View>: View {
    let title: String?
    let systemImage: String?
    let accent: Color
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        accent: Color = LifelineTheme.green,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifelineTheme.panelSpacing) {
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
        .background(LifelineTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.24), lineWidth: 1))
    }
}

private struct LifelineMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(LifelineTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LifelineActionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(LifelineTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct LifelineStatusPill: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(accent)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.32), lineWidth: 1))
    }
}

private struct LifelineFilterChip: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? LifelineTheme.textOnColor : accent)
                .background(isSelected ? accent : accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LifelineTimelineRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(LifelineTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LifelineSectionSummary: Identifiable {
    let section: ICSSection
    let modules: [CommandConsoleModule]

    var id: ICSSection { section }
}

private enum LifelineReportType: CaseIterable, Hashable {
    case situation
    case sos
    case casualty

    var title: String {
        switch self {
        case .situation: return "災情"
        case .sos: return "SOS"
        case .casualty: return "傷患"
        }
    }

    var systemImage: String {
        switch self {
        case .situation: return "building.2.crop.circle.fill"
        case .sos: return "sos.circle.fill"
        case .casualty: return "cross.case.fill"
        }
    }

    var accent: Color {
        switch self {
        case .situation: return LifelineTheme.warning
        case .sos: return LifelineTheme.danger
        case .casualty: return LifelineTheme.medical
        }
    }
}

private enum LifelineTheme {
    static let pageBackground = Color(red: 0.045, green: 0.058, blue: 0.061)
    static let surface = Color(red: 0.085, green: 0.108, blue: 0.118)
    static let raisedSurface = Color(red: 0.120, green: 0.145, blue: 0.158)
    static let green = Color(red: 0.18, green: 0.82, blue: 0.52)
    static let info = Color(red: 0.28, green: 0.62, blue: 0.90)
    static let command = Color(red: 0.44, green: 0.56, blue: 0.90)
    static let warning = Color(red: 0.86, green: 0.66, blue: 0.22)
    static let danger = Color(red: 0.92, green: 0.28, blue: 0.30)
    static let medical = Color(red: 0.94, green: 0.38, blue: 0.56)
    static let logistics = Color(red: 0.48, green: 0.74, blue: 0.48)
    static let review = Color(red: 0.72, green: 0.56, blue: 0.90)
    static let textOnColor = Color.white
    static let pagePadding: CGFloat = 16
    static let panelSpacing: CGFloat = 12
}

private extension ICSSection {
    var title: String {
        switch self {
        case .command: return "指揮"
        case .operations: return "作戰"
        case .planning: return "計畫"
        case .logistics: return "後勤"
        case .finance: return "財務"
        case .medical: return "醫療"
        case .afterActionReview: return "復盤"
        }
    }

    var systemImage: String {
        switch self {
        case .command: return "person.badge.key.fill"
        case .operations: return "map.fill"
        case .planning: return "brain.head.profile"
        case .logistics: return "shippingbox.fill"
        case .finance: return "dollarsign.circle.fill"
        case .medical: return "cross.case.fill"
        case .afterActionReview: return "clock.arrow.circlepath"
        }
    }

    var accent: Color {
        switch self {
        case .command: return LifelineTheme.command
        case .operations: return LifelineTheme.info
        case .planning: return LifelineTheme.warning
        case .logistics: return LifelineTheme.logistics
        case .finance: return LifelineTheme.green
        case .medical: return LifelineTheme.medical
        case .afterActionReview: return LifelineTheme.review
        }
    }
}

private extension FeatureAccessLevel {
    var title: String {
        switch self {
        case .none: return "未開放"
        case .limited: return "有限權限"
        case .primary: return "完整權限"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "xmark.circle.fill"
        case .limited: return "circle.lefthalf.filled"
        case .primary: return "checkmark.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .none: return .secondary
        case .limited: return LifelineTheme.warning
        case .primary: return LifelineTheme.green
        }
    }
}
