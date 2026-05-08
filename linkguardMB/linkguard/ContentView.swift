import SwiftUI

// MARK: - Main View

enum AppTab: Hashable {
    case dashboard, victims, sos, disaster, chat, reinforcement, team, commands, notifications, radio, connection, patientForm, nfcReader, decision, translator, photo, personnelAssignment, ai, communication, hospitals
}

struct ContentView: View {
    @StateObject private var viewModel = LinkGuardViewModel()
    @EnvironmentObject private var l10n: L10n
    @State private var selectedTab: AppTab = .dashboard
    @State private var cameFromDashboard = false
    @State private var externalAlarm: ExternalAlarmPresentation?

    private func navLabel(_ zh: String, en: String) -> String {
        l10n.language.hasPrefix("en") ? en : zh
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                    Tab(L("總覽"), systemImage: "gauge.with.dots.needle.33percent", value: AppTab.dashboard) {
                        DashboardView(vm: viewModel, selectedTab: $selectedTab, cameFromDashboard: $cameFromDashboard)
                    }
                    TabSection("AI") {
                        Tab("AI", systemImage: viewModel.isAIServicePaused ? "pause.circle" : "sparkles", value: AppTab.ai) {
                            AIHubView(vm: viewModel)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    TabSection(navLabel("通訊", en: "Messages")) {
                        Tab(L("通知"), systemImage: "bell.fill", value: AppTab.notifications) {
                            FieldNotificationView(vm: viewModel)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .badge(viewModel.unreadNotificationCount)
                        Tab(navLabel("通訊", en: "Comms"), systemImage: "antenna.radiowaves.left.and.right", value: AppTab.communication) {
                            CommunicationHubView(vm: viewModel)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .badge(viewModel.chatMessages.count)
                    }
                    Tab(L("災情"), systemImage: "building.2", value: AppTab.disaster) {
                        FieldDisasterView(vm: viewModel)
                            .navigationTitle(L("全區災情概況"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                    Tab("SOS", systemImage: "sos.circle.fill", value: AppTab.sos) {
                        SOSRecordListView(vm: viewModel)
                            .navigationTitle(L("SOS 警報"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                    .badge(viewModel.unacknowledgedSOSCount)
                    Tab(navLabel("指揮命令", en: "Orders"), systemImage: "brain.head.profile", value: AppTab.decision) {
                        DecisionView(vm: viewModel)
                            .navigationTitle(L("指揮決策"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                    .badge(viewModel.decisions.count + viewModel.unreadCommandCount)
                    TabSection(L("其他")) {
                        Tab(L("受困者"), systemImage: "person.fill.questionmark", value: AppTab.victims) {
                            VictimListView(vm: viewModel)
                                .navigationTitle(L("受困者列表"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("增援"), systemImage: "person.badge.plus", value: AppTab.reinforcement) {
                            ReinforcementListView(vm: viewModel)
                                .navigationTitle(L("增援請求"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        .badge(viewModel.pendingReinforcementCount)
                        Tab(L("團隊"), systemImage: "person.3.sequence.fill", value: AppTab.team) {
                            TeamListView(vm: viewModel)
                                .navigationTitle(L("分隊通訊群組"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("人員指派"), systemImage: "person.badge.key.fill", value: AppTab.personnelAssignment) {
                            PersonnelAssignmentView(vm: viewModel)
                                .navigationTitle(L("人員指派"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("傷員回報"), systemImage: "heart.text.square", value: AppTab.patientForm) {
                            PatientFormView(vm: viewModel)
                                .navigationTitle(L("傷員回報"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("NFC 讀取"), systemImage: "wave.3.right.circle.fill", value: AppTab.nfcReader) {
                            NFCReaderView(vm: viewModel)
                                .navigationTitle(L("NFC 讀取"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("翻譯"), systemImage: "globe", value: AppTab.translator) {
                            TranslatorView(vm: viewModel)
                                .navigationTitle(L("翻譯"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("後送醫院"), systemImage: "cross.fill", value: AppTab.hospitals) {
                            FieldHospitalView()
                                .navigationTitle(L("後送醫院"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                    }
                    TabSection(navLabel("工具", en: "Tools")) {
                        Tab(L("照片"), systemImage: "photo.on.rectangle.angled", value: AppTab.photo) {
                            PhotoReportView(vm: viewModel)
                                .navigationTitle(L("照片/影片回報"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                        Tab(L("設定"), systemImage: "gearshape", value: AppTab.connection) {
                            ConnectionView(vm: viewModel)
                                .navigationTitle(L("設定"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(.visible, for: .navigationBar)
                        }
                    }
            }
            .id("tabview-lang-\(l10n.language)")
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == .dashboard {
                    cameFromDashboard = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .linkGuardNotificationRouteRequested)) { notification in
                handleNotificationRoute(notification)
            }

            // 返回主頁浮動按鈕
            if cameFromDashboard && selectedTab != .dashboard && selectedTab != .victims {
                VStack {
                    HStack {
                        Button {
                            selectedTab = .dashboard
                            cameFromDashboard = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.bold())
                                Text(L("主頁"))
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(NV.green), in: .capsule)
                        }
                        .padding(.leading, 16)
                        .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(50)
            }

            // 全螢幕指揮命令覆蓋層
            if let command = viewModel.latestCriticalCommand {
                CommandAlertOverlay(command: command) {
                    viewModel.dismissCommandAlert()
                }
                .transition(.opacity)
                .zIndex(99)
            }

            // 全螢幕增援請求覆蓋層
            if let request = viewModel.latestReinforcementRequest {
                ReinforcementAlertOverlay(
                    request: request,
                    onAccept: { viewModel.acceptReinforcement(request) },
                    onDecline: { viewModel.declineReinforcement(request) }
                )
                .transition(.opacity)
                .zIndex(98)
            }

            // 全螢幕 SOS 警報覆蓋層
            if let victim = viewModel.latestSOSVictim {
                SOSAlertOverlay(victim: victim) {
                    viewModel.dismissSOSAlert()
                }
                .transition(.opacity)
                .zIndex(100)
            }

            // 緊急廣播覆蓋層
            if let broadcast = viewModel.urgentBroadcast {
                UrgentBroadcastOverlay(broadcast: broadcast) {
                    viewModel.dismissUrgentBroadcast()
                }
                .transition(.opacity)
                .zIndex(97)
            }

            // 傷患惡化預警覆蓋層
            if let warning = viewModel.activePatientWarning {
                PatientWarningOverlay(warning: warning) {
                    viewModel.dismissPatientWarning()
                }
                .transition(.opacity)
                .zIndex(96)
            }

            if let alarm = externalAlarm {
                ExternalAlarmOverlay(
                    alarm: alarm,
                    onAcknowledge: { externalAlarm = nil },
                    onOpenDetails: {
                        selectedTab = alarm.targetTab
                        externalAlarm = nil
                    }
                )
                .transition(.opacity)
                .zIndex(101)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.latestSOSVictim != nil)
        .animation(.easeInOut(duration: 0.3), value: viewModel.latestCriticalCommand != nil)
        .animation(.easeInOut(duration: 0.3), value: viewModel.latestReinforcementRequest != nil)
        .animation(.easeInOut(duration: 0.3), value: viewModel.urgentBroadcast != nil)
        .animation(.easeInOut(duration: 0.3), value: viewModel.activePatientWarning != nil)
        .animation(.easeInOut(duration: 0.3), value: externalAlarm != nil)
        .dismissKeyboardOnBlankTap()
    }

    private func handleNotificationRoute(_ notification: Notification) {
        guard let route = notification.userInfo?["route"] as? String else { return }
        let alarm = ExternalAlarmPresentation(
            route: route,
            title: notification.userInfo?["title"] as? String ?? L("LinkGuard 警報"),
            subtitle: notification.userInfo?["subtitle"] as? String ?? "",
            body: notification.userInfo?["body"] as? String ?? "",
            categoryIdentifier: notification.userInfo?["categoryIdentifier"] as? String ?? ""
        )
        selectedTab = alarm.targetTab
        externalAlarm = alarm
    }
}

struct ExternalAlarmPresentation: Identifiable, Equatable {
    let id = UUID()
    let route: String
    let title: String
    let subtitle: String
    let body: String
    let categoryIdentifier: String

    var targetTab: AppTab {
        switch route {
        case "sos": return .sos
        case "decision": return .decision
        case "victims": return .victims
        default: return .notifications
        }
    }

    var iconName: String {
        switch categoryIdentifier {
        case "SOS_ALERT": return "sos"
        case "COMMAND_ORDER", "DECISION": return "exclamationmark.triangle.fill"
        case "PATIENT_WARNING": return "waveform.path.ecg"
        case "PWS_ALERT": return "antenna.radiowaves.left.and.right"
        default: return "bell.badge.fill"
        }
    }
}

struct ExternalAlarmOverlay: View {
    let alarm: ExternalAlarmPresentation
    let onAcknowledge: () -> Void
    let onOpenDetails: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            NV.danger
                .opacity(pulse ? 0.85 : 0.96)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: alarm.iconName)
                    .font(.system(size: 80))
                    .foregroundColor(NV.textOnColor)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

                Text(alarm.title)
                    .font(.largeTitle).bold()
                    .foregroundColor(NV.textOnColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    if !alarm.subtitle.isEmpty {
                        Text(alarm.subtitle)
                            .font(.title2).bold()
                            .foregroundColor(NV.textOnColor)
                    }

                    Text(alarm.body.isEmpty ? L("請立即查看 LinkGuard 警報內容") : alarm.body)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(NV.textOnColor)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(NV.danger.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(NV.textOnColor.opacity(0.55), lineWidth: 2)
                )
                .cornerRadius(20)
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 16) {
                    Button(action: onAcknowledge) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.title2)
                            Text(L("收到")).font(.title2).bold()
                        }
                        .foregroundColor(NV.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(NV.textOnColor)
                        .cornerRadius(16)
                    }

                    Button(action: onOpenDetails) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill").font(.title2)
                            Text(L("查看詳情")).font(.title2).bold()
                        }
                        .foregroundColor(NV.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(NV.textOnColor)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 40)
            }
        }
        .onAppear { pulse = true }
    }
}

struct CommunicationHubView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @EnvironmentObject private var l10n: L10n
    @State private var mode: CommunicationHubMode = .message
    @AppStorage("commSplitEnabled") private var commSplitEnabled = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isSplitMode: Bool { commSplitEnabled && sizeClass == .regular }

    private enum CommunicationHubMode: Hashable, CaseIterable {
        case message, live, report
    }

    private func navLabel(_ zh: String, en: String) -> String {
        l10n.language.hasPrefix("en") ? en : zh
    }

    private func modeTitle(_ mode: CommunicationHubMode) -> String {
        switch mode {
        case .message: return navLabel("訊息", en: "Message")
        case .live: return navLabel("即時廣播", en: "Live Broadcast")
        case .report: return navLabel("語音會報", en: "Voice Briefing")
        }
    }

    var body: some View {
        NavigationStack {
            if isSplitMode {
                splitContent
            } else {
                VStack(spacing: 0) {
                    Picker(L("通訊"), selection: $mode) {
                        ForEach(CommunicationHubMode.allCases, id: \.self) { item in
                            Text(modeTitle(item)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    Divider()

                    Group {
                        switch mode {
                        case .message:
                            FieldChatView(vm: vm, embedsNavigationStack: false, showsNavigationTitle: false, showsKeyboardDone: true)
                        case .live:
                            RadioView(vm: vm, initialMode: .live, showsModePicker: false, embedsNavigationStack: false)
                        case .report:
                            RadioView(vm: vm, initialMode: .briefing, showsModePicker: false, embedsNavigationStack: false)
                        }
                    }
                }
                .navigationTitle(modeTitle(mode))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
    }

    private var splitContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(L("即時廣播"))
                    .font(.headline)
                    .padding(.vertical, 8)
                Divider()
                RadioView(vm: vm, initialMode: .live, showsModePicker: false, embedsNavigationStack: false)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 0) {
                Text(L("訊息"))
                    .font(.headline)
                    .padding(.vertical, 8)
                Divider()
                FieldChatView(vm: vm, embedsNavigationStack: false, showsNavigationTitle: false, showsKeyboardDone: true)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("通訊"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct AIHubView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @EnvironmentObject private var l10n: L10n
    @State private var mode: AIHubMode = .communication

    private enum AIHubMode: Hashable, CaseIterable {
        case communication, assistant, report
    }

    private func navLabel(_ zh: String, en: String) -> String {
        l10n.language.hasPrefix("en") ? en : zh
    }

    private func modeTitle(_ mode: AIHubMode) -> String {
        switch mode {
        case .communication: return navLabel("通訊", en: "Comms")
        case .assistant: return navLabel("助理", en: "Assistant")
        case .report: return navLabel("回報", en: "Report")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("AI", selection: $mode) {
                    ForEach(AIHubMode.allCases, id: \.self) { item in
                        Text(modeTitle(item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)

                Divider()

                Group {
                    switch mode {
                    case .communication:
                        RadioView(vm: vm, initialMode: .aiChat, showsModePicker: false, embedsNavigationStack: false)
                    case .assistant:
                        FieldAIChatView(vm: vm)
                    case .report:
                        FieldAIReportView(vm: vm)
                    }
                }
            }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab
    @Binding var cameFromDashboard: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showHandoverSummary = false
    @State private var showQuickGuide = false

    private var isWide: Bool { sizeClass == .regular }
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: isWide ? 4 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 標題列
                    HStack {
                        VStack(alignment: .leading) {
                            Text("LinkGuard")
                                .font(.largeTitle).bold()
                            Text(L("地震救援指揮系統"))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                // 快速操作手冊按鈕
                                Button {
                                    showQuickGuide = true
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title3)
                                        .foregroundColor(NV.info)
                                }
                                Circle()
                                    .fill(vm.systemStatus.color)
                                    .frame(width: 10, height: 10)
                                Text(vm.systemStatus.text)
                                    .font(.caption)
                                    .foregroundColor(vm.systemStatus.color)
                            }
                            if vm.commandClient.isConnected {
                                HStack(spacing: 8) {
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(vm.commandClient.hqServerStatus?.audioStreamRunning == true ? NV.green : .gray)
                                            .frame(width: 7, height: 7)
                                        Text(L("串流伺服器"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(vm.commandClient.hqServerStatus?.udpServerRunning == true ? NV.green : .gray)
                                            .frame(width: 7, height: 7)
                                        Text("UDP Server")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding([.horizontal, .bottom])

                    // 統計卡片（iPad 4欄，iPhone 2欄）
                    GlassEffectContainer(spacing: 8) {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            StatCard(title: L("受困者"),
                                     value: "\(vm.onlineVictimCount)/\(vm.victims.count)",
                                     icon: "person.wave.2")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .victims }
                            StatCard(title: L("已回報傷患"),
                                     value: "\(vm.localPatients.count)",
                                     icon: "heart.text.square")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .victims }
                            StatCard(title: "SOS",
                                     value: "\(vm.sosVictimCount)",
                                     icon: "sos.circle.fill")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .sos }
                            StatCard(title: L("團隊"),
                                     value: "\(vm.onlineTeamCount)/\(vm.teamMembers.count)",
                                     icon: "person.3.fill")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .team }
                            StatCard(title: L("增援"),
                                     value: "\(vm.pendingReinforcementCount)",
                                     icon: "person.badge.plus")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .reinforcement }
                            StatCard(title: L("訊息"),
                                     value: "\(vm.chatMessages.count)",
                                     icon: "bubble.left.and.bubble.right.fill")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .communication }
                            StatCard(title: L("命令"),
                                     value: "\(vm.unreadCommandCount)",
                                     icon: "megaphone.fill")
                            .onTapGesture { cameFromDashboard = true; selectedTab = .decision }
                            StatCard(title: L("任務"),
                                     value: "\(vm.activeTaskCount)",
                                     icon: "checklist")
                        }
                    }
                    .padding(.horizontal)

                    // 節點狀態列
                    HStack(spacing: 12) {
                        Image(systemName: vm.isBluetoothConnected ? "bluetooth.connected" : "bluetooth")
                            .foregroundColor(vm.isBluetoothConnected ? NV.green : .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.isBluetoothConnected
                                 ? "已連接：\(vm.bluetoothDeviceName ?? vm.nodeStatus.nodeID)"
                                 : L("藍牙未連接"))
                                .font(.caption)
                            Text("LoRa \(vm.nodeStatus.loraProfile.label)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if vm.isSimulating {
                            Text(L("模擬模式"))
                                .font(.caption2).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .glassEffect(.regular.tint(NV.simulation))
                        }
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.horizontal)

                    // 快速狀態回報
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("快速狀態回報"))
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(QuickStatusType.allCases, id: \.rawValue) { type in
                                Button {
                                    vm.sendQuickStatus(type)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: type.icon)
                                        Text(type.label)
                                            .font(.subheadline).bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .tint(type.color)
                                .buttonStyle(.borderedProminent)
                                .disabled(!vm.commandClient.isConnected)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // SOS 緊急按鈕
                    VStack(spacing: 10) {
                        if vm.isSOSActive {
                            Button {
                                vm.cancelSOS()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(L("取消 SOS"))
                                        .font(.headline).bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .tint(.orange)
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                vm.sendSOS()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sos.circle.fill")
                                    Text(L("SOS 緊急呼叫"))
                                        .font(.headline).bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .tint(.red)
                            .buttonStyle(.borderedProminent)
                            .disabled(!vm.commandClient.isConnected)
                        }
                    }
                    .padding(.horizontal)

                    // 全員撤離警報（連線 HQ 時顯示）
                    if vm.commandClient.isConnected {
                        EvacuationAlertButton(vm: vm)
                            .padding(.horizontal)
                    }

                    // 倒數計時器
                    if !vm.countdownTimers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("倒數計時器"))
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(vm.countdownTimers) { timer in
                                HStack {
                                    Image(systemName: "timer")
                                        .foregroundColor(timer.remainingSeconds < 60 ? NV.danger : NV.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(timer.title)
                                            .font(.subheadline).bold()
                                        Text(timer.isExpired ? L("已到期") : L("剩餘 %@", timer.remainingText))
                                            .font(.caption)
                                            .foregroundColor(timer.isExpired ? NV.danger : .secondary)
                                    }
                                    Spacer()
                                    Text(timer.remainingText)
                                        .font(.title2).bold().monospacedDigit()
                                        .foregroundColor(timer.remainingSeconds < 60 ? NV.danger : NV.warning)
                                }
                                .padding()
                                .glassEffect(.regular.tint(timer.remainingSeconds < 60 ? NV.danger.opacity(0.2) : .clear), in: .rect(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    }

                    // 待處理任務
                    if !vm.tasks.filter(\.isActive).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("待處理任務 (%lld)", vm.activeTaskCount))
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(vm.tasks.filter(\.isActive)) { task in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Circle().fill(task.taskStatus.color).frame(width: 8, height: 8)
                                            Text(task.title).font(.subheadline).bold()
                                        }
                                        if !task.detail.isEmpty {
                                            Text(task.detail)
                                                .font(.caption).foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        Text("\(task.taskStatus.label) · \(task.timeText)")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if task.taskStatus == .pending {
                                        Button(L("接受")) {
                                            vm.updateTaskStatus(task.id, newStatus: .accepted)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(NV.green)
                                        .controlSize(.small)
                                    } else if task.taskStatus == .accepted || task.taskStatus == .inProgress {
                                        Menu {
                                            Button(L("執行中")) { vm.updateTaskStatus(task.id, newStatus: .inProgress) }
                                            Button(L("已完成")) { vm.updateTaskStatus(task.id, newStatus: .completed) }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                        }
                                    }
                                }
                                .padding()
                                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    }

                    // 危險標記警示
                    if !vm.hazardReports.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("危險標記 (%lld)", vm.hazardReports.count))
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(vm.hazardReports.prefix(3)) { hazard in
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(hazard.severityLevel.color)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hazard.hazard?.label ?? hazard.hazardType)
                                            .font(.subheadline).bold()
                                        if !hazard.description.isEmpty {
                                            Text(hazard.description)
                                                .font(.caption).foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("\(hazard.reporterName) · \(hazard.zone.isEmpty ? L("未知區域") : hazard.zone) · \(hazard.timeText)")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(hazard.severityLevel.label)
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .foregroundColor(NV.textOnColor)
                                        .glassEffect(.regular.tint(hazard.severityLevel.color), in: .rect(cornerRadius: 6))
                                }
                                .padding()
                                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    }

                    // 受困者即時狀態（iPad 顯示全部，用 Grid；iPhone 顯示前 3 個）
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("受困者即時狀態"))
                            .font(.headline)
                            .padding(.horizontal)

                        if vm.victims.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.title).foregroundColor(.secondary)
                                    Text(L("尚未發現受困者..."))
                                        .font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                            }.padding()
                        } else if isWide {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(vm.victims) { victim in
                                    VictimRow(victim: victim)
                                        .padding(12)
                                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            ForEach(vm.victims.prefix(3)) { victim in
                                VictimRow(victim: victim)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    // 已回報傷患（表單填寫的詳細傷患資料）
                    if !vm.localPatients.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L("已回報傷患"))
                                    .font(.headline)
                                Spacer()
                                Text("\(vm.localPatients.count)")
                                    .font(.caption).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .glassEffect(.regular.tint(NV.command), in: .capsule)
                                Button {
                                    cameFromDashboard = true
                                    selectedTab = .victims
                                } label: {
                                    Text(L("全部"))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(NV.info)
                            }
                            .padding(.horizontal)

                            ForEach(vm.localPatients.suffix(3).reversed()) { patient in
                                PatientReportRow(patient: patient)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                                    .padding(.horizontal)
                            }
                        }
                    }

                    // 交班摘要
                    Button {
                        showHandoverSummary = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text(L("產生交班摘要"))
                                .bold()
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                    .tint(.primary)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .sheet(isPresented: $showHandoverSummary) {
                HandoverSummarySheet(vm: vm)
            }
            .sheet(isPresented: $showQuickGuide) {
                QuickGuideView()
            }
        }
    }
}

// MARK: - 全員撤離警報

struct EvacuationAlertButton: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                vm.sendHQQuickCommand(
                    type: "evacuation",
                    priority: 2,
                    title: L("全員撤離"),
                    detail: L("發布撤離命令，所有人員立即撤離至集結點"),
                    sender: "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("全員撤離"))
                            .font(.headline).bold()
                        Text(L("通知所有人立即撤離"))
                            .font(.caption)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.danger)
        }
    }
}

// MARK: - 統計卡片

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            Text(value)
                .font(.title2).bold()
            Text(title)
                .font(.caption).foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 110)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - 交班摘要

struct HandoverSummarySheet: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var summaryText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(summaryText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(L("交班摘要"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("關閉")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = summaryText
                        #elseif canImport(AppKit)
                        NSPasteboard.general.setString(summaryText, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            .onAppear { summaryText = vm.generateHandoverSummary() }
        }
    }
}

// MARK: - Victim List

struct VictimListView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        List {
            // 裝置受困者：BLE/LoRa 偵測到的心率/SOS 訊號
            Section {
                if vm.victims.isEmpty {
                    Text(L("尚未發現受困者..."))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(vm.victims) { victim in
                        NavigationLink(destination: VictimDetailView(victim: victim)) {
                            VictimRow(victim: victim)
                        }
                    }
                }
            } header: {
                Label(L("裝置受困者（即時訊號）"), systemImage: "antenna.radiowaves.left.and.right")
            }

            // 已回報傷患：搜救人員填表上傳的詳細傷患資料
            Section {
                if vm.localPatients.isEmpty {
                    Text(L("尚未回報傷患..."))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(vm.localPatients.reversed()) { patient in
                        NavigationLink(destination: PatientReportDetailView(patient: patient)) {
                            PatientReportRow(patient: patient)
                        }
                    }
                }
            } header: {
                Label(L("已回報傷患（表單填寫）"), systemImage: "heart.text.square")
            }
        }
        .outerNavigationTitle(L("受困者列表"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(vm.victims.count + vm.localPatients.count)")
                    .font(.subheadline.bold())
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

// MARK: - 已回報傷患 Row / Detail

private struct PatientReportRow: View {
    let patient: PatientReport

    private var priorityInfo: (label: String, color: Color) {
        // 重現後端 START 邏輯（簡化版）作為前線速判
        if patient.breathingRate == -1 { return (L("黑色"), .gray) }
        if patient.breathingRate > 30 || patient.capillaryRefill > 2 { return (L("紅色"), NV.danger) }
        if !patient.canFollowCommands { return (L("黃色"), NV.warning) }
        return (L("綠色"), NV.green)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title3)
                    .foregroundColor(priorityInfo.color)
                Text(priorityInfo.label)
                    .font(.caption2).bold()
                    .foregroundColor(priorityInfo.color)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(patient.name.isEmpty ? patient.patientId : patient.name)
                        .font(.subheadline).bold()
                    if let age = patient.age {
                        Text("· \(age)\(L("歲"))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Text(patient.location.isEmpty ? L("位置未填") : patient.location)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(patient.breathingRate == -1 ? L("無呼吸") : "\(patient.breathingRate)/min",
                          systemImage: "lungs.fill")
                        .font(.caption2)
                    if !patient.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(NV.info)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PatientReportDetailView: View {
    let patient: PatientReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(patient.name.isEmpty ? patient.patientId : patient.name)
                        .font(.title2).bold()
                    HStack(spacing: 8) {
                        if !patient.nationalId.isEmpty {
                            Text(patient.nationalId).font(.caption).foregroundColor(.secondary)
                        }
                        if !patient.birthDate.isEmpty {
                            Text(patient.birthDate).font(.caption).foregroundColor(.secondary)
                        }
                        if let age = patient.age {
                            Text("\(age)\(L("歲"))").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DetailStatCard(icon: "lungs.fill", title: L("呼吸速率"),
                                   value: patient.breathingRate == -1 ? L("無呼吸") : "\(patient.breathingRate)/min")
                    DetailStatCard(icon: "drop.fill", title: L("微血管回填"),
                                   value: patient.capillaryRefill == -1 ? L("無脈搏") : String(format: "%.1fs", patient.capillaryRefill))
                    DetailStatCard(icon: "person.fill.questionmark", title: L("意識"),
                                   value: patient.canFollowCommands ? L("可聽令") : L("無法聽令"))
                    DetailStatCard(icon: "mappin.and.ellipse", title: L("位置"),
                                   value: patient.location.isEmpty ? "—" : patient.location)
                }
                .padding(.horizontal)

                if let lat = patient.gpsLat, let lon = patient.gpsLon {
                    HStack {
                        Image(systemName: "location.fill").foregroundColor(NV.info)
                        Text(String(format: "GPS: %.5f, %.5f", lat, lon))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.horizontal)
                }

                if !patient.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("備註"), systemImage: "note.text")
                            .font(.headline)
                        Text(patient.notes)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(patient.name.isEmpty ? patient.patientId : patient.name)
    }
}

struct VictimDetailView: View {
    let victim: VictimNode

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 狀態頭部
                VStack(spacing: 12) {
                    Image(systemName: victim.isSOS ? "sos" : "person.fill")
                        .font(.system(size: 48))
                        .foregroundColor(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray))
                        .frame(width: 80, height: 80)
                        .glassEffect(
                            .regular.tint(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray)),
                            in: .circle
                        )
                    Text(victim.id)
                        .font(.title).bold()
                    HStack(spacing: 8) {
                        Text(victim.isOnline ? L("線上") : L("離線"))
                            .font(.caption).bold()
                            .foregroundColor(victim.isOnline ? NV.green : .gray)
                        if victim.isSOS {
                            Text("SOS")
                                .font(.caption).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundColor(NV.textOnColor)
                                .glassEffect(.regular.tint(NV.danger), in: .rect(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 24)

                // 詳細資訊 Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    DetailStatCard(icon: "heart.fill", title: L("心率"),
                                   value: victim.heartRateText)
                    DetailStatCard(icon: "location.fill", title: L("估計距離"),
                                   value: "~\(victim.distanceText)")
                    DetailStatCard(icon: "antenna.radiowaves.left.and.right", title: "RSSI",
                                   value: "\(Int(victim.rssi)) dBm")
                    DetailStatCard(icon: "chart.bar.fill", title: "SNR",
                                   value: String(format: "%.1f dB", victim.snr))
                    DetailStatCard(icon: "battery.50", title: L("電量"),
                                   value: "\(victim.battery)%")
                    DetailStatCard(icon: "clock", title: L("最後更新"),
                                   value: victim.lastSeenText)
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(victim.id)
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

struct DetailStatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(value)
                .font(.title3).bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .padding(.horizontal)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

struct VictimRow: View {
    let victim: VictimNode

    var body: some View {
        HStack(spacing: 12) {
            // 狀態指示
            Image(systemName: victim.isSOS ? "sos" : "person.fill")
                .foregroundColor(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray))
                .font(.system(size: 16))
                .frame(width: 40, height: 40)
                .glassEffect(
                    .regular.tint(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray)),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(victim.id).font(.headline)
                    if victim.isSOS {
                        Text("SOS")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundColor(NV.textOnColor)
                            .glassEffect(.regular.tint(NV.danger), in: .rect(cornerRadius: 4))
                    }
                }
                HStack(spacing: 8) {
                    // 心率
                    Label(victim.heartRateText, systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(victim.heartRate > 0 ? NV.heartRate : .secondary)
                    // 距離
                    Label("~\(victim.distanceText)", systemImage: "location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(victim.isOnline ? L("線上") : L("離線"))
                    .font(.caption2).bold()
                    .foregroundColor(victim.isOnline ? NV.green : .gray)
                Text("\(Int(victim.rssi)) dBm")
                    .font(.caption2)
                    .foregroundColor(victim.signalColor)
                HStack(spacing: 2) {
                    Image(systemName: "battery.25")
                        .font(.caption2)
                    Text("\(victim.battery)%")
                        .font(.caption2)
                }
                .foregroundColor(victim.battery <= 20 ? NV.danger : .secondary)
                Text(victim.lastSeenText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SOS Record List

struct SOSRecordListView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        List {
            if vm.sosRecords.isEmpty {
                Section {
                    Text(L("目前沒有 SOS 紀錄"))
                        .foregroundColor(.secondary)
                }
            } else {
                Section(header: Text(L("SOS 紀錄"))) {
                    ForEach(vm.sosRecords) { record in
                        SOSRecordRow(record: record) {
                            vm.acknowledgeRecord(record)
                        }
                    }
                }
            }
        }
        .outerNavigationTitle(L("SOS 警報"))
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

struct SOSRecordRow: View {
    let record: SOSRecord
    var onAcknowledge: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isAcknowledged
                  ? "checkmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .foregroundColor(record.isAcknowledged ? NV.green : NV.danger)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle).font(.headline)
                HStack(spacing: 4) {
                    Text(record.timeText)
                    Text("·")
                    Text(record.heartRate > 0 ? "\(record.heartRate) bpm" : "-- bpm")
                    Text("·")
                    Text("~\(record.distance)")
                }
                .font(.caption).foregroundColor(.secondary)

                if !record.message.isEmpty {
                    SOSRecordInfoLine(icon: "text.bubble", text: record.message)
                }

                if !record.locationDescription.isEmpty {
                    SOSRecordInfoLine(icon: "mappin.and.ellipse", text: record.locationDescription)
                }

                if let coordinateText = record.coordinateText {
                    SOSRecordInfoLine(icon: "location", text: coordinateText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(Int(record.rssi)) dBm")
                    .font(.caption2).foregroundColor(.secondary)

                if !record.isAcknowledged {
                    Button(L("確認")) { onAcknowledge?() }
                        .font(.caption2).bold()
                        .buttonStyle(.glass)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SOSRecordInfoLine: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(2)
    }
}

// MARK: - 指揮中心命令列表

struct CommandListView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        List {
            if vm.commandOrders.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "megaphone")
                                .font(.title).foregroundColor(.secondary)
                            Text(L("等待指揮中心命令..."))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else {
                Section(header: Text(L("指揮命令"))) {
                    ForEach(vm.commandOrders) { order in
                        CommandOrderRow(order: order) {
                            vm.markCommandAsRead(order)
                        }
                    }
                }
            }
        }
        .outerNavigationTitle(L("指揮中心命令"))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("全部已讀")) {
                    vm.markAllCommandsAsRead()
                }
                .font(.subheadline)
                .disabled(vm.unreadCommandCount == 0)
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
}
    }

struct CommandOrderRow: View {
    let order: CommandOrder
    var onMarkRead: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // 優先等級圖示
            Image(systemName: order.priority.icon)
                .foregroundColor(order.priority.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.title).font(.headline)
                    if !order.isRead {
                        Circle()
                            .fill(NV.info)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(order.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: order.type.icon)
                    Text(L(order.type.rawValue))
                    Text("·")
                    Text(order.sender)
                    Text("·")
                    Text(order.timeText)
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(order.priority.label)
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundColor(NV.textOnColor)
                    .glassEffect(.regular.tint(order.priority.color), in: .rect(cornerRadius: 4))

                if !order.isRead {
                    Button(L("已讀")) { onMarkRead?() }
                        .font(.caption2).bold()
                        .buttonStyle(.glass)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 連線管理

struct ConnectionView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @AppStorage("appColorScheme") private var appColorScheme = "dark"
    @AppStorage("commSplitEnabled") private var commSplitEnabled = false
    @EnvironmentObject var l10n: L10n
    @State private var deptInput = ""
    @State private var pairInput = ""
    @State private var nodeIDInput = ""
    @State private var nicknameInput = ""
    @State private var manualIP = ""
    @State private var manualPort = "8930"
    @State private var showQuickGuide = false

    var body: some View {
        List {
            // 藍牙連線
            Section(header: Text(L("藍牙連線"))) {
                HStack {
                    Image(systemName: vm.isBluetoothConnected ? "bluetooth.connected" : "bluetooth")
                        .foregroundColor(vm.isBluetoothConnected ? NV.green : .gray)
                        .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.isBluetoothConnected ? L("已連接") : L("未連接"))
                                .font(.headline)
                            if let name = vm.bluetoothDeviceName {
                                Text(name)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if vm.isBluetoothConnected {
                            Button(L("斷開")) { vm.disconnectDevice() }
                                .font(.caption)
                                .buttonStyle(.glass(.regular.tint(NV.danger)))
                        }
                    }

                    if !vm.isBluetoothConnected {
                        Button {
                            vm.scanForDevices()
                        } label: {
                            HStack {
                                if vm.bluetoothManager.isScanning {
                                    ProgressView().padding(.trailing, 4)
                                }
                                Text(vm.bluetoothManager.isScanning ? L("掃描中…") : L("掃描 LinkGuard 裝置"))
                            }
                        }
                        .buttonStyle(.glass)
                    }

                    ForEach(vm.bluetoothManager.discoveredDevices) { device in
                        Button {
                            vm.connectToDevice(device)
                        } label: {
                            HStack {
                                Image(systemName: "wave.3.right")
                                    .foregroundColor(NV.green)
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("\(device.rssi) dBm")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(L("連接"))
                                    .font(.caption).foregroundColor(NV.green)
                            }
                        }
                    }
                }

                // 副指揮連接
                Section(header: Text(L("副指揮連接"))) {
                    HStack {
                        Image(systemName: vm.commandClient.isConnected ? "wifi" : "wifi.slash")
                            .foregroundColor(vm.commandClient.isConnected ? NV.green : .gray)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.commandClient.isConnected ? L("已連線") : L("搜尋中…"))
                                .font(.headline)
                                .foregroundColor(vm.commandClient.isConnected ? NV.green : .primary)
                            if let name = vm.commandClient.serverName {
                                Text(name)
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Text(L("自動搜尋 Bonjour 指揮中心"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Circle()
                            .fill(vm.commandClient.isConnected ? NV.green : NV.warning)
                            .frame(width: 10, height: 10)
                    }

                    // 伺服器狀態（連線後即時顯示）
                    if vm.commandClient.isConnected {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(vm.commandClient.hqServerStatus?.audioStreamRunning == true ? NV.green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(L("串流伺服器"))
                                    .font(.caption)
                                Text(vm.commandClient.hqServerStatus?.audioStreamRunning == true ? L("運行中") : L("離線"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(vm.commandClient.hqServerStatus?.udpServerRunning == true ? NV.green : .gray)
                                    .frame(width: 8, height: 8)
                                Text("UDP Server")
                                    .font(.caption)
                                Text(vm.commandClient.hqServerStatus?.udpServerRunning == true ? L("運行中") : L("離線"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    // 手動連線
                    if !vm.commandClient.isConnected {
                        HStack {
                            TextField(L("指揮中心 IP"), text: $manualIP)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            TextField("Port", text: $manualPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Button(L("連線")) {
                                let ip = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
                                let port = UInt16(manualPort) ?? 8930
                                guard !ip.isEmpty else { return }
                                vm.commandClient.connectToIP(ip, port: port)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                // 節點設定
                Section(header: Text(L("搜救節點設定"))) {
                    // 我的暱稱（顯示在指揮中心）
                    HStack {
                        Text(L("我的暱稱"))
                        Spacer()
                        TextField(L("選填，例：阿明"), text: $nicknameInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Button(L("更新")) {
                            vm.changeUserNickname(nicknameInput)
                        }
                        .font(.caption)
                        .buttonStyle(.glass)
                    }

                    // 節點 ID
                    HStack {
                        Text(L("節點 ID"))
                        Spacer()
                        TextField("RT-XXX", text: $nodeIDInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            #if os(iOS)
                            .autocapitalization(.allCharacters)
                            #endif
                        Button(L("更新")) {
                            vm.changeNodeID(nodeIDInput)
                        }
                        .font(.caption)
                        .buttonStyle(.glass)
                        .disabled(nodeIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }                    // 配對碼
                    HStack {
                        Text(L("配對碼"))
                        Spacer()
                        TextField("0000", text: $pairInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            #if os(iOS)
                            .autocapitalization(.allCharacters)
                            #endif
                        Button(L("更新")) {
                            vm.changePairCode(pairInput)
                        }
                        .font(.caption)
                        .buttonStyle(.glass)
                        .disabled(pairInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // 部門碼
                    HStack {
                        Text(L("部門碼"))
                        Spacer()
                        TextField("EMT", text: $deptInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            #if os(iOS)
                            .autocapitalization(.allCharacters)
                            #endif
                        Button(L("更新")) {
                            vm.changeDeptCode(deptInput)
                        }
                        .font(.caption)
                        .buttonStyle(.glass)
                        .disabled(deptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // LoRa 檔位
                    HStack {
                        Text(L("LoRa 檔位"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.nodeStatus.loraLevel },
                            set: { vm.changeLoRaLevel($0) }
                        )) {
                            ForEach(loraProfiles, id: \.level) { p in
                                Text(p.label).tag(p.level)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section(header: Text(L("操作手冊")),
                        footer: Text(L("此區塊是紀錄格式操作手冊，不是醫療處置教學；實際處置依消防、救護、醫療單位 SOP。"))) {
                    Button {
                        showQuickGuide = true
                    } label: {
                        Label(L("開啟快速操作手冊"), systemImage: "questionmark.circle")
                    }

                    NFCManualBlockView()
                }

                // 模擬模式
                Section(header: Text(L("模擬模式")),
                        footer: Text(L("在沒有硬體時模擬受困者訊號、SOS 警報等即時資料變化，適用於 Demo 展示。"))) {
                    Toggle(isOn: Binding(
                        get: { vm.isSimulating },
                        set: { _ in vm.toggleSimulation() }
                    )) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(NV.simulation)
                            Text(L("即時模擬"))
                        }
                    }
                }

                // WiFi 命令模式
                Section(header: Text(L("WiFi 命令模式")),
                        footer: Text(L("透過 WiFi NTP 時間同步，所有連到同一網路的裝置會在相同時間點收到相同的指揮命令。不需要 LoRa 硬體。"))) {
                    Toggle(isOn: Binding(
                        get: { vm.isWiFiCommandMode },
                        set: { _ in vm.toggleWiFiCommandMode() }
                    )) {
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundColor(NV.info)
                            Text(L("WiFi 命令同步"))
                        }
                    }
                }

                // 系統資訊
                Section(header: Text(L("系統資訊"))) {
                    InfoRow(label: L("節點 ID"), value: vm.nodeStatus.nodeID)
                    InfoRow(label: L("配對碼"), value: vm.nodeStatus.pairCode)
                    InfoRow(label: L("部門碼"), value: vm.nodeStatus.deptCode)
                    InfoRow(label: L("節點電量"), value: vm.nodeStatus.voltage > 0
                           ? "\(vm.nodeStatus.battery)% (\(String(format: "%.2f", vm.nodeStatus.voltage))V)"
                           : "\(vm.nodeStatus.battery)%")
                    InfoRow(label: L("LoRa 檔位"), value: vm.nodeStatus.loraProfile.label)
                    InfoRow(label: L("運行時間"), value: vm.uptimeText)
                    InfoRow(label: L("受困者總數"), value: "\(vm.victims.count)")
                    InfoRow(label: L("線上受困者"), value: "\(vm.onlineVictimCount)")
                    InfoRow(label: L("SOS 求救中"), value: "\(vm.sosVictimCount)")
                }

                // 界面配置
                Section(header: Text(L("界面配置")),
                        footer: Text(L("在 iPad 上將通訊頁面分為左側電台廣播、右側訊息同時顯示。"))) {
                    Toggle(isOn: $commSplitEnabled) {
                        HStack {
                            Image(systemName: "rectangle.split.2x1")
                                .foregroundColor(NV.info)
                            Text(L("通訊分屏（iPad）"))
                        }
                    }
                }

                // 語言切換
                Section(header: Text(L("語言 / Language"))) {
                    Picker(L("語言"), selection: $l10n.language) {
                        Text(L("中文")).tag("zh-Hant")
                        Text("EN").tag("en")
                    }
                    .pickerStyle(.segmented)
                }

                // 外觀模式
                Section(header: Text(L("外觀"))) {
                    Picker(L("主題"), selection: $appColorScheme) {
                        Text(L("夜視")).tag("dark")
                        Text(L("淺色")).tag("light")
                        Text(L("跟隨系統")).tag("system")
                    }
            .pickerStyle(.segmented)
                }
            }
        .outerNavigationTitle(L("設定"))
        .sheet(isPresented: $showQuickGuide) {
            QuickGuideView()
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("完成")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear {
            deptInput = vm.nodeStatus.deptCode
            pairInput = vm.nodeStatus.pairCode
            nodeIDInput = vm.nodeStatus.nodeID
            nicknameInput = vm.userNickname
        }
    }
}

private struct NFCManualBlockView: View {
    private let identityRows: [(String, String)] = [
        ("顯示 ID", "LG-260506-TAO-ZL-E01-S03-B02-F02-A-P023-K"),
        ("資料庫 Key", "LG260506TAOZLE01S03B02F02AP023K"),
        ("NFC URL", "https://linkguard.tw/p/LG260506TAOZLE01S03B02F02AP023K"),
        ("隱私規則", "姓名、身分證、電話與完整病歷不寫入 NFC；傷患 ID 不可變動。")
    ]

    private let formatRows: [(String, String, String)] = [
        ("LG1", "NTAG215", "LG1|ID|T|S|I|V|TX|TM"),
        ("LG2", "NTAG216", "LG2|ID:...|T:...|S:...|LOC:...|I:...|V:...|TX:...|ALG:...|NOTE:...|TM:...|UPD:...")
    ]

    private let workflowRows: [(String, String)] = [
        ("1. 建立傷患", "先完成傷患 ID、分區、樓層、檢傷、生命徵象與處置欄位。"),
        ("2. 選擇容量", "NTAG215 固定 LG1；NTAG216 固定 LG2。容量不確定時先選 LG1。"),
        ("3. 寫入標籤", "按下寫入後只靠近一張空白或可覆寫標籤，等待 Apple 原生 NFC 視窗顯示完成。"),
        ("4. 回讀確認", "寫完後用 NFC 讀取頁或同頁讀取按鈕回讀，確認 ID 與檢傷欄位一致。"),
        ("5. 交接", "同一名傷患只維護一張主要卡；換卡時先讀舊卡確認 ID，再覆寫或補登 HQ 紀錄。")
    ]

    private let syncRows: [(String, String)] = [
        ("同步時機", "寫卡成功後 App 會送出 nfc_tag_written 到 HQ。"),
        ("HQ 查核", "到 HQ「NFC 標籤管理」搜尋傷患 ID，確認格式、容量、寫入裝置與 payload。"),
        ("未同步", "先確認 iPhone 已連線 HQ、同一區域網路、Bonjour 或手動 IP 連線正常。"),
        ("Peer HQ", "Peer 模式只顯示主 HQ 同步紀錄，不能清除主 HQ 的寫卡紀錄。")
    ]

    private let troubleshootingRows: [(String, String)] = [
        ("掃描畫面未出現", "請用 iPhone 實機；Xcode target 需有 Near Field Communication Tag Reading capability。"),
        ("免費帳號限制", "真機測 CoreNFC 通常需要 Apple Developer Program 或加入已付費 Team。"),
        ("讀得到 URL 但 App 讀不到", "URL 背景讀取不等於 App CoreNFC 權限；請重新簽名安裝含 NFC entitlement 的 App。"),
        ("讀取失敗", "確認標籤已 NDEF 格式化、容量足夠、沒有一次靠近多張卡。"),
        ("備援", "Android/USB NFC 可先寫 URL；現場同時列印 QR Code，iPhone 可用相機掃描。")
    ]

    private let codeRows: [(String, String)] = [
        ("檢傷 T", "R=紅/立即; Y=黃/延遲; G=綠/輕傷; B=黑/死亡或無生命跡象; U=未分類"),
        ("性別年齡 S", "M45=男性約45歲; F30=女性約30歲; C08=兒童約8歲; U=不明"),
        ("傷勢 I", "HEAD=頭部外傷; CHEST=胸部外傷; ABD=腹部外傷; ARM_BLEED=手臂出血; LEG_BLEED=腿部出血; LEFT_LEG_BLEED=左腿出血; RIGHT_LEG_BLEED=右腿出血; FX=骨折; BURN=燒燙傷; CRUSH=壓砸傷; UNCON=意識不清; CPA=無呼吸心跳"),
        ("處置 TX", "TQL=左側止血帶; TQR=右側止血帶; BAND=包紮; SPL=固定; O2=給氧; CPR=CPR; AED=AED 使用; IV=靜脈路徑; NONE=尚未處置"),
        ("過敏 ALG", "PCN=青黴素; U=不明; 空白=未記錄")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("此手冊只定義 LinkGuard 紀錄格式與操作流程，不取代現場醫療處置 SOP。"))
                .font(.caption)
                .foregroundColor(.secondary)

            DisclosureGroup(L("身分與隱私規則")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(identityRows, id: \.0) { row in
                        manualRow(row.0, row.1, monospaced: row.0 != "隱私規則")
                    }
                }
                .padding(.top, 8)
            }

            ForEach(formatRows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.0)
                            .font(.subheadline.bold())
                        Text(row.1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Text(row.2)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text(L("容量規則：NTAG215 固定使用 LG1；NTAG216 固定使用 LG2；若現場不確定標籤容量，先寫 LG1。"))
                .font(.caption)
                .foregroundColor(.secondary)

            DisclosureGroup(L("寫卡與交接流程")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workflowRows, id: \.0) { row in
                        manualRow(row.0, row.1)
                    }
                }
                .padding(.top, 8)
            }

            DisclosureGroup(L("HQ 同步檢查")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(syncRows, id: \.0) { row in
                        manualRow(row.0, row.1)
                    }
                }
                .padding(.top, 8)
            }

            DisclosureGroup(L("LG1 / LG2 代碼表")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(codeRows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.0)
                                .font(.caption.bold())
                            Text(row.1)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 8)
            }

            DisclosureGroup(L("讀不到 / 寫失敗排除")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(troubleshootingRows, id: \.0) { row in
                        manualRow(row.0, row.1)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func manualRow(_ title: String, _ detail: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(title))
                .font(.caption.bold())
            Text(L(detail))
                .font(monospaced ? .caption2.monospaced() : .caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}

// MARK: - SOS 全螢幕警報

struct SOSAlertOverlay: View {
    let victim: VictimNode
    let onDismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            // 脈衝背景
            NV.danger
                .opacity(pulse ? 0.85 : 0.95)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 24) {
                Spacer()

                // SOS 圖示
                Image(systemName: "sos")
                    .font(.system(size: 80))
                    .foregroundColor(NV.textOnColor)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

                Text(L("SOS 求救警報"))
                    .font(.largeTitle).bold()
                    .foregroundColor(NV.textOnColor)

                // 受困者資訊卡
                VStack(spacing: 12) {
                    Text(victim.id)
                        .font(.title).bold()

                    HStack(spacing: 24) {
                        VStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.title2).foregroundColor(NV.heartRate)
                            Text(victim.heartRateText)
                                .font(.headline)
                        }
                        VStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.title2).foregroundColor(NV.info)
                            Text("~\(victim.distanceText)")
                                .font(.headline)
                        }
                        VStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title2).foregroundColor(NV.green)
                            Text("\(Int(victim.rssi)) dBm")
                                .font(.headline)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("\(victim.battery)%", systemImage: "battery.25")
                            .font(.subheadline)
                        Text(victim.isOnline ? L("線上") : L("離線"))
                            .font(.subheadline).bold()
                            .foregroundColor(victim.isOnline ? NV.green : .gray)
                    }
                }
                .padding(24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.horizontal, 24)

                Spacer()

                // 確認按鈕
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                        Text(L("收到"))
                            .font(.title2).bold()
                    }
                    .foregroundColor(NV.danger)
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(NV.textOnColor)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 40)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - 指揮命令全螢幕警報

struct CommandAlertOverlay: View {
    let command: CommandOrder
    let onDismiss: () -> Void
    @State private var pulse = false

    /// 最高級命令用紅色，其餘用命令色
    private var alertColor: Color {
        command.priority == .critical ? NV.danger : NV.command
    }

    var body: some View {
        ZStack {
            // 脈衝背景
            alertColor
                .opacity(pulse ? 0.85 : 0.95)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 24) {
                Spacer()

                // 命令圖示
                Image(systemName: command.priority == .critical
                      ? "exclamationmark.triangle.fill"
                      : "megaphone.fill")
                    .font(.system(size: 80))
                    .foregroundColor(NV.textOnColor)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)

                Text(command.priority == .critical ? L("緊急命令") : L("指揮中心命令"))
                    .font(.largeTitle).bold()
                    .foregroundColor(NV.textOnColor)

                // 命令資訊卡
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: command.type.icon)
                            .font(.title3)
                        Text(L(command.type.rawValue))
                            .font(.headline)
                    }

                    Text(command.title)
                        .font(.title2).bold()

                    Text(command.detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        Label(command.sender, systemImage: "building.2")
                            .font(.subheadline)
                        Label(command.priority.label, systemImage: command.priority.icon)
                            .font(.subheadline).bold()
                            .foregroundColor(command.priority.color)
                        Text(command.timeText)
                            .font(.subheadline)
                    }
                }
                .padding(24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.horizontal, 24)

                Spacer()

                // 確認按鈕
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                        Text(L("收到"))
                            .font(.title2).bold()
                    }
                    .foregroundColor(alertColor)
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(NV.textOnColor)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 40)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - 增援請求列表

struct ReinforcementListView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var showCompose = false
    @State private var composeMessage = ""
    @State private var composeLocation = ""

    var body: some View {
        List {
            if vm.reinforcementRequests.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.title).foregroundColor(.secondary)
                            Text(L("目前沒有增援請求"))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else {
                    // 待處理（別人發的）
                    let pending = vm.reinforcementRequests.filter { !$0.isFromSelf && $0.status == .pending }
                    if !pending.isEmpty {
                        Section(header: Text(L("待回應"))) {
                            ForEach(pending) { req in
                                ReinforcementRequestRow(request: req,
                                    onAccept: { vm.acceptReinforcement(req) },
                                    onDecline: { vm.declineReinforcement(req) })
                            }
                        }
                    }

                    // 所有請求
                    Section(header: Text(L("全部請求"))) {
                        ForEach(vm.reinforcementRequests) { req in
                            ReinforcementRequestRow(request: req)
                        }
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .outerNavigationTitle(L("增援請求"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCompose = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            #endif
            .sheet(isPresented: $showCompose) {
                NavigationStack {
                    Form {
                        Section(header: Text(L("增援資訊"))) {
                            TextField(L("描述（如：需要醫療支援）"), text: $composeMessage)
                            TextField(L("位置（如：A 棟 3F）"), text: $composeLocation)
                        }
                    }
                    .navigationTitle(L("呼叫增援"))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.visible, for: .navigationBar)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("取消")) { showCompose = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("發送")) {
                                vm.sendReinforcementRequest(
                                    message: composeMessage, location: composeLocation)
                                composeMessage = ""
                                composeLocation = ""
                                showCompose = false
                            }
                            .disabled(composeMessage.isEmpty)
                        }
                        #if os(iOS)
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(L("完成")) {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                        #endif
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

struct ReinforcementRequestRow: View {
    let request: ReinforcementRequest
    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: request.status.icon)
                .foregroundColor(request.status.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.isFromSelf ? L("你的請求") : L("來自 %@", request.fromTeam))
                        .font(.headline)
                    if request.status == .pending && !request.isFromSelf {
                        Circle().fill(NV.reinforce).frame(width: 8, height: 8)
                    }
                }
                Text(request.message)
                    .font(.subheadline).foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if !request.location.isEmpty {
                        Label(request.location, systemImage: "location.fill")
                    }
                    Text("·")
                    Text(request.timeText)
                }
                .font(.caption2).foregroundColor(.gray)

                if !request.respondedBy.isEmpty {
                    Text(L("回應：%@", request.respondedBy.joined(separator: ", ")))
                        .font(.caption2).foregroundColor(NV.team)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(L(request.status.rawValue))
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundColor(NV.textOnColor)
                    .glassEffect(.regular.tint(request.status.color), in: .rect(cornerRadius: 4))

                if request.status == .pending && !request.isFromSelf {
                    HStack(spacing: 6) {
                        Button(L("加入")) { onAccept?() }
                            .font(.caption2).bold()
                            .buttonStyle(.glass(.regular.tint(NV.green)))
                        Button(L("拒絕")) { onDecline?() }
                            .font(.caption2).bold()
                            .buttonStyle(.glass(.regular.tint(NV.danger)))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 團隊列表

struct TeamListView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        List {
            if vm.teamMembers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.title).foregroundColor(.secondary)
                            Text(L("尚未發現其他搜救節點"))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding()
                }
            } else {
                Section(header: Text(L("線上 (%lld)", vm.onlineTeamCount))) {
                    ForEach(vm.teamMembers.filter(\.isOnline)) { member in
                        TeamMemberRow(member: member)
                    }
                }
                let offline = vm.teamMembers.filter { !$0.isOnline }
                if !offline.isEmpty {
                    Section(header: Text(L("離線"))) {
                        ForEach(offline) { member in
                            TeamMemberRow(member: member)
                        }
                    }
                }
            }
        }
        .outerNavigationTitle(L("分隊通訊群組"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

struct TeamMemberRow: View {
    let member: TeamMember

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .foregroundColor(member.isOnline ? NV.team : .gray)
                .font(.title3)
                .frame(width: 40, height: 40)
                .glassEffect(
                    .regular.tint(member.isOnline ? NV.team : .gray),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.id).font(.headline)
                    Text(member.deptCode)
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundColor(NV.textOnColor)
                        .glassEffect(.regular.tint(NV.team), in: .rect(cornerRadius: 4))
                }
                HStack(spacing: 8) {
                    Label(L("%lld 受困者", member.victimCount), systemImage: "person.wave.2")
                        .font(.caption).foregroundColor(.secondary)
                    Label("~\(member.lastSeenText)", systemImage: "clock")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(member.isOnline ? L("線上") : L("離線"))
                    .font(.caption2).bold()
                    .foregroundColor(member.isOnline ? NV.green : .gray)
                Text("\(Int(member.rssi)) dBm")
                    .font(.caption2).foregroundColor(member.signalColor)
                HStack(spacing: 2) {
                    Image(systemName: "battery.25").font(.caption2)
                    Text("\(member.battery)%").font(.caption2)
                }
                .foregroundColor(member.battery <= 20 ? NV.danger : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 增援請求全螢幕覆蓋層

struct ReinforcementAlertOverlay: View {
    let request: ReinforcementRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            NV.reinforce
                .opacity(pulse ? 0.85 : 0.95)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(NV.textOnColor)
                    .scaleEffect(pulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)

                Text(L("增援請求"))
                    .font(.largeTitle).bold()
                    .foregroundColor(NV.textOnColor)

                VStack(spacing: 12) {
                    Text(L("來自 %@", request.fromTeam))
                        .font(.title2).bold()

                    Text(request.message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !request.location.isEmpty {
                        Label(request.location, systemImage: "location.fill")
                            .font(.headline)
                    }

                    Text(request.timeText)
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.horizontal, 24)

                Spacer()

                // 雙按鈕：加入 / 拒絕
                HStack(spacing: 16) {
                    Button(action: onDecline) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill").font(.title2)
                            Text(L("拒絕")).font(.title2).bold()
                        }
                        .foregroundColor(NV.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(NV.textOnColor)
                        .cornerRadius(16)
                    }

                    Button(action: onAccept) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.title2)
                            Text(L("加入")).font(.title2).bold()
                        }
                        .foregroundColor(NV.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(NV.textOnColor)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 40)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

// MARK: - 緊急廣播覆蓋層

struct UrgentBroadcastOverlay: View {
    let broadcast: TextBroadcast
    let onDismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.orange
                .opacity(pulse ? 0.9 : 0.95)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(NV.textOnColor)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

                Text(L("緊急廣播"))
                    .font(.largeTitle).bold()
                    .foregroundColor(NV.textOnColor)

                Text(broadcast.message)
                    .font(.title2)
                    .foregroundColor(NV.textOnColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(L("來自: %@", broadcast.senderName))
                    .font(.subheadline)
                    .foregroundColor(NV.textOnColor.opacity(0.8))

                Spacer()

                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                        Text(L("確認"))
                            .font(.title2).bold()
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                    .background(.white)
                    .cornerRadius(16)
                }

                Spacer().frame(height: 40)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - 傷患惡化預警覆蓋層

struct PatientWarningOverlay: View {
    let warning: PatientWarning
    let onDismiss: () -> Void

    private var levelColor: Color {
        switch warning.warningLevel {
        case "high": return NV.danger
        case "medium": return .orange
        default: return .yellow
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 48))
                    .foregroundColor(levelColor)

                Text(L("傷患惡化預警"))
                    .font(.title).bold()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L("患者: %@", warning.patientId), systemImage: "person.fill")
                    Label(L("檢傷等級: %@", warning.priority), systemImage: "cross.case.fill")
                    Label(L("位置: %@", warning.location), systemImage: "location.fill")
                    Label(L("已等候: %lld 分鐘", warning.minutesSinceTriage), systemImage: "clock")
                }
                .font(.body)

                Text(warning.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                        Text(L("已知悉"))
                            .font(.title3).bold()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(levelColor)
                    .cornerRadius(14)
                }
            }
            .padding(32)
            .frame(maxWidth: 500)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .padding(24)
        }
    }
}
