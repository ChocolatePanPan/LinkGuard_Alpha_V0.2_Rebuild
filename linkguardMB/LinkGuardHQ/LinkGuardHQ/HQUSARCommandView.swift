import SwiftUI

struct HQUSARCommandView: View {
    @ObservedObject var vm: HQViewModel
    @State private var worksiteCode = "W01"
    @State private var worksiteName = ""
    @State private var worksiteAddress = ""
    @State private var worksitePriority: WorksitePriority = .normal
    @State private var selectedWorksiteID = ""
    @State private var selectedDeviceID = ""
    @State private var taskKind: SquadTaskKind = .assess
    @State private var taskTitle = ""
    @State private var taskInstructions = ""

    private var worksites: [Worksite] {
        vm.usarStore.worksites.values.sorted { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
        }
    }

    private var tasks: [SquadTask] {
        vm.usarStore.squadTasks.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var latestStatuses: [SquadStatus] {
        vm.usarStore.squadStatuses.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var resourceRequests: [ResourceRequest] {
        vm.usarStore.resourceRequests.values.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("USAR UCC 指揮鏈"), subtitle: L("UCC → 分區 → 工作點 → 小隊長"), icon: "point.3.connected.trianglepath.dotted", accent: NV.command) {
                Button {
                    _ = vm.ensureDefaultUSAROperation()
                    if selectedWorksiteID.isEmpty {
                        selectedWorksiteID = worksites.first?.id ?? ""
                    }
                } label: {
                    Label(L("初始化"), systemImage: "square.stack.3d.up.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.command)
            }

            HStack(spacing: NV.panelSpacing) {
                StatLabel(icon: "building.2.fill", label: L("工作點"), value: "\(worksites.count)", color: NV.command)
                StatLabel(icon: "checklist.checked", label: L("任務"), value: "\(tasks.count)", color: NV.green)
                StatLabel(icon: "dot.radiowaves.left.and.right", label: L("狀態回報"), value: "\(latestStatuses.count)", color: NV.info)
                StatLabel(icon: "shippingbox.fill", label: L("資源請求"), value: "\(resourceRequests.count)", color: NV.reinforce)
            }

            HStack(alignment: .top, spacing: NV.panelSpacing) {
                worksiteComposer
                squadTaskComposer
            }

            HStack(alignment: .top, spacing: NV.panelSpacing) {
                worksiteBoard
                taskAndStatusBoard
            }

            resourceRequestBoard
            packetLogBoard
        }
        .onAppear {
            if selectedWorksiteID.isEmpty {
                selectedWorksiteID = worksites.first?.id ?? ""
            }
            if selectedDeviceID.isEmpty {
                selectedDeviceID = vm.server.fieldUnits.first?.deviceID ?? ""
            }
        }
        .onChange(of: worksites.map(\.id)) { _, ids in
            if selectedWorksiteID.isEmpty || !ids.contains(selectedWorksiteID) {
                selectedWorksiteID = ids.first ?? ""
            }
        }
        .onChange(of: vm.server.fieldUnits.map(\.deviceID)) { _, ids in
            if selectedDeviceID.isEmpty || !ids.contains(selectedDeviceID) {
                selectedDeviceID = ids.first ?? ""
            }
        }
    }

    private var worksiteComposer: some View {
        HQPanel(title: L("建立工作點"), icon: "building.2.crop.circle", accent: NV.command) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField(L("代號"), text: $worksiteCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Picker(L("優先"), selection: $worksitePriority) {
                        ForEach(WorksitePriority.allCases) { priority in
                            Text(priority.displayText).tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                }
                TextField(L("工作點名稱"), text: $worksiteName)
                    .textFieldStyle(.roundedBorder)
                TextField(L("位置 / 地址"), text: $worksiteAddress)
                    .textFieldStyle(.roundedBorder)
                Button {
                    vm.createUSARWorksite(code: worksiteCode, name: worksiteName, address: worksiteAddress, priority: worksitePriority)
                    selectedWorksiteID = worksites.first?.id ?? selectedWorksiteID
                    worksiteName = ""
                    worksiteAddress = ""
                    worksiteCode = String(format: "W%02d", worksites.count + 2)
                } label: {
                    Label(L("建立並同步"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.command)
                .disabled(worksiteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var squadTaskComposer: some View {
        HQPanel(title: L("派遣小隊任務"), icon: "figure.run.circle", accent: NV.green) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L("工作點"), selection: $selectedWorksiteID) {
                    Text(L("請選擇工作點")).tag("")
                    ForEach(worksites) { worksite in
                        Text("\(worksite.code) · \(worksite.name)").tag(worksite.id)
                    }
                }
                .pickerStyle(.menu)

                Picker(L("小隊長裝置"), selection: $selectedDeviceID) {
                    Text(L("廣播 / 未指定")).tag("")
                    ForEach(vm.server.fieldUnits) { unit in
                        Text("\(unit.deptCode)-\(unit.deviceID)").tag(unit.deviceID)
                    }
                }
                .pickerStyle(.menu)

                Picker(L("任務類型"), selection: $taskKind) {
                    ForEach(SquadTaskKind.allCases) { kind in
                        Text(kind.displayText).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField(L("任務標題"), text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                TextField(L("任務指示"), text: $taskInstructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button {
                    vm.dispatchUSARSquadTask(worksiteID: selectedWorksiteID, targetDeviceID: selectedDeviceID, kind: taskKind, title: taskTitle, instructions: taskInstructions)
                    taskTitle = ""
                    taskInstructions = ""
                } label: {
                    Label(L("送出任務"), systemImage: "paperplane.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.green)
                .disabled(selectedWorksiteID.isEmpty || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var worksiteBoard: some View {
        HQPanel(title: L("工作點清單"), icon: "list.bullet.rectangle", accent: NV.command) {
            if worksites.isEmpty {
                HQEmptyStateView(icon: "building.2", title: L("尚未建立 USAR 工作點"), subtitle: L("先建立一個工作點，UCC 才能往下派遣。"), minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(worksites) { worksite in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 4) {
                                Text(worksite.code)
                                    .font(.headline.monospaced())
                                Text(worksite.priority.displayText)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(priorityColor(worksite.priority).opacity(0.16))
                                    .foregroundColor(priorityColor(worksite.priority))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .frame(width: 62)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(worksite.name)
                                    .font(.headline)
                                Text(worksite.address.isEmpty ? L("未填位置") : worksite.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Label(worksite.status.displayText, systemImage: "flag.fill")
                                    Label("\(worksite.victimCount)", systemImage: "person.fill.questionmark")
                                    if let asr = worksite.currentASRLevel {
                                        Label(asr.displayText, systemImage: "magnifyingglass")
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: selectedWorksiteID == worksite.id ? 1 : 0.72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedWorksiteID == worksite.id ? NV.command.opacity(0.55) : Color.secondary.opacity(0.14), lineWidth: NV.strokeWidth)
                        )
                        .onTapGesture { selectedWorksiteID = worksite.id }
                    }
                }
            }
        }
    }

    private var taskAndStatusBoard: some View {
        HQPanel(title: L("任務 / 狀態"), icon: "waveform.path.ecg.rectangle", accent: NV.info) {
            if tasks.isEmpty && latestStatuses.isEmpty {
                HQEmptyStateView(icon: "checklist", title: L("尚未有 USAR 任務或狀態"), subtitle: L("派遣小隊任務後，小隊長回報會出現在這裡。"), minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(tasks.prefix(8)) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(task.kind.displayText, systemImage: "checklist.checked")
                                    .foregroundColor(NV.info)
                                Spacer()
                                Text(task.status.displayText)
                                    .font(.caption.bold())
                                    .foregroundColor(task.status == .completed ? NV.green : NV.command)
                            }
                            Text(task.title)
                                .font(.headline)
                            Text(task.instructions.isEmpty ? L("無額外指示") : task.instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(L("小隊：%@", task.squadID))
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    ForEach(latestStatuses.prefix(6)) { status in
                        HStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(NV.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.status.displayText)
                                    .font(.headline)
                                Text(status.note.isEmpty ? status.squadID : "\(status.squadID) · \(status.note)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: status.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var resourceRequestBoard: some View {
        HQPanel(title: L("資源請求"), icon: "shippingbox", accent: NV.reinforce) {
            if resourceRequests.isEmpty {
                HQEmptyStateView(icon: "shippingbox", title: L("尚未收到資源請求"), minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(resourceRequests.prefix(8)) { request in
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .foregroundColor(NV.reinforce)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(request.resourceType) × \(request.quantity)")
                                    .font(.headline)
                                Text(request.reason.isEmpty ? request.requesterID : "\(request.requesterID) · \(request.reason)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(request.status.displayText)
                                .font(.caption.bold())
                                .foregroundColor(NV.reinforce)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var packetLogBoard: some View {
        HQPanel(title: L("USAR 封包紀錄"), icon: "network", accent: NV.team) {
            if vm.usarMessageLog.isEmpty {
                Text(L("尚無封包"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.usarMessageLog.prefix(8), id: \.messageID) { payload in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .foregroundColor(NV.team)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payload.messageType)
                                    .font(.caption.bold())
                                Text("\(payload.originRole) → \(payload.targetRole ?? "*")")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: Date(timeIntervalSince1970: payload.timestamp)))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func priorityColor(_ priority: WorksitePriority) -> Color {
        switch priority {
        case .immediate: return NV.danger
        case .high: return NV.reinforce
        case .normal: return NV.green
        case .low: return NV.info
        case .deferred: return .secondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
