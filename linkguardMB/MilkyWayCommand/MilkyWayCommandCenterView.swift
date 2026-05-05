import SwiftUI

// MARK: - 指揮中心主頁（TabView tab 用，觸控優化）

struct MilkyWayCommandCenterView: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    @State private var selectedRoute: MilkyWayRoute = .overview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 狀態 Header ──
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.title2.bold())
                            .foregroundStyle(MWTheme.green)
                            .frame(width: 52, height: 52)
                            .background(MWTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.operationName)
                                .font(.title3.bold())
                                .lineLimit(1)
                            Text("二級指揮（可接管替代伺服器 / 無 AI）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                                    .frame(width: 8, height: 8)
                                Text(vm.commandNetworkEnabled ? "本機指揮網運作中" : "離線作戰模式")
                                    .font(.caption.bold())
                                    .foregroundStyle(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                            }
                            Text(vm.localNodeName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(vm.countdownText)
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(vm.activeCountdownEnd == nil ? .secondary : MWTheme.amber)
                            Text("倒數")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MWTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))

                    // ── Metric 卡片（4 個，自適應）──
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
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

                    // ── 面板選擇器（觸控 Chip） ──
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
                                .buttonStyle(.borderedProminent)
                                .tint(selectedRoute == route ? MWTheme.green : MWTheme.surface)
                                .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    // ── 動態面板 ──
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
            .background(MWTheme.bg.ignoresSafeArea())
            .navigationTitle("Milky Way 指揮中心")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct OverviewPanel: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
                ForEach(vm.metrics) { metric in
                    MetricTile(metric: metric)
                }
            }

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
        .background(MWTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
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
            .background(MWTheme.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func mwPanel() -> some View {
        modifier(MWPanelModifier())
    }
}
