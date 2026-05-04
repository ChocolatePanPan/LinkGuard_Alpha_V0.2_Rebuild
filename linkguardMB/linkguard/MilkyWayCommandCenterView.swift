import SwiftUI

struct MilkyWayCommandCenterView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab
    @Binding var cameFromDashboard: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 286, max: 320)
        } content: {
            MilkyWayOperationsColumn(vm: vm, selectedTab: $selectedTab)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 390)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .tint(NV.green)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .dashboard { cameFromDashboard = false }
        }
    }

    private var sidebar: some View {
        List {
            Section {
                MilkyWaySidebarHeader(vm: vm)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            }

            Section(L("作戰")) {
                navRow(L("總覽"), icon: "gauge.with.dots.needle.67percent", tab: .dashboard)
                navRow(L("災情"), icon: "building.2.fill", tab: .disaster)
                navRow("SOS", icon: "sos.circle.fill", tab: .sos, badge: vm.unacknowledgedSOSCount)
                navRow(L("受困者"), icon: "person.fill.questionmark", tab: .victims, badge: vm.victims.count + vm.localPatients.count)
                navRow(L("團隊"), icon: "person.3.sequence.fill", tab: .team, badge: vm.onlineTeamCount)
                navRow(L("增援"), icon: "person.badge.plus.fill", tab: .reinforcement, badge: vm.pendingReinforcementCount)
            }

            Section(L("指揮")) {
                navRow(L("指揮命令"), icon: "megaphone.fill", tab: .commands, badge: vm.unreadCommandCount)
                navRow(L("指揮決策"), icon: "brain.head.profile", tab: .decision, badge: vm.decisions.count)
                navRow(L("人員指派"), icon: "person.badge.key.fill", tab: .personnelAssignment)
                navRow(L("傷員回報"), icon: "heart.text.square.fill", tab: .patientForm, badge: vm.localPatients.count)
            }

            Section(L("通訊與工具")) {
                navRow(L("通訊"), icon: "antenna.radiowaves.left.and.right", tab: .communication, badge: vm.chatMessages.count)
                navRow("AI", icon: vm.isAIServicePaused ? "pause.circle.fill" : "sparkles", tab: .ai)
                navRow(L("翻譯"), icon: "globe.asia.australia.fill", tab: .translator)
                navRow(L("照片"), icon: "photo.on.rectangle.angled", tab: .photo)
                navRow(L("通知"), icon: "bell.badge.fill", tab: .notifications, badge: vm.unreadNotificationCount)
                navRow(L("設定"), icon: "gearshape.fill", tab: .connection)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(NV.bg.ignoresSafeArea())
    }

    private func navRow(_ title: String, icon: String, tab: AppTab, badge: Int = 0) -> some View {
        Button {
            selectedTab = tab
        } label: {
            MilkyWaySidebarRow(title: title, icon: icon, badge: badge, isSelected: selectedTab == tab)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedTab == tab ? NV.green.opacity(0.16) : Color.clear)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .dashboard:
            MilkyWayDashboardSurface(vm: vm, selectedTab: $selectedTab)
        case .victims:
            VictimListView(vm: vm)
        case .sos:
            SOSRecordListView(vm: vm)
        case .disaster:
            FieldDisasterView(vm: vm)
        case .chat, .call, .radio, .communication:
            CommunicationHubView(vm: vm)
        case .reinforcement:
            ReinforcementListView(vm: vm)
        case .team:
            TeamListView(vm: vm)
        case .commands:
            CommandListView(vm: vm)
        case .notifications:
            FieldNotificationView(vm: vm)
        case .patientForm:
            PatientFormView(vm: vm)
        case .decision:
            DecisionView(vm: vm)
        case .translator:
            TranslatorView(vm: vm)
        case .photo:
            PhotoReportView(vm: vm)
        case .personnelAssignment:
            PersonnelAssignmentView(vm: vm)
        case .ai:
            AIHubView(vm: vm)
        case .connection:
            ConnectionView(vm: vm)
        }
    }
}

