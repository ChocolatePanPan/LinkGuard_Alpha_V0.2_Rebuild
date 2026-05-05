import SwiftUI
#if os(macOS)
import AppKit
#endif


// MARK: - 指揮中心主介面

enum HQSection: String, CaseIterable, Identifiable {
    case dashboard = "儀表板"
    case grandDashboard = "大儀表板"
    case disaster = "災害狀態"
    case personnelOverview = "人員總覽"
    case victimOverview = "受困者總覽"
    case personnel = "人員配置"
    case chat = "通訊頻道"
    case call = "通話"
    case pws = "PWS 警報"
    case briefing = "會報系統"
    case notification = "個人通知"
    case timeline = "事件日誌"
    case zonemap = "分區地圖"
    case reports = "會報儀表板"
    case decision = "指揮決策"
    case photoWall = "照片牆"
    case stats = "統計儀表板"
    case resources = "資源管理"
    case broadcast = "文字廣播"
    case radio = "電台監聽"
    case patientWarning = "傷患預警"
    case aiChat = "AI 對話"
    case backendServices = "後端服務"
    case decisionHistory = "AI 決策歷史"
    case fireDepartments = "消防局聯絡簿"
    case hospitals = "後送醫院"
    case settings = "設定"

    static let navigationOrder: [HQSection] = [
        .dashboard,
        .grandDashboard,
        .disaster,
        .personnelOverview,
        .victimOverview,
        .personnel,
        .zonemap,
        .resources,
        .photoWall,
        .chat,
        .call,
        .broadcast,
        .radio,
        .pws,
        .patientWarning,
        .briefing,
        .notification,
        .timeline,
        .reports,
        .stats,
        .decision,
        .aiChat,
        .decisionHistory,
        .backendServices,
        .fireDepartments,
        .hospitals,
        .settings
    ]

    var id: String { rawValue }

    var localizedName: String { L(rawValue) }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .grandDashboard: return "square.grid.3x3.fill"
        case .disaster: return "building.2"
        case .personnelOverview: return "person.3.sequence.fill"
        case .victimOverview: return "person.fill.questionmark"
        case .personnel: return "person.badge.plus"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .call: return "phone.fill"
        case .pws: return "exclamationmark.triangle.fill"
        case .briefing: return "doc.text.fill"
        case .notification: return "bell.fill"
        case .timeline: return "clock.arrow.circlepath"
        case .zonemap: return "map.fill"
        case .reports: return "doc.richtext"
        case .decision: return "brain.head.profile"
        case .photoWall: return "photo.on.rectangle.angled"
        case .stats: return "chart.bar.xaxis"
        case .resources: return "shippingbox"
        case .broadcast: return "megaphone.fill"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .patientWarning: return "heart.text.square"
        case .aiChat: return "sparkles"
        case .backendServices: return "cpu"
        case .decisionHistory: return "clock.arrow.circlepath"
        case .fireDepartments: return "flame.fill"
        case .hospitals: return "cross.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum HQNavigationPlacement: String, CaseIterable, Identifiable {
    case left
    case bottom
    case right

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .left: return L("左側")
        case .bottom: return L("下方")
        case .right: return L("右側")
        }
    }

    var icon: String {
        switch self {
        case .left: return "sidebar.left"
        case .bottom: return "rectangle.bottomthird.inset.filled"
        case .right: return "sidebar.right"
        }
    }
}

struct HQDashboardView: View {
    @ObservedObject var vm: HQViewModel
    @EnvironmentObject var l10n: L10n
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.navigationPlacement") private var navigationPlacementRaw: String = HQNavigationPlacement.left.rawValue
    @AppStorage("hq.splitEnabled") private var splitEnabled = false
    @AppStorage("hq.splitSecondSection") private var splitSecondSectionRaw: String = HQSection.chat.rawValue
    @State private var selectedSection: HQSection? = .dashboard
    @State private var sidebarExpanded = true
    // 任務指派表單
    @State private var taskTitle = ""
    @State private var taskDetail = ""
    @State private var taskAssigneeID = ""
    @State private var taskAssigneeName = ""
    @State private var taskZone = ""
    // 計時器表單
    @State private var timerTitle = ""
    @State private var timerMinutes = ""
    @State private var sosFlash = false
    @State private var localIPText = "IP: --"
    @State private var shouldRevealBottomNavigationSelection = false

    private static let sosTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let bottomNavigationItemWidth: CGFloat = 86
    private static let bottomNavigationItemHeight: CGFloat = 54
    private static let bottomNavigationBarHeight: CGFloat = 74
    private static let bottomNavigationSpacing: CGFloat = 8

    private var navigationPlacement: HQNavigationPlacement {
        HQNavigationPlacement(rawValue: navigationPlacementRaw) ?? .left
    }

    private var sidebarToggleIcon: String {
        navigationPlacement == .right ? "sidebar.right" : "sidebar.left"
    }

    private var selectedSectionValue: HQSection {
        selectedSection ?? .dashboard
    }

    private var isAbsoluteBlackMode: Bool {
        appColorScheme == "black"
    }

    private var usesDarkNavigationChrome: Bool {
        isAbsoluteBlackMode || appColorScheme == "dark" || colorScheme == .dark
    }

