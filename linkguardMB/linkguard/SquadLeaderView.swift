import SwiftUI

struct SquadLeaderView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var selectedTaskID: String?
    @State private var statusNote = ""
    @State private var locationDescription = ""
    @State private var resourceType = ""
    @State private var resourceQuantity = 1
    @State private var resourceReason = ""
    @State private var medicalVictimID = ""
    @State private var medicalTriageCode = "RED"
    @State private var medicalDestination = ""
    @State private var medicalNotes = ""
    @State private var medicalStatus: MedicalTransferStatus = .pending

    private var tasks: [SquadTask] { vm.visibleUSARTasks }

    private var selectedTask: SquadTask? {
        if let selectedTaskID,
           let task = tasks.first(where: { $0.id == selectedTaskID }) {
            return task
        }
        return tasks.first
    }

    private var worksites: [Worksite] {
        vm.usarStore.worksites.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                FieldINSARAGBriefPanel(profile: .squadLeader, accent: NV.green)
                taskList
                statusPanel
                medicalPanel
                resourcePanel
                recentPackets
            }
            .padding()
        }
        .outerNavigationTitle(L("USAR 小隊長"))
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear {
            if selectedTaskID == nil {
                selectedTaskID = tasks.first?.id
            }
        }
        .onChange(of: tasks.map(\.id)) { _, ids in
            if selectedTaskID == nil || !(selectedTaskID.map { ids.contains($0) } ?? false) {
                selectedTaskID = ids.first
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title)
                    .foregroundColor(NV.green)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("小隊長作業面板"))
                        .font(.title2.bold())
                    Text("\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                connectionBadge
            }
            HStack(spacing: 10) {
                SquadStatTile(icon: "checklist.checked", title: L("待辦"), value: "\(tasks.count)", color: NV.command)
                SquadStatTile(icon: "building.2", title: L("工作點"), value: "\(worksites.count)", color: NV.info)
                SquadStatTile(icon: "cross.case.fill", title: L("後送"), value: "\(vm.usarStore.medicalTransfers.count)", color: NV.danger)
                SquadStatTile(icon: "network", title: L("封包"), value: "\(vm.usarMessageLog.count)", color: NV.green)
            }
        }
    }

    private var connectionBadge: some View {
        Label(vm.commandClient.isConnected ? L("HQ 已連線") : L("離線"), systemImage: vm.commandClient.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((vm.commandClient.isConnected ? NV.green : Color.secondary).opacity(0.14))
            .foregroundColor(vm.commandClient.isConnected ? NV.green : .secondary)
            .clipShape(Capsule())
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("任務"), systemImage: "checklist")
                .font(.headline)
            if tasks.isEmpty {
                SquadEmptyPanel(icon: "tray.fill", title: L("尚未收到 USAR 任務"), detail: L("UCC 派遣後會出現在這裡。"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        Button {
                            selectedTaskID = task.id
                        } label: {
                            SquadTaskRow(task: task, worksite: vm.usarStore.worksites[task.worksiteID], isSelected: selectedTask?.id == task.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("狀態回報"), systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            if let selectedTask {
                Text(selectedTask.title)
                    .font(.subheadline.bold())
                Text(selectedTask.instructions.isEmpty ? L("無額外指示") : selectedTask.instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField(L("位置描述"), text: $locationDescription)
                .textFieldStyle(.roundedBorder)
            TextField(L("備註"), text: $statusNote)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([SquadOperationalStatus.arrived, .assessing, .searching, .rescuing, .requestingSupport, .paused, .evacuating, .completed]) { status in
                    Button {
                        vm.sendUSARSquadStatus(taskID: selectedTask?.id, status: status, note: statusNote, locationDescription: locationDescription)
                        statusNote = ""
                    } label: {
                        Label(status.displayText, systemImage: icon(for: status))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: status))
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var medicalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("醫療後送"), systemImage: "cross.case.fill")
                .font(.headline)

            if !vm.localPatients.isEmpty {
                Picker(L("本機傷患"), selection: $medicalVictimID) {
                    Text(L("手動輸入")).tag("")
                    ForEach(vm.localPatients) { patient in
                        Text(patient.name.isEmpty ? patient.patientId : "\(patient.patientId) · \(patient.name)")
                            .tag(patient.patientId)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField(L("傷患 ID / NFC ID"), text: $medicalVictimID)
                .textFieldStyle(.roundedBorder)
            TextField(L("檢傷代碼"), text: $medicalTriageCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
            Picker(L("後送狀態"), selection: $medicalStatus) {
                ForEach(MedicalTransferStatus.allCases) { status in
                    Text(status.displayText).tag(status)
                }
            }
            .pickerStyle(.menu)
            TextField(L("目的地 / 交接點"), text: $medicalDestination)
                .textFieldStyle(.roundedBorder)
            TextField(L("醫療備註"), text: $medicalNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                vm.sendUSARMedicalTransfer(
                    taskID: selectedTask?.id,
                    victimID: medicalVictimID,
                    triageCode: medicalTriageCode,
                    status: medicalStatus,
                    toFacilityName: medicalDestination,
                    notes: medicalNotes
                )
                medicalVictimID = ""
                medicalDestination = ""
                medicalNotes = ""
                medicalStatus = .pending
            } label: {
                Label(L("送出醫療後送"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.danger)
            .disabled(medicalVictimID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var resourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("資源請求"), systemImage: "shippingbox.fill")
                .font(.headline)
            TextField(L("資源名稱"), text: $resourceType)
                .textFieldStyle(.roundedBorder)
            Stepper(value: $resourceQuantity, in: 1...99) {
                Text(L("數量：%lld", resourceQuantity))
            }
            TextField(L("用途 / 理由"), text: $resourceReason)
                .textFieldStyle(.roundedBorder)
            Button {
                vm.sendUSARResourceRequest(taskID: selectedTask?.id, resourceType: resourceType, quantity: resourceQuantity, reason: resourceReason)
                resourceType = ""
                resourceQuantity = 1
                resourceReason = ""
            } label: {
                Label(L("送出資源請求"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.reinforce)
            .disabled(resourceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var recentPackets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("最近 USAR 封包"), systemImage: "network")
                .font(.headline)
            if vm.usarMessageLog.isEmpty {
                SquadEmptyPanel(icon: "network", title: L("尚無封包"), detail: L("收到或送出 USAR 訊息後會列出。"))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.usarMessageLog.prefix(6), id: \.messageID) { payload in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .foregroundColor(NV.info)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payload.messageType)
                                    .font(.caption.bold())
                                Text("\(payload.originRole) → \(payload.targetRole ?? "*")")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func icon(for status: SquadOperationalStatus) -> String {
        switch status {
        case .standby: return "pause.circle.fill"
        case .enRoute: return "arrow.forward.circle.fill"
        case .arrived: return "mappin.circle.fill"
        case .assessing: return "magnifyingglass.circle.fill"
        case .searching: return "binoculars.fill"
        case .rescuing: return "cross.case.fill"
        case .treating: return "heart.text.square.fill"
        case .requestingSupport: return "person.badge.plus"
        case .paused: return "pause.fill"
        case .evacuating: return "figure.run.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func color(for status: SquadOperationalStatus) -> Color {
        switch status {
        case .requestingSupport: return NV.reinforce
        case .paused, .evacuating: return NV.warning
        case .completed: return NV.green
        case .rescuing, .treating: return NV.danger
        default: return NV.command
        }
    }
}

private struct SquadStatTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

private struct SquadTaskRow: View {
    let task: SquadTask
    let worksite: Worksite?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(task.kind.displayText)
                    .font(.caption.bold())
                    .foregroundColor(NV.command)
                Spacer()
                Text(task.status.displayText)
                    .font(.caption.bold())
                    .foregroundColor(task.status == .completed ? NV.green : NV.info)
            }
            Text(task.title)
                .font(.headline)
                .foregroundColor(.primary)
            Text(worksite.map { "\($0.code) · \($0.name)" } ?? task.worksiteID)
                .font(.caption)
                .foregroundColor(.secondary)
            if !task.instructions.isEmpty {
                Text(task.instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? NV.command.opacity(0.12) : Color.clear)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? NV.command.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SquadEmptyPanel: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