private struct MilkyWaySidebarHeader: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NV.command.opacity(0.28))
                    Image(systemName: "sparkles")
                        .font(.title2.bold())
                        .foregroundColor(NV.green)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Milky Way")
                        .font(.title3.bold())
                    Text(L("指揮中心"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(vm.commandClient.isConnected ? NV.green : NV.danger)
                    .frame(width: 8, height: 8)
                Text(vm.commandClient.isConnected ? L("已連線指揮中心") : L("未連線指揮中心"))
                    .font(.caption.bold())
                    .foregroundColor(vm.commandClient.isConnected ? NV.green : NV.danger)
            }

            Text("\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NV.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MilkyWaySidebarRow: View {
    let title: String
    let icon: String
    let badge: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundColor(isSelected ? NV.green : .secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundColor(isSelected ? .primary : .secondary)
            Spacer(minLength: 8)
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundColor(NV.textOnColor)
                    .background(NV.command, in: Capsule())
            }
        }
        .frame(minHeight: 32)
    }
}

private struct MilkyWayOperationsColumn: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    private var senderName: String {
        "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                operationsHeader
                quickCommandPanel
                timerPanel
                liveSignalPanel
            }
            .padding(16)
        }
        .background(NV.bg.ignoresSafeArea())
    }

    private var operationsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("作戰控制"))
                .font(.title2.bold())
            VStack(spacing: 9) {
                statusLine(title: L("HQ 連線"), value: vm.commandClient.isConnected ? L("在線") : L("離線"), color: vm.commandClient.isConnected ? NV.green : NV.danger)
                statusLine(title: L("本機節點"), value: vm.nodeStatus.nodeID, color: vm.nodeStatus.batteryColor)
                statusLine(title: "LoRa", value: vm.nodeStatus.loraProfile.label, color: NV.info)
                statusLine(title: L("電量"), value: "\(vm.nodeStatus.battery)%", color: vm.nodeStatus.batteryColor)
            }
        }
        .milkyPanel()
    }

    private func statusLine(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var quickCommandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("快速指揮"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MilkyWayCommandButton(title: L("全員撤離"), icon: "figure.run.circle.fill", tint: NV.danger, isPrimary: true) {
                    vm.sendHQQuickCommand(type: "evacuation", priority: 2, title: L("全員撤離"), detail: L("所有人員立即撤離至安全集結點"), sender: senderName)
                }
                MilkyWayCommandButton(title: L("原地待命"), icon: "pause.circle.fill", tint: NV.warning) {
                    vm.sendHQQuickCommand(type: "standby", priority: 1, title: L("原地待命"), detail: L("各隊維持位置，等待下一步指示"), sender: senderName)
                }
                MilkyWayCommandButton(title: L("回報狀態"), icon: "doc.text.fill", tint: NV.info) {
                    vm.sendHQQuickCommand(type: "report", priority: 0, title: L("回報狀態"), detail: L("請各隊回報人員、受困者與環境狀態"), sender: senderName)
                }
                MilkyWayCommandButton(title: L("醫療支援"), icon: "cross.case.fill", tint: NV.reinforce) {
                    vm.sendHQQuickCommand(type: "support", priority: 1, title: L("醫療支援"), detail: L("請醫療與搬運組支援傷患處置"), sender: senderName)
                }
            }
            .disabled(!vm.commandClient.isConnected)

            if !vm.commandClient.isConnected {
                Button {
                    selectedTab = .connection
                } label: {
                    Label(L("連線指揮中心"), systemImage: "wifi.router.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.command)
            }
        }
        .milkyPanel()
    }

    private var timerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("倒數管制"))
                    .font(.headline)
                Spacer()
                Text("\(vm.countdownTimers.count)")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                timerButton(title: "3m", seconds: 180)
                timerButton(title: "5m", seconds: 300)
                timerButton(title: "10m", seconds: 600)
            }

            if vm.countdownTimers.isEmpty {
                MilkyWayEmptyLine(icon: "timer", title: L("無倒數計時"))
            } else {
                ForEach(Array(vm.countdownTimers.prefix(3))) { timer in
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .foregroundColor(timer.remainingSeconds < 60 ? NV.danger : NV.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timer.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(timer.remainingText)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.cancelHQTimer(timer.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(NV.danger)
                    }
                    .padding(10)
                    .background(NV.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .milkyPanel()
    }

    private func timerButton(title: String, seconds: Int) -> some View {
        Button {
            vm.startHQTimer(title: L("作戰倒數"), durationSeconds: seconds)
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(NV.info)
        .disabled(!vm.commandClient.isConnected)
    }

    private var liveSignalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("即時訊號"))
                .font(.headline)

            MilkyWaySignalRow(title: "SOS", value: "\(vm.unacknowledgedSOSCount)", icon: "sos.circle.fill", color: vm.unacknowledgedSOSCount > 0 ? NV.danger : NV.green)
            MilkyWaySignalRow(title: L("受困者"), value: "\(vm.onlineVictimCount)/\(vm.victims.count)", icon: "person.wave.2.fill", color: NV.info)
            MilkyWaySignalRow(title: L("線上隊伍"), value: "\(vm.onlineTeamCount)/\(vm.teamMembers.count)", icon: "person.3.fill", color: NV.team)
            MilkyWaySignalRow(title: L("任務"), value: "\(vm.activeTaskCount)", icon: "checklist", color: NV.warning)
        }
        .milkyPanel()
    }
}