    var body: some View {
        ZStack {
            navigationLayout
            .animation(.easeInOut(duration: 0.2), value: sidebarExpanded)
            .animation(.easeInOut(duration: 0.2), value: navigationPlacement)

            // SOS 全螢幕警報覆蓋
            if vm.showSOSOverlay {
                sosOverlayView
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .onChange(of: vm.showSOSOverlay) { show in
            if show {
                sosFlash = true
                HQAlarmPlayer.shared.playSOSAlarm()
            } else {
                sosFlash = false
                HQAlarmPlayer.shared.stopAlarm()
            }
        }
        .onDisappear {
            HQAlarmPlayer.shared.stopAlarm()
        }
        .onAppear {
            localIPText = localIPAddress()
        }
        .overlay(alignment: .topLeading) {
            if navigationPlacement == .bottom {
                bottomNavigationKeyboardShortcuts
            }
        }
    }

    @ViewBuilder
    private var navigationLayout: some View {
        switch navigationPlacement {
        case .left:
            HStack(spacing: 0) {
                navigationPane(edge: .leading)
                Divider()
                centeredDetailContent
            }
        case .right:
            HStack(spacing: 0) {
                centeredDetailContent
                Divider()
                navigationPane(edge: .trailing)
            }
        case .bottom:
            VStack(spacing: 0) {
                centeredDetailContent
                Divider()
                bottomNavigationBar
            }
        }
    }

    private var centeredDetailContent: some View {
        Group {
            if splitEnabled, let second = HQSection(rawValue: splitSecondSectionRaw) {
                HStack(spacing: 0) {
                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Divider()
                    secondPanelContent(for: second)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(NV.pageBackground(appColorScheme: appColorScheme, colorScheme: colorScheme).ignoresSafeArea())
    }

    @ViewBuilder
    private func secondPanelContent(for section: HQSection) -> some View {
        switch section {
        case .dashboard: dashboardDetailView
        case .grandDashboard: HQGrandDashboardView(vm: vm)
        case .disaster: HQDisasterView(vm: vm)
        case .personnelOverview: HQPersonnelOverviewView(vm: vm)
        case .victimOverview: HQVictimOverviewView(vm: vm)
        case .personnel: HQPersonnelView(vm: vm)
        case .chat: HQChatView(vm: vm)
        case .call: HQCallView(vm: vm)
        case .pws: HQPWSView(vm: vm)
        case .briefing: HQBriefingView(vm: vm)
        case .notification: HQNotificationView(vm: vm)
        case .timeline: HQTimelineView(vm: vm)
        case .zonemap: HQZoneMapView(vm: vm)
        case .reports: HQReportsDashboardView(vm: vm)
        case .decision: HQDecisionView(vm: vm)
        case .photoWall: HQPhotoWallView(vm: vm)
        case .stats: HQStatsDashboardView(vm: vm)
        case .resources: HQResourceView(vm: vm)
        case .broadcast: HQBroadcastView(vm: vm)
        case .radio: HQRadioView(vm: vm)
        case .patientWarning: HQPatientWarningView(vm: vm)
        case .aiChat: HQAIChatView(vm: vm)
        case .backendServices:
            #if os(macOS)
            HQBackendServicesView(vm: vm, supervisor: vm.backendSupervisor)
            #else
            Text(L("僅 macOS 支援")).foregroundColor(.secondary)
            #endif
        case .decisionHistory: HQDecisionHistoryView(vm: vm)
        case .fireDepartments: HQFireDepartmentDirectoryView(vm: vm)
        case .hospitals: HQHospitalDirectoryView(vm: vm)
        case .settings:
            #if os(macOS)
            HQSettingsView(vm: vm, supervisor: vm.backendSupervisor) {
                selectedSection = .backendServices
            }
            #else
            Text(L("僅 macOS 支援")).foregroundColor(.secondary)
            #endif
        }
    }

    private var bottomNavigationKeyboardShortcuts: some View {
        Group {
            Button(action: selectPreviousSection) { EmptyView() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(action: selectNextSection) { EmptyView() }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func selectPreviousSection() {
        selectAdjacentSection(offset: -1)
    }

    private func selectNextSection() {
        selectAdjacentSection(offset: 1)
    }

    private func selectAdjacentSection(offset: Int) {
        guard navigationPlacement == .bottom,
              let currentIndex = HQSection.navigationOrder.firstIndex(of: selectedSectionValue) else { return }
        let sections = HQSection.navigationOrder
        let nextIndex = (currentIndex + offset + sections.count) % sections.count
        shouldRevealBottomNavigationSelection = true
        selectedSection = sections[nextIndex]
    }

    @ViewBuilder
    private var navigationChromeBackground: some View {
        NV.navigationBackground(appColorScheme: appColorScheme, colorScheme: colorScheme)
    }

    private func navigationSelectionFill(for section: HQSection) -> Color {
        NV.navigationSelectionFill(appColorScheme: appColorScheme, colorScheme: colorScheme, accent: sectionColor(section))
    }

    private func navigationSelectionStroke(for section: HQSection) -> Color {
        isAbsoluteBlackMode ? Color.white.opacity(0.30) : sectionColor(section).opacity(usesDarkNavigationChrome ? 0.42 : 0.28)
    }

    private func navigationForeground(for section: HQSection, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return usesDarkNavigationChrome ? sectionColor(section).opacity(0.90).mix(with: .white, by: 0.30) : sectionColor(section)
    }

    @ViewBuilder
    private func navigationPane(edge: Edge) -> some View {
        if sidebarExpanded {
            sidebarView
                .frame(width: 260)
                .transition(.move(edge: edge))
        } else {
            collapsedSidebar
                .frame(width: 56)
                .transition(.move(edge: edge))
        }
    }

    // MARK: - SOS 全螢幕警報

    private var sosOverlayView: some View {
        ZStack {
            // 閃爍紅色背景
            NV.danger.opacity(sosFlash ? 0.35 : 0.15)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: sosFlash)

            VStack(spacing: 24) {
                Spacer()

                // 圖示 + 標題
                Image(systemName: "sos")
                    .font(.system(size: 80))
                    .foregroundColor(NV.danger)
                    .scaleEffect(sosFlash ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: sosFlash)

                Text(L("SOS 緊急警報"))
                    .font(.system(size: 42, weight: .black))
                    .foregroundColor(.white)

                // 警報列表
                VStack(spacing: 12) {
                    ForEach(vm.activeSOSAlerts) { alert in
                        HStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundColor(NV.danger)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.senderName)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text(L("裝置: %@", alert.deviceID))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                if alert.lat != 0 || alert.lon != 0 {
                                    Text(L("座標: %.5f, %.5f", alert.lat, alert.lon))
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }

                            Spacer()

                            Text(Self.sosTimeFormatter.string(from: alert.timestamp))
                                .font(.title3.monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))

                            Button {
                                vm.dismissSOSAlert(alert.id)
                            } label: {
                                Text(L("解除"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(6)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                    }
                }
                .frame(maxWidth: 600)

                Spacer()

                // 確認按鈕
                Button {
                    vm.acknowledgeSOSOverlay()
                } label: {
                    Text(L("確認警報（保持追蹤）"))
                        .font(.title3.bold())
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(NV.danger)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
        }
        .onAppear { sosFlash = true }
    }

    private var detailContent: some View {
        Group {
            switch selectedSection {
            case .dashboard: dashboardDetailView
            case .grandDashboard: HQGrandDashboardView(vm: vm)
            case .disaster: HQDisasterView(vm: vm)
            case .personnelOverview: HQPersonnelOverviewView(vm: vm)
            case .victimOverview: HQVictimOverviewView(vm: vm)
            case .personnel: HQPersonnelView(vm: vm)
            case .chat: HQChatView(vm: vm)
            case .call: HQCallView(vm: vm)
            case .pws: HQPWSView(vm: vm)
            case .briefing: HQBriefingView(vm: vm)
            case .notification: HQNotificationView(vm: vm)
            case .timeline: HQTimelineView(vm: vm)
            case .zonemap: HQZoneMapView(vm: vm)
            case .reports: HQReportsDashboardView(vm: vm)
            case .decision: HQDecisionView(vm: vm)
            case .photoWall: HQPhotoWallView(vm: vm)
            case .stats: HQStatsDashboardView(vm: vm)
            case .resources: HQResourceView(vm: vm)
            case .broadcast: HQBroadcastView(vm: vm)
            case .radio: HQRadioView(vm: vm)
            case .patientWarning: HQPatientWarningView(vm: vm)
            case .aiChat: HQAIChatView(vm: vm)
            #if os(macOS)
            case .backendServices: HQBackendServicesView(vm: vm, supervisor: vm.backendSupervisor)
            #else
            case .backendServices: Text(L("僅 macOS 支援")).foregroundColor(.secondary)
            #endif
            case .decisionHistory: HQDecisionHistoryView(vm: vm)
            case .fireDepartments: HQFireDepartmentDirectoryView(vm: vm)
            case .hospitals: HQHospitalDirectoryView(vm: vm)
            #if os(macOS)
            case .settings: HQSettingsView(vm: vm, supervisor: vm.backendSupervisor) {
                selectedSection = .backendServices
            }
            #else
            case .settings: Text(L("僅 macOS 支援")).foregroundColor(.secondary)
            #endif
            case nil: dashboardDetailView
            }
        }
    }

    // MARK: - 收合側邊欄（純圖示）

    private var collapsedSidebar: some View {
        VStack(spacing: 0) {
            // Logo
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            // 功能圖示
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(HQSection.navigationOrder) { section in
                        Button {
                            shouldRevealBottomNavigationSelection = false
                            selectedSection = section
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(navigationForeground(for: section, isSelected: selectedSection == section))
                                    .frame(width: 36, height: 36)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selectedSection == section ? navigationSelectionFill(for: section) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selectedSection == section ? navigationSelectionStroke(for: section) : Color.clear, lineWidth: NV.strokeWidth)
                                    }
                                collapsedBadge(for: section)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(section.localizedName)
                    }

                    Divider().padding(.vertical, 6).padding(.horizontal, 8)

                    // 伺服器狀態
                    Image(systemName: (vm.server.isRunning || vm.peerClient.isConnected) ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 16))
                        .foregroundColor((vm.server.isRunning || vm.peerClient.isConnected) ? NV.green : .gray)
                        .frame(width: 36, height: 36)
                        .help(vm.systemStatus.text)

                    // 前線裝置數
                    let fieldCount = vm.hqRole == .peer ? vm.peerFieldUnitCount : vm.server.fieldUnits.count
                    if fieldCount > 0 {
                        Text("\(fieldCount)")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(NV.green)
                            .cornerRadius(12)
                            .help(L("前線裝置: %lld", fieldCount))
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()

            // 展開按鈕
            Button {
                sidebarExpanded = true
            } label: {
                Image(systemName: sidebarToggleIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .help(L("展開側邊欄"))
            .padding(.bottom, 8)
        }
        .background { navigationChromeBackground }
    }

    @ViewBuilder
    private func collapsedBadge(for section: HQSection) -> some View {
        switch section {
        case .chat:
            if !vm.chatMessages.isEmpty {
                Circle().fill(NV.info).frame(width: 8, height: 8).offset(x: 2, y: -2)
            }
        case .pws:
            if vm.pwsAlerts.filter(\.isActive).count > 0 {
                Circle().fill(NV.danger).frame(width: 8, height: 8).offset(x: 2, y: -2)
            }
        case .notification:
            if !vm.personalNotifications.isEmpty {
                Circle().fill(NV.warning).frame(width: 8, height: 8).offset(x: 2, y: -2)
            }
        case .timeline:
            if !vm.timelineEvents.isEmpty {
                Circle().fill(NV.info).frame(width: 8, height: 8).offset(x: 2, y: -2)
            }
        case .photoWall:
            if !vm.photoAlerts.isEmpty {
                Circle().fill(NV.info).frame(width: 8, height: 8).offset(x: 2, y: -2)
            }
        default: EmptyView()
        }
    }

    // MARK: - 側邊欄

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                // Logo
                Section {
                    HStack(spacing: 10) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LinkGuard")
                                .font(.title3).bold()
                            Text(L("地震救援指揮系統"))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

            // 功能選單
            Section(header: Text(L("功能"))) {
                ForEach(HQSection.navigationOrder) { section in
                    Label {
                        HStack {
                            Text(section.localizedName)
                            Spacer()
                            badgeView(for: section)
                        }
                    } icon: {
                        Image(systemName: section.icon)
                            .foregroundColor(sectionColor(section))
                    }
                    .tag(section)
                }
            }

            // 伺服器 / 連接 模式
            Section(header: Text(L("指揮網路"))) {
                Picker(L("角色"), selection: Binding(
                    get: { vm.hqRole },
                    set: { vm.switchRole($0) }
                )) {
                    ForEach(HQViewModel.HQRole.allCases, id: \.self) { role in
                        Text(L(role.rawValue)).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)

                if vm.hqRole == .server {
                    // ----- Mac 指揮中心模式 -----
                    HStack {
                        Image(systemName: vm.server.isRunning
                              ? "antenna.radiowaves.left.and.right"
                              : "antenna.radiowaves.left.and.right.slash")
                            .foregroundColor(vm.server.isRunning ? NV.green : .gray)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.server.isRunning ? L("運行中") : L("已停止"))
                                .font(.headline)
                            Text("Port 8930 · Bonjour")
                                .font(.caption2).foregroundColor(.secondary)
                            if vm.server.isRunning {
                                Text(localIPText)
                                    .font(.caption2)
                                    .foregroundColor(NV.green)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Button(vm.server.isRunning ? L("停止") : L("啟動")) {
                            vm.toggleServer()
                            localIPText = localIPAddress()
                        }
                        .font(.caption).bold()
                        .buttonStyle(.bordered)
                        .tint(vm.server.isRunning ? NV.danger : NV.green)
                    }
                    // 已連線 HQ 同伴列表
                    if !vm.server.hqPeers.isEmpty {
                        ForEach(vm.server.hqPeers) { peer in
                            HStack(spacing: 8) {
                                Image(systemName: "display.2")
                                    .foregroundColor(NV.info)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(peer.peerName)
                                        .font(.caption).bold()
                                    Text(peer.peerID)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Circle().fill(NV.green).frame(width: 8, height: 8)
                            }
                        }
                    }
                } else {
                    // ----- 副指揮連接模式 -----
                    if vm.peerClient.isConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(NV.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("已連線")).font(.headline)
                                Text(vm.peerClient.connectedServerName)
                                    .font(.caption2).foregroundColor(NV.green)
                            }
                            Spacer()
                            Button(L("中斷")) {
                                vm.peerClient.disconnect()
                            }
                            .font(.caption).bold()
                            .buttonStyle(.bordered)
                            .tint(NV.danger)
                        }
                    } else {
                        // 搜尋中 / 搜尋按鈕
                        HStack {
                            if vm.peerClient.isSearching {
                                ProgressView().controlSize(.small)
                                Text(L("搜尋中…")).font(.caption).foregroundColor(.secondary)
                            } else {
                                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                                Text(L("尋找指揮中心")).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(vm.peerClient.isSearching ? L("停止") : L("搜尋")) {
                                if vm.peerClient.isSearching { vm.peerClient.stopBrowsing() }
                                else { vm.peerClient.startBrowsing() }
                            }
                            .font(.caption).bold()
                            .buttonStyle(.bordered)
                        }
                        // 已發現的伺服器列表
                        ForEach(vm.peerClient.discoveredServers) { srv in
                            Button {
                                vm.peerClient.connect(to: srv)
                            } label: {
                                HStack {
                                    Image(systemName: "wifi").foregroundColor(NV.info)
                                    Text(srv.name).font(.caption)
                                    Spacer()
                                    Text(L("連線")).font(.caption2).foregroundColor(NV.info)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // 連線總覽
            Section(header: Text(L("總覽"))) {
                HStack {
                    Label(L("前線裝置"), systemImage: "iphone.radiowaves.left.and.right")
                    Spacer()
                    Text("\(vm.connectedCount)/\(vm.hqRole == .peer ? vm.peerFieldUnitCount : vm.server.fieldUnits.count)").bold()
                }
                HStack {
                    Label(L("受困者"), systemImage: "person.wave.2")
                    Spacer()
                    Text("\(vm.onlineVictimCount)/\(vm.totalVictimCount)").bold()
                }
                HStack {
                    Label("SOS", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(vm.sosCount > 0 ? NV.danger : .secondary)
                    Spacer()
                    Text("\(vm.sosCount)").bold()
                        .foregroundColor(vm.sosCount > 0 ? NV.danger : .primary)
                }
                HStack {
                    Label(L("團隊節點"), systemImage: "person.3.fill")
                    Spacer()
                    Text("\(vm.teamCount)").bold()
                }
            }

            // 前線裝置列表
            if vm.hqRole == .peer, let status = vm.peerClient.serverStatus {
                Section(header: Text(L("前線裝置 (%lld)", status.fieldUnitCount))) {
                    if status.fieldUnits.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "iphone.slash")
                                    .font(.title2).foregroundColor(.secondary)
                                Text(L("等待連線…"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }.padding()
                    } else {
                        ForEach(status.fieldUnits) { unit in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(unit.isOnline ? NV.green : .gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.deviceID)
                                        .font(.caption).bold()
                                    Text(unit.deptCode)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if unit.sosCount > 0 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(NV.danger)
                                        .font(.caption)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "battery.\(min(100, max(0, unit.battery)))")
                                        .font(.caption2)
                                    Text("\(unit.battery)%")
                                        .font(.caption2)
                                        .foregroundColor(unit.battery < 20 ? NV.danger : .secondary)
                                }
                                if unit.bleConnected {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.caption2)
                                        .foregroundColor(NV.info)
                                }
                            }
                        }
                    }
                }
            } else {
                Section(header: Text(L("前線裝置 (%lld)", vm.server.fieldUnits.count))) {
                    if vm.server.fieldUnits.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "iphone.slash")
                                    .font(.title2).foregroundColor(.secondary)
                                Text(vm.server.isRunning ? L("等待連線…") : L("啟動伺服器"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }.padding()
                    } else {
                        ForEach(vm.server.fieldUnits) { unit in
                            FieldUnitRow(unit: unit)
                        }
                    }
                }
            }
        }
        
        // 底部收合按鈕
        HStack {
            Button {
                sidebarExpanded = false
            } label: {
                Image(systemName: sidebarToggleIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .help(L("收合側邊欄"))
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)

        }
        .background { navigationChromeBackground }
    }

    private var bottomNavigationBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.bottomNavigationSpacing) {
                    ForEach(HQSection.navigationOrder) { section in
                        bottomNavigationButton(for: section)
                            .id(section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedSectionValue) { section in
                if shouldRevealBottomNavigationSelection {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(section)
                    }
                    shouldRevealBottomNavigationSelection = false
                }
            }
        }
        .frame(height: Self.bottomNavigationBarHeight)
        .background { navigationChromeBackground }
    }

    private func bottomNavigationButton(for section: HQSection) -> some View {
        Button {
            shouldRevealBottomNavigationSelection = false
            selectedSection = section
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: section.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 30, height: 24)
                    badgeView(for: section)
                        .scaleEffect(0.82)
                        .offset(x: 14, y: -6)
                }
                Text(section.localizedName)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(navigationForeground(for: section, isSelected: selectedSection == section))
            .frame(width: Self.bottomNavigationItemWidth, height: Self.bottomNavigationItemHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedSection == section ? navigationSelectionFill(for: section) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selectedSection == section ? navigationSelectionStroke(for: section) : Color.clear, lineWidth: NV.strokeWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.localizedName)
    }

    @ViewBuilder
    private func badgeView(for section: HQSection) -> some View {
        switch section {
        case .personnelOverview:
            Text("\(vm.teamCount)")
                .font(.caption2).bold()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(NV.team.opacity(NV.tagOpacity))
                .cornerRadius(NV.tagRadius)
        case .victimOverview:
            let count = vm.totalVictimCount
            if count > 0 {
                Text("\(count)")
                    .font(.caption2).bold()
                    .foregroundColor(vm.sosCount > 0 ? .white : .primary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(vm.sosCount > 0 ? NV.danger : NV.warning.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)
            }
        case .chat:
            if !vm.chatMessages.isEmpty {
                Text("\(vm.chatMessages.count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.info.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)
            }
        case .pws:
            let active = vm.pwsAlerts.filter(\.isActive).count
            if active > 0 {
                Text("\(active)")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.danger)
                    .cornerRadius(NV.tagRadius)
            }
        case .notification:
            if !vm.personalNotifications.isEmpty {
                Text("\(vm.personalNotifications.count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.warning.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)
            }
        case .timeline:
            if !vm.timelineEvents.isEmpty {
                Text("\(vm.timelineEvents.count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.info.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)
            }
        case .photoWall:
            if !vm.photoAlerts.isEmpty {
                Text("\(vm.photoAlerts.count)")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.info)
                    .cornerRadius(NV.tagRadius)
            }
        default: EmptyView()
        }
    }

    private func sectionColor(_ section: HQSection) -> Color {
        switch section {
        case .dashboard: return NV.green
        case .grandDashboard: return NV.command
        case .disaster: return NV.warning
        case .personnelOverview: return NV.team
        case .victimOverview: return NV.warning
        case .personnel: return NV.info
        case .chat: return NV.command
        case .call: return NV.command
        case .pws: return NV.danger
        case .briefing: return NV.team
        case .notification: return NV.reinforce
        case .timeline: return NV.info
        case .zonemap: return NV.green
        case .reports: return NV.command
        case .decision: return NV.command
        case .photoWall: return NV.info
        case .stats: return NV.team
        case .resources: return NV.green
        case .broadcast: return NV.danger
        case .radio: return NV.green
        case .patientWarning: return NV.warning
        case .aiChat: return NV.command
        case .backendServices: return NV.green
        case .decisionHistory: return NV.command
        case .fireDepartments: return NV.danger
        case .hospitals: return NV.info
        case .settings: return NV.info
        }
    }

    // MARK: - 儀表板詳細區：命令表單 + 快速命令 + 資料總覽

    private var dashboardDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // SOS 持續警示橫幅
                if !vm.activeSOSAlerts.isEmpty && !vm.showSOSOverlay {
                    Button {
                        vm.showSOSOverlay = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sos")
                                .font(.title2)
                            Text(L("%lld 個 SOS 警報進行中", vm.activeSOSAlerts.count))
                                .font(.headline.bold())
                            Spacer()
                            Text(L("點擊查看"))
                                .font(.caption)
                                .opacity(0.8)
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(NV.danger)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                HQPageTitleBar(L("儀表板"), subtitle: L("地震救援指揮系統 · 命令發布面板"), icon: "gauge.with.dots.needle.33percent", accent: NV.green) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(vm.systemStatus.color)
                            .frame(width: NV.dotSize, height: NV.dotSize)
                        Text(vm.systemStatus.text)
                            .font(.caption)
                            .foregroundColor(vm.systemStatus.color)
                    }
                }
                .padding(.horizontal)

                // 統計卡片
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                     GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    HQStatCard(title: L("前線裝置"), value: "\(vm.connectedCount)",
                               icon: "iphone.radiowaves.left.and.right", color: NV.green)
                    HQStatCard(title: L("受困者"), value: "\(vm.totalVictimCount)",
                               icon: "person.wave.2", color: NV.info)
                    HQStatCard(title: "SOS", value: "\(vm.sosCount)",
                               icon: "exclamationmark.triangle.fill", color: NV.danger)
                    HQStatCard(title: L("已發命令"), value: "\(vm.commandHistory.count)",
                               icon: "megaphone.fill", color: NV.command)
                    HQStatCard(title: L("PWS 警報"), value: "\(vm.pwsAlerts.filter(\.isActive).count)",
                               icon: "exclamationmark.shield", color: NV.warning)
                    HQStatCard(title: L("人員配置"), value: "\(vm.personnelAssignments.count)",
                               icon: "person.3.fill", color: NV.team)
                    HQStatCard(title: L("通訊"), value: "\(vm.chatMessages.count)",
                               icon: "bubble.left.and.bubble.right.fill", color: NV.info)
                    HQStatCard(title: L("會報"), value: "\(vm.briefings.count)",
                               icon: "doc.text.fill", color: NV.reinforce)
                    HQStatCard(title: L("任務"), value: "\(vm.activeTaskCount)",
                               icon: "checklist", color: NV.warning)
                    HQStatCard(title: L("後台"), value: vm.isBackendConnected ? L("已連線") : L("離線"),
                               icon: "server.rack", color: vm.isBackendConnected ? NV.green : .gray)
                }
                .padding(.horizontal)

                // 上下分割：命令表單 + 快速命令
                HStack(alignment: .top, spacing: 16) {
                    // 左：命令表單
                    commandFormPanel
                    // 右：快速命令
                    quickCommandPanel
                }
                .padding(.horizontal)

                // 任務指派 + 計時器
                HStack(alignment: .top, spacing: 16) {
                    taskAssignmentPanel
                    timerManagementPanel
                }
                .padding(.horizontal)

                // 快速狀態回報 + 危險標記
                HStack(alignment: .top, spacing: 16) {
                    quickStatusFeedPanel
                    hazardReportsPanel
                }
                .padding(.horizontal)

                // 增援請求
                reinforcementPanel
                    .padding(.horizontal)

                // HQ LoRa 連線
                loraPanel
                    .padding(.horizontal)

                // 受困者總覽
                victimOverviewPanel
                    .padding(.horizontal)
            }
            .padding(.top, NV.pagePadding)
            .padding(.bottom)
        }
    }

    // MARK: - 命令表單

    private var commandFormPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("發送命令"), systemImage: "megaphone.fill")
                .font(.headline)

            // 類型
            Picker(L("類型"), selection: $vm.selectedType) {
                ForEach(CommandType.allCases, id: \.self) { type in
                    Label(L(type.rawValue), systemImage: type.icon).tag(type)
                }
            }

            // 優先等級
            Picker(L("優先等級"), selection: $vm.selectedPriority) {
                ForEach(CommandPriority.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)

            // 標題
            TextField(L("命令標題"), text: $vm.commandTitle)
                .textFieldStyle(.roundedBorder)

            // 詳情
            TextField(L("命令詳情（選填）"), text: $vm.commandDetail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            // 發送者
            HStack {
                Text(L("發送者"))
                    .font(.caption).foregroundColor(.secondary)
                TextField(L("代號"), text: $vm.senderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            // PADOS 目標選擇
            DeviceTargetSelector(
                targetMode: $vm.targetMode,
                selectedIDs: $vm.selectedTargetDeviceIDs,
                fieldUnits: vm.server.fieldUnits
            )

            // 發送按鈕
            Button {
                vm.sendCustomCommand()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(vm.targetMode == .broadcast ? L("廣播命令") : L("發送至 %lld 台裝置", vm.selectedTargetDeviceIDs.count))
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.warning)
            .disabled(!vm.canSendCommand)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 快速命令

    private var quickCommandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("快速命令"), systemImage: "bolt.fill")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(quickCommands) { qc in
                    Button {
                        vm.sendQuickCommand(qc)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: qc.icon)
                                .font(.caption)
                            Text(L(qc.title))
                                .font(.caption).bold()
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(qc.color)
                    .disabled(!vm.isHQActive)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 任務指派

    private var taskAssignmentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("任務指派"), systemImage: "checklist")
                .font(.headline)

            TextField(L("任務標題"), text: $taskTitle)
                .textFieldStyle(.roundedBorder)
            TextField(L("任務詳情（選填）"), text: $taskDetail)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField(L("指派對象 ID"), text: $taskAssigneeID)
                    .textFieldStyle(.roundedBorder)
                TextField(L("對象名稱"), text: $taskAssigneeName)
                    .textFieldStyle(.roundedBorder)
            }
            TextField(L("區域"), text: $taskZone)
                .textFieldStyle(.roundedBorder)

            Button {
                let task = TaskAssignment(
                    title: taskTitle, detail: taskDetail,
                    assigneeID: taskAssigneeID.isEmpty ? "ALL" : taskAssigneeID,
                    assigneeName: taskAssigneeName.isEmpty ? taskAssigneeID : taskAssigneeName,
                    zone: taskZone
                )
                vm.assignTask(task)
                taskTitle = ""; taskDetail = ""; taskAssigneeID = ""; taskAssigneeName = ""; taskZone = ""
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(L("指派任務")).bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.warning)
            .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.isHQActive)

            // 待處理任務列表
            if !vm.tasks.filter(\.isActive).isEmpty {
                Divider()
                ForEach(vm.tasks.filter(\.isActive)) { task in
                    HStack {
                        Circle().fill(task.taskStatus.color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.caption).bold()
                            Text("\(task.assigneeName) · \(task.taskStatus.label)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { vm.cancelTask(task.id) } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 計時器管理

    private var timerManagementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("倒數計時器"), systemImage: "timer")
                .font(.headline)

            HStack {
                TextField(L("計時器名稱"), text: $timerTitle)
                    .textFieldStyle(.roundedBorder)
                TextField(L("分鐘"), text: $timerMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Button {
                let mins = Int(timerMinutes) ?? 5
                vm.startTimer(title: timerTitle.isEmpty ? "計時器" : timerTitle, durationSeconds: mins * 60)
                timerTitle = ""; timerMinutes = ""
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(L("啟動計時器")).bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.warning)
            .disabled(!vm.isHQActive)

            // 快速計時器
            HStack(spacing: 8) {
                ForEach([5, 10, 15, 30], id: \.self) { mins in
                    Button(L("%lld 分", mins)) {
                        vm.startTimer(title: L("%lld 分鐘計時", mins), durationSeconds: mins * 60)
                    }
                    .buttonStyle(.bordered)
                    .tint(NV.info)
                    .disabled(!vm.isHQActive)
                }
            }

            // 進行中計時器
            if !vm.countdownTimers.isEmpty {
                Divider()
                ForEach(vm.countdownTimers) { timer in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timer.title).font(.caption).bold()
                            Text(timer.isExpired ? L("已到期") : L("剩餘 %@", timer.remainingText))
                                .font(.caption2)
                                .foregroundColor(timer.isExpired ? NV.danger : .secondary)
                        }
                        Spacer()
                        Text(timer.remainingText)
                            .font(.title3).bold().monospacedDigit()
                            .foregroundColor(timer.remainingSeconds < 60 ? NV.danger : NV.warning)
                        Button { vm.cancelTimer(timer.id) } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 快速狀態回報動態

    private var quickStatusFeedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("前線狀態回報"), systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                .font(.headline)

            if vm.quickStatuses.isEmpty {
                Text(L("尚無回報"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(vm.quickStatuses.prefix(8)) { status in
                    HStack(spacing: 8) {
                        if let type = status.statusType {
                            Image(systemName: type.icon)
                                .foregroundColor(type.color)
                                .frame(width: 20)
                            Text(type.label)
                                .font(.caption).bold()
                                .foregroundColor(type.color)
                        }
                        Text(status.senderName)
                            .font(.caption2).foregroundColor(.secondary)
                        if !status.zone.isEmpty {
                            Text("· \(status.zone)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(status.timeText)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 危險標記回報

    private var hazardReportsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("危險標記 (%lld)", vm.hazardReports.count), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)

            if vm.hazardReports.isEmpty {
                Text(L("尚無危險回報"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(vm.hazardReports.prefix(6)) { hazard in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(hazard.severityLevel.color)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hazard.hazard?.label ?? hazard.hazardType)
                                .font(.caption).bold()
                            Text("\(hazard.reporterName) · \(hazard.zone.isEmpty ? "未知" : hazard.zone)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(hazard.severityLevel.label)
                            .font(.caption2).bold()
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .foregroundColor(hazard.severityLevel.color)
                            .background(hazard.severityLevel.color.opacity(0.15))
                            .cornerRadius(4)
                        Text(hazard.timeText)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 受困者總覽

    private var victimOverviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("受困者即時狀態 (彙整)"), systemImage: "person.wave.2")
                .font(.headline)

            if vm.server.allVictims.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title).foregroundColor(.secondary)
                        Text(L("尚未收到前線裝置回報…"))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                }.padding()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                     GridItem(.flexible())], spacing: 8) {
                    ForEach(vm.server.allVictims) { v in
                        VictimSummaryCard(victim: v)
                    }
                }
            }
        }
        .padding()
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 增援請求管理

    private var reinforcementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("增援請求 (%lld)", vm.reinforcementRequests.count), systemImage: "person.3.sequence.fill")
                    .font(.headline)
                Spacer()
                if vm.pendingReinforcementCount > 0 {
                    Text(L("%lld 待處理", vm.pendingReinforcementCount))
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundColor(NV.textOnColor)
                        .background(NV.reinforce)
                        .cornerRadius(NV.tagRadius)
                }
            }

            if vm.reinforcementRequests.isEmpty {
                Text(L("尚無增援請求"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(vm.reinforcementRequests.prefix(8)) { request in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(request.fromTeam)
                                .font(.caption).bold()
                            Spacer()
                            Text(request.status.label)
                                .font(.caption2).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundColor(NV.textOnColor)
                                .background(request.status.color)
                                .cornerRadius(4)
                            Text(request.timeText)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Text(request.message)
                            .font(.caption).foregroundColor(.secondary)
                        if !request.location.isEmpty {
                            Text(L("位置：%@", request.location))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        if !request.respondedBy.isEmpty {
                            Text(L("回覆：%@", request.respondedBy.joined(separator: ", ")))
                                .font(.caption2).foregroundColor(.secondary)
                        }

                        if request.status == .pending {
                            HStack(spacing: 8) {
                                Button {
                                    vm.approveReinforcement(request)
                                } label: {
                                    Label(L("批准"), systemImage: "checkmark.circle.fill")
                                        .font(.caption).bold()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(NV.green)

                                Button {
                                    vm.declineReinforcement(request)
                                } label: {
                                    Label(L("拒絕"), systemImage: "xmark.circle.fill")
                                        .font(.caption).bold()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(NV.danger)
                            }
                        }
                    }
                    .padding(NV.cardPadding)
                    .background(request.status == .pending ? NV.reinforce.opacity(0.08) : Color.clear)
                    .cornerRadius(NV.cardRadius)
                    if request.id != vm.reinforcementRequests.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - HQ LoRa 連線

    private var loraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("HQ LoRa 通訊 (910 MHz)"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(vm.bluetoothManager.isConnected ? NV.green : .gray)
                    .frame(width: NV.dotSize, height: NV.dotSize)
                Text(vm.bluetoothManager.isConnected
                     ? (vm.bluetoothManager.connectedDeviceName ?? "已連接")
                     : "未連接")
                    .font(.caption)
                    .foregroundColor(vm.bluetoothManager.isConnected ? NV.green : .secondary)
            }

            if vm.bluetoothManager.isConnected, let status = vm.bluetoothManager.loraStatus {
                // 連線狀態
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("節點 ID")).font(.caption2).foregroundColor(.secondary)
                        Text(status.id).font(.caption).bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("頻率")).font(.caption2).foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", status.freq)) MHz").font(.caption).bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("配對碼")).font(.caption2).foregroundColor(.secondary)
                        Text(status.pair).font(.caption).bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("LoRa 檔位")).font(.caption2).foregroundColor(.secondary)
                        Text("L\(status.lvl)").font(.caption).bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("電池")).font(.caption2).foregroundColor(.secondary)
                        Text("\(status.bat)%").font(.caption).bold()
                            .foregroundColor(status.bat < 20 ? NV.danger : NV.green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("運行時間")).font(.caption2).foregroundColor(.secondary)
                        Text(formatUptime(status.uptime)).font(.caption).bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("已發命令")).font(.caption2).foregroundColor(.secondary)
                        Text("\(status.cmdCount)").font(.caption).bold()
                    }
                }

                // HQ 節點列表
                if !status.hqNodes.isEmpty {
                    Divider()
                    Text(L("HQ LoRa 節點 (%lld)", status.hqNodes.count))
                        .font(.caption).bold()
                    ForEach(status.hqNodes) { node in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(node.online ? NV.green : .gray)
                                .frame(width: 8, height: 8)
                            Text(node.id).font(.caption).bold()
                            Spacer()
                            Text("\(node.bat)%").font(.caption2)
                                .foregroundColor(node.bat < 20 ? NV.danger : .secondary)
                            Text("\(Int(node.rssi)) dBm").font(.caption2).foregroundColor(.secondary)
                            Text("SNR \(String(format: "%.1f", node.snr))").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                // 收到的 LoRa 命令
                if !vm.loraReceivedCommands.isEmpty {
                    Divider()
                    Text(L("收到的 LoRa 命令")).font(.caption).bold()
                    ForEach(vm.loraReceivedCommands.prefix(5), id: \.cmd_id) { cmd in
                        HStack {
                            Text(cmd.title).font(.caption).bold()
                            Spacer()
                            Text("from \(cmd.sender)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

            } else {
                // 未連接：掃描/連線 UI
                if vm.bluetoothManager.isScanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L("正在掃描 HQ LoRa 裝置...")).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button(L("停止")) { vm.bluetoothManager.stopScanning() }
                            .font(.caption).buttonStyle(.bordered)
                    }
                    ForEach(vm.bluetoothManager.discoveredDevices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).font(.caption).bold()
                                Text("RSSI: \(device.rssi) dBm").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L("連線")) { vm.bluetoothManager.connect(to: device) }
                                .font(.caption).buttonStyle(.borderedProminent).tint(NV.green)
                        }
                    }
                } else {
                    HStack {
                        Text(L("透過藍牙連接 HQ LoRa 模組（Heltec WiFi LoRa 32 V3）"))
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button(L("掃描")) { vm.bluetoothManager.startScanning() }
                            .font(.caption).buttonStyle(.borderedProminent).tint(NV.command)
                        if vm.bluetoothManager.isConnected {
                            Button(L("中斷")) { vm.bluetoothManager.disconnect() }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding()
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    private func formatUptime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(s)s"
    }

    private func localIPAddress() -> String {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return L("IP: 未知") }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var addr = ptr.pointee.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    getnameinfo(sockPtr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                }
            }
            let ip = String(cString: hostname)
            if !ip.isEmpty && ip != "127.0.0.1" {
                addresses.append(ip)
            }
        }
        return addresses.isEmpty ? "IP: 未偵測到 WiFi" : "IP: \(addresses.joined(separator: ", "))"
    }
}

// MARK: - 子視圖

struct HQStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2).bold()
            Text(L(title))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: NV.statCardMinHeight, alignment: .leading)
        .hqPanelChrome(accent: color)
    }
}

struct FieldUnitRow: View {
    let unit: ConnectedFieldUnit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: unit.bleConnected ? "iphone.radiowaves.left.and.right" : "iphone")
                .foregroundColor(unit.isOnline ? NV.green : .gray)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(unit.deviceID)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(unit.deptCode)
                        .font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(NV.team.opacity(NV.tagOpacity))
                        .cornerRadius(NV.tagRadius)
                    Text(L("%lld 受困者", unit.victims.count))
                        .font(.caption2).foregroundColor(.secondary)
                    if unit.sosCount > 0 {
                        Text("SOS:\(unit.sosCount)")
                            .font(.caption2).bold()
                            .foregroundColor(NV.danger)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "battery.25").font(.caption2)
                    Text("\(unit.battery)%").font(.caption2)
                }
                .foregroundColor(unit.battery <= 20 ? NV.danger : .secondary)
                Text(unit.isOnline ? L("線上") : L("離線"))
                    .font(.caption2)
                    .foregroundColor(unit.isOnline ? NV.green : .gray)
            }
        }
        .padding(.vertical, 2)
    }
}

struct VictimSummaryCard: View {
    let victim: VictimSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: victim.isSOS ? "sos" : "person.fill")
                    .foregroundColor(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray))
                Text(victim.id)
                    .font(.headline)
                Spacer()
                if victim.isSOS {
                    Text("SOS")
                        .font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .foregroundColor(.white)
                        .background(NV.danger)
                        .cornerRadius(4)
                }
            }
            HStack(spacing: 12) {
                Label(victim.heartRate > 0 ? "\(victim.heartRate) bpm" : "-- bpm",
                      systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundColor(victim.heartRate > 0 ? NV.heartRate : .secondary)
                Label("\(Int(victim.rssi)) dBm",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2).foregroundColor(.secondary)
                Label("\(victim.battery)%", systemImage: "battery.25")
                    .font(.caption2)
                    .foregroundColor(victim.battery <= 20 ? NV.danger : .secondary)
            }
        }
        .padding(NV.cardPadding)
        .background(victim.isSOS ? NV.danger.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(victim.isSOS ? NV.danger.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: NV.strokeWidth)
        )
        .cornerRadius(NV.cardRadius)
    }
}
