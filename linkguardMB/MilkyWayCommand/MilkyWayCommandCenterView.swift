import SwiftUI

struct MilkyWayCommandCenterView: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        NavigationSplitView {
            MilkyWaySidebar(vm: vm)
                .navigationSplitViewColumnWidth(min: 252, ideal: 292, max: 320)
        } content: {
            MilkyWayControlColumn(vm: vm)
                .navigationSplitViewColumnWidth(min: 306, ideal: 352, max: 390)
        } detail: {
            MilkyWayDetailSurface(vm: vm)
        }
        .navigationSplitViewStyle(.balanced)
        .background(MWTheme.bg.ignoresSafeArea())
    }
}

private struct MilkyWaySidebar: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.title2.bold())
                            .foregroundStyle(MWTheme.green)
                            .frame(width: 44, height: 44)
                            .background(MWTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Milky Way")
                                .font(.title3.bold())
                            Text("獨立 iPad 指揮中心")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

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
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MWTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            }

            Section("作戰面板") {
                ForEach(MilkyWayRoute.allCases) { route in
                    Button {
                        vm.selectedRoute = route
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: route.icon)
                                .frame(width: 22)
                                .foregroundStyle(vm.selectedRoute == route ? MWTheme.green : .secondary)
                            Text(route.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(vm.selectedRoute == route ? .primary : .secondary)
                            Spacer()
                        }
                        .frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(vm.selectedRoute == route ? MWTheme.green.opacity(0.14) : Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MWTheme.bg.ignoresSafeArea())
    }
}

private struct MilkyWayControlColumn: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("作戰控制")
                        .font(.title2.bold())
                    ControlStatusLine(title: "中樞模式", value: "獨立", color: MWTheme.green)
                    ControlStatusLine(title: "節點", value: vm.localNodeName, color: MWTheme.cyan)
                    ControlStatusLine(title: "資料來源", value: "本機作戰資料", color: MWTheme.violet)
                    Button {
                        vm.toggleNetwork()
                    } label: {
                        Label(vm.commandNetworkEnabled ? "關閉指揮網" : "開啟指揮網", systemImage: vm.commandNetworkEnabled ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.commandNetworkEnabled ? MWTheme.amber : MWTheme.green)
                }
                .mwPanel()

                VStack(alignment: .leading, spacing: 12) {
                    Text("快速命令")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(MWCommandPreset.allCases) { preset in
                            Button {
                                vm.issue(preset)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: preset.icon)
                                        .font(.title3.bold())
                                    Text(preset.title)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: preset == .evacuate ? 86 : 76)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 8))
                            .tint(preset.color)
                        }
                    }
                }
                .mwPanel()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("倒數管制")
                            .font(.headline)
                        Spacer()
                        Text(vm.countdownText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(vm.activeCountdownEnd == nil ? .secondary : MWTheme.amber)
                    }
                    HStack(spacing: 8) {
                        CountdownButton(title: "3m") { vm.startCountdown(minutes: 3) }
                        CountdownButton(title: "5m") { vm.startCountdown(minutes: 5) }
                        CountdownButton(title: "10m") { vm.startCountdown(minutes: 10) }
                    }
                    if vm.activeCountdownEnd != nil {
                        Button(role: .destructive) {
                            vm.cancelCountdown()
                        } label: {
                            Label("取消倒數", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .mwPanel()

                VStack(alignment: .leading, spacing: 12) {
                    Text("即時訊號")
                        .font(.headline)
                    SignalRow(title: "危急事件", value: "\(vm.incidents.filter { $0.severity == .critical || $0.severity == .urgent }.count)", icon: "exclamationmark.triangle.fill", color: MWTheme.red)
                    SignalRow(title: "隊伍在線", value: "\(vm.teams.count)", icon: "person.3.fill", color: MWTheme.cyan)
                    SignalRow(title: "待辦任務", value: "\(vm.tasks.filter { $0.progress < 1 }.count)", icon: "checklist", color: MWTheme.amber)
                }
                .mwPanel()
            }
            .padding(16)
        }
        .background(MWTheme.bg.ignoresSafeArea())
    }
}

private struct MilkyWayDetailSurface: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.operationName)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text("為 iPad 打造的獨立作戰中樞")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusChip(title: vm.commandNetworkEnabled ? "指揮網" : "離線", icon: vm.commandNetworkEnabled ? "wifi" : "wifi.slash", color: vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                    StatusChip(title: "非 Mac HQ", icon: "ipad", color: MWTheme.cyan)
                }
                .mwPanel()

                switch vm.selectedRoute {
                case .overview:
                    OverviewPanel(vm: vm)
                case .incidents:
                    IncidentPanel(vm: vm)
                case .teams:
                    TeamPanel(vm: vm)
                case .tasks:
                    TaskPanel(vm: vm)
                case .comms:
                    LogPanel(vm: vm)
                case .resources:
                    ResourcePanel(vm: vm)
                case .settings:
                    SettingsPanel(vm: vm)
                }
            }
            .padding(20)
        }
        .background(MWTheme.bg.ignoresSafeArea())
        .navigationTitle("Milky Way")
        .navigationBarTitleDisplayMode(.inline)
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