private struct MilkyWayCommandButton: View {
    let title: String
    let icon: String
    let tint: Color
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isPrimary ? 84 : 74)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .buttonBorderShape(.roundedRectangle(radius: 8))
    }
}

private struct MilkyWaySignalRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(color)
        }
        .padding(10)
        .background(NV.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MilkyWayDashboardSurface: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        MilkyWayVictimBoard(vm: vm, selectedTab: $selectedTab)
                        MilkyWayTaskBoard(vm: vm, selectedTab: $selectedTab)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        MilkyWayCommandFeed(vm: vm, selectedTab: $selectedTab)
                        MilkyWayTeamBoard(vm: vm, selectedTab: $selectedTab)
                    }
                    .frame(maxWidth: 410)
                }
            }
            .padding(20)
        }
        .background(NV.bg.ignoresSafeArea())
        .navigationTitle("Milky Way")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Milky Way 指揮中心")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("iPad 作戰中樞"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                MilkyWayStatusChip(title: vm.commandClient.isConnected ? L("HQ 在線") : L("HQ 離線"), icon: "wifi", color: vm.commandClient.isConnected ? NV.green : NV.danger)
                MilkyWayStatusChip(title: vm.isAIServicePaused ? L("AI 暫停") : "AI", icon: vm.isAIServicePaused ? "pause.circle.fill" : "sparkles", color: vm.isAIServicePaused ? NV.warning : NV.info)
                MilkyWayStatusChip(title: vm.nodeStatus.loraProfile.label, icon: "antenna.radiowaves.left.and.right", color: NV.team)
            }
        }
        .padding(18)
        .background(NV.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MilkyWayMetricTile(title: "SOS", value: "\(vm.unacknowledgedSOSCount)", icon: "sos.circle.fill", color: vm.unacknowledgedSOSCount > 0 ? NV.danger : NV.green) { selectedTab = .sos }
            MilkyWayMetricTile(title: L("受困者"), value: "\(vm.onlineVictimCount)/\(vm.victims.count)", icon: "person.wave.2.fill", color: NV.info) { selectedTab = .victims }
            MilkyWayMetricTile(title: L("團隊"), value: "\(vm.onlineTeamCount)/\(vm.teamMembers.count)", icon: "person.3.fill", color: NV.team) { selectedTab = .team }
            MilkyWayMetricTile(title: L("傷患"), value: "\(vm.localPatients.count)", icon: "heart.text.square.fill", color: NV.heartRate) { selectedTab = .patientForm }
            MilkyWayMetricTile(title: L("命令"), value: "\(vm.unreadCommandCount)", icon: "megaphone.fill", color: NV.command) { selectedTab = .commands }
            MilkyWayMetricTile(title: L("任務"), value: "\(vm.activeTaskCount)", icon: "checklist", color: NV.warning) { selectedTab = .personnelAssignment }
        }
    }
}

private struct MilkyWayStatusChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.bold())
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
    }
}

