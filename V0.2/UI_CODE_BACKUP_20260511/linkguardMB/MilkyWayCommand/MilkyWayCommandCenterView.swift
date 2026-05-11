import SwiftUI

// MARK: - 指揮中心主頁（TabView tab 用，觸控優化）

struct MilkyWayCommandCenterView: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    @State private var selectedRoute: MilkyWayRoute = .overview

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        MWTheme.bg,
                        MWTheme.surface.opacity(0.72),
                        MWTheme.bg
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(MWTheme.cyan.opacity(0.14))
                    .frame(width: 280, height: 280)
                    .blur(radius: 50)
                    .offset(x: 170, y: -250)

                Circle()
                    .fill(MWTheme.violet.opacity(0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 45)
                    .offset(x: -180, y: 290)

                VStack(spacing: 0) {
                    // ── 頂部固定區：Banner + BridgeHeader + Route Chips ──
                    VStack(alignment: .leading, spacing: 12) {
                        CommandTierBanner(vm: vm)
                        BridgeHeader(vm: vm)

                        // ── 面板選擇器（觸控 Chip，固定不滾動） ──
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MilkyWayRoute.allCases) { route in
                                    Button {
                                        selectedRoute = route
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: route.icon)
                                            Text(route.title)
                                                .font(.subheadline.bold())
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(selectedRoute == route ? MWTheme.textOnColor : .secondary)
                                    .background(
                                        Capsule()
                                            .fill(selectedRoute == route ? MWTheme.green : MWTheme.elevated.opacity(0.85))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(MWTheme.cyan.opacity(selectedRoute == route ? 0.0 : 0.24), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(16)
                    .background(MWTheme.bg.opacity(0.96))

                    Divider()
                        .overlay(MWTheme.cyan.opacity(0.14))

                    // ── 可捲動動態面板 ──
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch selectedRoute {
                            case .overview:   OverviewPanel(vm: vm)
                            case .incidents:  IncidentPanel(vm: vm)
                            case .teams:      TeamPanel(vm: vm)
                            case .tasks:      TaskPanel(vm: vm)
                            case .comms:      LogPanel(vm: vm)
                            case .resources:  ResourcePanel(vm: vm)
                            case .settings:   SettingsPanel(vm: vm)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Milky Way 戰情橋")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CommandTierBanner: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        HStack(spacing: 10) {
            Label("SECONDARY COMMAND NODE", systemImage: "shield.lefthalf.filled")
                .font(.caption.bold())
                .foregroundStyle(MWTheme.textOnColor)
            Spacer()
            StatusChip(
                title: vm.failoverState.title,
                icon: "arrow.triangle.2.circlepath.circle.fill",
                color: vm.failoverState.color
            )
            StatusChip(title: "AI OFF", icon: "brain.slash", color: MWTheme.cyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [MWTheme.green.opacity(0.85), MWTheme.cyan.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
}

private struct BridgeHeader: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.title2.bold())
                        .foregroundStyle(MWTheme.cyan)
                        .frame(width: 42, height: 42)
                        .background(MWTheme.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    Text(vm.operationName)
                        .font(.title3.bold())
                        .lineLimit(1)
                }
                Text("二級指揮節點：可接管替代伺服器、維持任務派送與通訊同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                        .frame(width: 8, height: 8)
                    Text(vm.commandNetworkEnabled ? "本機指揮網運作中" : "離線作戰模式")
                        .font(.caption.bold())
                        .foregroundStyle(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                    Text(vm.localNodeName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(vm.countdownText)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(vm.activeCountdownEnd == nil ? .secondary : MWTheme.amber)
                Text("TACTICAL TIMER")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MWTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MWTheme.cyan.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct OverviewPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Metric 卡片 ──
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
                ForEach(vm.metrics) { metric in
                    MetricTile(metric: metric)
                }
            }

            // ── 快速命令 ──
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "快速命令", icon: "bolt.fill")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(MWCommandPreset.allCases) { preset in
                        Button {
                            vm.issue(preset)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: preset.icon)
                                    .font(.title2.bold())
                                Text(preset.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 88)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .tint(preset.color)
                    }
                }
            }
            .mwPanel()

            // ── 倒數管制 ──
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "倒數管制", icon: "timer")
                HStack(spacing: 10) {
                    CountdownButton(title: "3 分鐘") { vm.startCountdown(minutes: 3) }
                    CountdownButton(title: "5 分鐘") { vm.startCountdown(minutes: 5) }
                    CountdownButton(title: "10 分鐘") { vm.startCountdown(minutes: 10) }
                }
                if vm.activeCountdownEnd != nil {
                    Button(role: .destructive) {
                        vm.cancelCountdown()
                    } label: {
                        Label("取消倒數", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    vm.toggleNetwork()
                } label: {
                    Label(
                        vm.commandNetworkEnabled ? "關閉指揮網" : "開啟指揮網",
                        systemImage: vm.commandNetworkEnabled
                            ? "antenna.radiowaves.left.and.right.slash"
                            : "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.commandNetworkEnabled ? MWTheme.amber : MWTheme.green)
            }
            .mwPanel()

            // ── 態勢摘要（左右分欄）──
            HStack(alignment: .top, spacing: 16) {
                IncidentPanel(vm: vm, compact: true)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    TeamPanel(vm: vm, compact: true)
                    TaskPanel(vm: vm, compact: true)
                }
                .frame(maxWidth: 430)
            }
        }
    }
}

private struct IncidentPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "事件線", icon: "timeline.selection")
            ForEach(Array(vm.incidents.prefix(compact ? 3 : 12))) { incident in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(incident.severity.color)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(incident.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Spacer()
                            Text(incident.severity.label)
                                .font(.caption.bold())
                                .foregroundStyle(incident.severity.color)
                        }
                        Text(incident.location)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(incident.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(compact ? 2 : 3)
                    }
                }
                .padding(12)
                .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .mwPanel()
    }
}