private struct MilkyWayMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 126)
            .background(NV.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct MilkyWayVictimBoard: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            boardHeader(title: L("生命訊號"), icon: "waveform.path.ecg") { selectedTab = .victims }
            if vm.victims.isEmpty && vm.localPatients.isEmpty {
                MilkyWayEmptyState(icon: "antenna.radiowaves.left.and.right", title: L("尚未發現受困者..."))
                    .frame(height: 220)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(vm.victims.prefix(6))) { victim in
                        MilkyWayVictimTile(victim: victim)
                    }
                }
                if !vm.localPatients.isEmpty {
                    Divider()
                    ForEach(Array(vm.localPatients.suffix(3).reversed())) { patient in
                        MilkyWayPatientCompactRow(patient: patient)
                            .padding(10)
                            .background(NV.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .milkyPanel()
    }
}

private struct MilkyWayVictimTile: View {
    let victim: VictimNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(victim.id)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(victim.isSOS ? NV.danger : victim.signalColor)
                    .frame(width: 9, height: 9)
            }
            HStack(spacing: 10) {
                Label(victim.heartRateText, systemImage: "heart.fill")
                    .foregroundColor(victim.heartRate > 0 ? NV.heartRate : .secondary)
                Label(victim.distanceText, systemImage: "location.fill")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            Text(victim.lastSeenText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .background(NV.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(victim.isSOS ? NV.danger.opacity(0.85) : Color.clear, lineWidth: 1.5)
        }
    }
}

private struct MilkyWayPatientCompactRow: View {
    let patient: PatientReport

    private var displayName: String {
        patient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? patient.patientId : patient.name
    }

    private var triageColor: Color {
        if patient.breathingRate < 0 || patient.capillaryRefill < 0 { return NV.danger }
        if patient.breathingRate > 30 || !patient.canFollowCommands { return NV.warning }
        return NV.green
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cross.case.fill")
                .foregroundColor(triageColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(patient.location.isEmpty ? patient.patientId : patient.location)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(patient.breathingRate < 0 ? "--" : "\(patient.breathingRate)/m")
                .font(.caption.monospacedDigit())
                .foregroundColor(triageColor)
        }
    }
}

private struct MilkyWayCommandFeed: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            boardHeader(title: L("指揮流"), icon: "timeline.selection") { selectedTab = .commands }
            if vm.commandOrders.isEmpty && vm.sosRecords.isEmpty && vm.decisions.isEmpty {
                MilkyWayEmptyState(icon: "dot.radiowaves.left.and.right", title: L("等待指揮中心命令..."))
                    .frame(height: 190)
            } else {
                ForEach(Array(vm.commandOrders.prefix(3))) { order in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: order.priority.icon)
                            .foregroundColor(order.priority.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(order.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(order.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            Text(order.timeText)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(NV.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(Array(vm.sosRecords.prefix(2))) { record in
                    HStack(spacing: 10) {
                        Image(systemName: record.isAcknowledged ? "checkmark.circle.fill" : "sos.circle.fill")
                            .foregroundColor(record.isAcknowledged ? NV.green : NV.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.displayTitle)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(record.timeText)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(NV.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .milkyPanel()
    }
}

private struct MilkyWayTaskBoard: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            boardHeader(title: L("任務隊列"), icon: "checklist") { selectedTab = .personnelAssignment }
            let activeTasks = vm.tasks.filter(\.isActive)
            if activeTasks.isEmpty {
                MilkyWayEmptyState(icon: "checkmark.shield.fill", title: L("無待處理任務"))
                    .frame(height: 150)
            } else {
                ForEach(Array(activeTasks.prefix(5))) { task in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(task.taskStatus.color)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(task.assigneeName.isEmpty ? task.assigneeID : task.assigneeName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(task.taskStatus.label)
                            .font(.caption2.bold())
                            .foregroundColor(task.taskStatus.color)
                    }
                    .padding(10)
                    .background(NV.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .milkyPanel()
    }
}

private struct MilkyWayTeamBoard: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            boardHeader(title: L("隊伍狀態"), icon: "person.3.fill") { selectedTab = .team }
            if vm.teamMembers.isEmpty {
                MilkyWayEmptyState(icon: "person.3.sequence.fill", title: L("尚未連線隊伍"))
                    .frame(height: 150)
            } else {
                ForEach(Array(vm.teamMembers.prefix(6))) { member in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(member.isOnline ? member.signalColor : .gray)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayLabel)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(member.lastSeenText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(member.battery)%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(member.battery > 20 ? NV.green : NV.danger)
                    }
                    .padding(10)
                    .background(NV.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .milkyPanel()
    }
}

private func boardHeader(title: String, icon: String, action: @escaping () -> Void) -> some View {
    HStack {
        Label(title, systemImage: icon)
            .font(.headline)
        Spacer()
        Button(action: action) {
            Image(systemName: "arrow.up.right")
        }
        .buttonStyle(.plain)
        .foregroundColor(NV.info)
    }
}

private struct MilkyWayEmptyLine: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(NV.surface.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MilkyWayEmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NV.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MilkyPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NV.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func milkyPanel() -> some View {
        modifier(MilkyPanelModifier())
    }
}