private struct TeamPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "隊伍", icon: "person.3.sequence.fill")
            ForEach(Array(vm.teams.prefix(compact ? 4 : 12))) { team in
                HStack(spacing: 12) {
                    Circle()
                        .fill(team.severity.color)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(team.name) / \(team.role)")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text("\(team.zone) · \(team.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(team.battery)%")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(team.battery > 30 ? MWTheme.green : MWTheme.red)
                }
                .padding(12)
                .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .mwPanel()
    }
}

private struct TaskPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "任務", icon: "checklist.checked")
            ForEach(Array(vm.tasks.prefix(compact ? 4 : 12))) { task in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(task.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Spacer()
                        Text(task.due)
                            .font(.caption.bold())
                            .foregroundStyle(task.severity.color)
                    }
                    Text(task.owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: task.progress)
                        .tint(task.severity.color)
                }
                .padding(12)
                .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .mwPanel()
    }
}

private struct LogPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "通訊紀錄", icon: "antenna.radiowaves.left.and.right")
            ForEach(vm.logs.prefix(16)) { log in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(log.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.title)
                            .font(.subheadline.bold())
                        Text(log.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(log.time, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .mwPanel()
    }
}

private struct ResourcePanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "資源", icon: "shippingbox.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(vm.resources) { resource in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(resource.name)
                                .font(.headline)
                            Spacer()
                            Circle()
                                .fill(resource.condition.color)
                                .frame(width: 9, height: 9)
                        }
                        Text(resource.amount)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(resource.condition.color)
                        Text(resource.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .mwPanel()
    }
}

private struct SettingsPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "中樞設定", icon: "slider.horizontal.3")
            Toggle("本機指揮網", isOn: $vm.commandNetworkEnabled)
                .toggleStyle(.switch)
            TextField("節點名稱", text: $vm.localNodeName)
                .textFieldStyle(.roundedBorder)
            TextField("作戰名稱", text: $vm.operationName)
                .textFieldStyle(.roundedBorder)
            ControlStatusLine(title: "替代伺服器", value: vm.failoverState.title, color: vm.failoverState.color)
            ControlStatusLine(title: "AI 功能", value: "停用", color: MWTheme.cyan)
        }
        .mwPanel()
    }
}

private struct ControlStatusLine: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct CountdownButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MWTheme.cyan)
    }
}

private struct SignalRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(10)
        .background(MWTheme.elevated.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusChip: View {
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
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
    }
}

private struct MetricTile: View {
    let metric: MWMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: metric.icon)
                    .foregroundStyle(metric.color)
                Spacer()
            }
            Text(metric.value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.color)
            Text(metric.title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 126)
        .background(MWTheme.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(metric.color.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }
}

private struct MWPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MWTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MWTheme.cyan.opacity(0.16), lineWidth: 1)
            )
    }
}

private extension View {
    func mwPanel() -> some View {
        modifier(MWPanelModifier())
    }
}
