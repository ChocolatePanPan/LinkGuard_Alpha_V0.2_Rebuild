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
    @State private var selectedRoleDeviceID = ""
    @State private var selectedUSARRole: UCCRole = .sectorCommander
    @State private var selectedRoleWorksiteID = ""
    @State private var roleDisplayName = ""
    @State private var roleInstructions = ""

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

    private var medicalTransfers: [MedicalTransfer] {
        vm.usarStore.medicalTransfers.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var assessments: [ASRAssessment] {
        vm.usarStore.assessments.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var hazards: [HazardFlag] {
        vm.usarStore.hazards.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var markings: [RCMMarking] {
        vm.usarStore.markings.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var operationalLogs: [OperationalLog] {
        vm.usarStore.operationalLogs.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var roleScopes: [USARRoleScope] {
        vm.usarStore.roleScopes.values.sorted { lhs, rhs in
            if lhs.role.rawValue != rhs.role.rawValue { return lhs.role.rawValue < rhs.role.rawValue }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var assignableRoles: [UCCRole] { [.sectorCommander, .worksiteManager, .squadLeader] }

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
                StatLabel(icon: "person.badge.key.fill", label: L("角色"), value: "\(roleScopes.count)", color: NV.team)
                StatLabel(icon: "checklist.checked", label: L("任務"), value: "\(tasks.count)", color: NV.green)
                StatLabel(icon: "dot.radiowaves.left.and.right", label: L("狀態回報"), value: "\(latestStatuses.count)", color: NV.info)
                StatLabel(icon: "magnifyingglass", label: "ASR", value: "\(assessments.count)", color: NV.team)
                StatLabel(icon: "exclamationmark.triangle.fill", label: L("危害"), value: "\(hazards.count)", color: NV.danger)
                StatLabel(icon: "shippingbox.fill", label: L("資源請求"), value: "\(resourceRequests.count)", color: NV.reinforce)
                StatLabel(icon: "cross.case.fill", label: L("醫療"), value: "\(medicalTransfers.count)", color: NV.danger)
            }

            HQINSARAGBriefPanel(profile: .ucc)

            HStack(alignment: .top, spacing: NV.panelSpacing) {
                worksiteComposer
                roleAssignmentPanel
                squadTaskComposer
            }

            HStack(alignment: .top, spacing: NV.panelSpacing) {
                worksiteBoard
                taskAndStatusBoard
            }

            assessmentAndHazardBoard
            supportAndMedicalBoard
            markingAndLogBoard
            packetLogBoard
        }
        .onAppear {
            if selectedWorksiteID.isEmpty {
                selectedWorksiteID = worksites.first?.id ?? ""
            }
            if selectedDeviceID.isEmpty {
                selectedDeviceID = vm.server.fieldUnits.first?.deviceID ?? ""
            }
            if selectedRoleDeviceID.isEmpty {
                selectedRoleDeviceID = vm.server.fieldUnits.first?.deviceID ?? ""
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
            if selectedRoleDeviceID.isEmpty || !ids.contains(selectedRoleDeviceID) {
                selectedRoleDeviceID = ids.first ?? ""
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

    private var roleAssignmentPanel: some View {
        HQPanel(title: L("角色派令"), icon: "person.badge.key.fill", accent: NV.team) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L("裝置"), selection: $selectedRoleDeviceID) {
                    Text(L("請選擇裝置")).tag("")
                    ForEach(vm.server.fieldUnits) { unit in
                        Text("\(unit.deptCode)-\(unit.deviceID)").tag(unit.deviceID)
                    }
                }
                .pickerStyle(.menu)

                Picker(L("角色"), selection: $selectedUSARRole) {
                    ForEach(assignableRoles, id: \.self) { role in
                        Text(role.displayText).tag(role)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L("工作點"), selection: $selectedRoleWorksiteID) {
                    Text(L("全分區 / 未指定")).tag("")
                    ForEach(worksites) { worksite in
                        Text("\(worksite.code) · \(worksite.name)").tag(worksite.id)
                    }
                }
                .pickerStyle(.menu)

                TextField(L("顯示名稱"), text: $roleDisplayName)
                    .textFieldStyle(.roundedBorder)
                TextField(L("派令備註"), text: $roleInstructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button {
                    vm.assignUSARRole(
                        deviceID: selectedRoleDeviceID,
                        role: selectedUSARRole,
                        worksiteID: selectedRoleWorksiteID.isEmpty ? nil : selectedRoleWorksiteID,
                        displayName: roleDisplayName,
                        instructions: roleInstructions
                    )
                    roleDisplayName = ""
                    roleInstructions = ""
                } label: {
                    Label(L("同步角色"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.team)
                .disabled(selectedRoleDeviceID.isEmpty)

                if !roleScopes.isEmpty {
                    Divider()
                    LazyVStack(spacing: 8) {
                        ForEach(roleScopes.prefix(5)) { scope in
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: scope.role))
                                    .foregroundColor(NV.team)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scope.displayName)
                                        .font(.caption.bold())
                                    Text(scope.role.displayText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(scope.worksiteID.flatMap { vm.usarStore.worksites[$0]?.code } ?? scope.sectorID ?? "-")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .hqThemedSurfaceBackground(opacity: 0.62)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
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

    private var supportAndMedicalBoard: some View {
        HStack(alignment: .top, spacing: NV.panelSpacing) {
            resourceRequestBoard
            medicalTransferBoard
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

    private var medicalTransferBoard: some View {
        HQPanel(title: L("醫療後送"), icon: "cross.case.fill", accent: NV.danger) {
            if medicalTransfers.isEmpty {
                HQEmptyStateView(icon: "cross.case", title: L("尚未收到醫療後送"), minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(medicalTransfers.prefix(8)) { transfer in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "cross.case.fill")
                                .foregroundColor(medicalStatusColor(transfer.status))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(transfer.victimID)
                                        .font(.headline.monospaced())
                                    Text(transfer.triageCode)
                                        .font(.caption2.bold())
                                        .foregroundColor(NV.danger)
                                }
                                Text("\(transfer.status.displayText) · \(transfer.toFacilityName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !transfer.notes.isEmpty {
                                    Text(transfer.notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: transfer.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var markingAndLogBoard: some View {
        HStack(alignment: .top, spacing: NV.panelSpacing) {
            markingBoard
            operationalLogBoard
        }
    }

    private var markingBoard: some View {
        HQPanel(title: L("RCM / 場地標記"), icon: "mappin.and.ellipse", accent: NV.info) {
            if markings.isEmpty {
                HQEmptyStateView(icon: "mappin.and.ellipse", title: L("尚未收到 RCM 標記"), minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(markings.prefix(8)) { marking in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: marking.markingType))
                                .foregroundColor(NV.info)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(marking.code)
                                        .font(.headline.monospaced())
                                    Text(marking.markingType.displayText)
                                        .font(.caption2.bold())
                                        .foregroundColor(NV.info)
                                }
                                Text(worksiteCode(for: marking.worksiteID))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !marking.meaning.isEmpty {
                                    Text(marking.meaning)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: marking.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var operationalLogBoard: some View {
        HQPanel(title: L("SITREP / 作戰日誌"), icon: "doc.text.fill", accent: NV.team) {
            if operationalLogs.isEmpty {
                HQEmptyStateView(icon: "doc.text", title: L("尚未收到 SITREP"), minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(operationalLogs.prefix(8)) { log in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(NV.team)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(log.eventType.displayText)
                                        .font(.caption2.bold())
                                        .foregroundColor(NV.team)
                                    Text(log.title)
                                        .font(.headline)
                                }
                                Text("\(log.sourceRole.displayText) · \(log.sourceID)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !log.detail.isEmpty {
                                    Text(log.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: log.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var assessmentAndHazardBoard: some View {
        HStack(alignment: .top, spacing: NV.panelSpacing) {
            HQPanel(title: L("ASR / 工作點評估"), icon: "magnifyingglass.circle.fill", accent: NV.team) {
                if assessments.isEmpty {
                    HQEmptyStateView(icon: "magnifyingglass", title: L("尚未收到 ASR"), subtitle: L("工作點管理回報 ASR 後會出現在這裡。"), minHeight: 140)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(assessments.prefix(8)) { assessment in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 4) {
                                    Text(assessment.level.displayText)
                                        .font(.headline.monospaced())
                                    Text(assessment.recommendedPriority.displayText)
                                        .font(.caption2.bold())
                                        .foregroundColor(priorityColor(assessment.recommendedPriority))
                                }
                                .frame(width: 66)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(worksiteCode(for: assessment.worksiteID))
                                        .font(.headline)
                                    Text("\(assessment.structureType.displayText) · \(assessment.confidence.displayText)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !assessment.notes.isEmpty {
                                        Text(assessment.notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(Self.timeFormatter.string(from: assessment.timestamp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .hqThemedSurfaceBackground(opacity: 0.68)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            HQPanel(title: L("危害回報"), icon: "exclamationmark.triangle.fill", accent: NV.danger) {
                if hazards.isEmpty {
                    HQEmptyStateView(icon: "exclamationmark.triangle", title: L("尚未收到危害回報"), subtitle: L("工作點管理送出危害後會出現在這裡。"), minHeight: 140)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(hazards.prefix(8)) { hazard in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: hazard.isActive ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                    .foregroundColor(hazard.isActive ? severityColor(hazard.severity) : NV.green)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(hazard.hazardType.displayText)
                                            .font(.headline)
                                        Text(hazard.severity.displayText)
                                            .font(.caption2.bold())
                                            .foregroundColor(severityColor(hazard.severity))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(severityColor(hazard.severity).opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                    Text(worksiteCode(for: hazard.worksiteID))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(hazard.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(Self.timeFormatter.string(from: hazard.timestamp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .hqThemedSurfaceBackground(opacity: 0.68)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
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

    private func severityColor(_ severity: USARHazardSeverity) -> Color {
        switch severity {
        case .monitor: return NV.info
        case .caution: return NV.warning
        case .high: return NV.reinforce
        case .critical: return NV.danger
        }
    }

    private func medicalStatusColor(_ status: MedicalTransferStatus) -> Color {
        switch status {
        case .pending, .packaged: return NV.warning
        case .moving: return NV.reinforce
        case .handedOff, .completed: return NV.green
        case .cancelled: return .secondary
        }
    }

    private func icon(for markingType: RCMMarkingType) -> String {
        switch markingType {
        case .worksiteClassification: return "building.2.fill"
        case .victimLocation: return "person.fill.questionmark"
        case .rapidClearance: return "checkmark.seal.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        case .route: return "arrow.triangle.turn.up.right.circle.fill"
        }
    }

    private func icon(for role: UCCRole) -> String {
        switch role {
        case .sectorCommander, .sectorSafety, .sectorLogistics:
            return "map.fill"
        case .worksiteManager, .searchLead, .rescueLead, .medicalLead, .logisticsLead:
            return "building.2.fill"
        case .squadLeader:
            return "figure.run.circle.fill"
        case .uccCommander, .uccOperations, .uccPlanning, .uccResources, .uccMedical, .uccSafety:
            return "person.3.sequence.fill"
        }
    }

    private func worksiteCode(for worksiteID: String) -> String {
        guard let worksite = vm.usarStore.worksites[worksiteID] else { return worksiteID }
        return "\(worksite.code) · \(worksite.name)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct HQINSARAGBriefPanel: View {
    let profile: INSARAGRoleProfile

    private var brief: INSARAGRoleBrief { profile.brief }

    var body: some View {
        HQPanel(title: brief.title, icon: "checklist.checked", accent: NV.team) {
            VStack(alignment: .leading, spacing: 12) {
                Text(brief.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundColor(NV.team)
                        .frame(width: 22)
                    Text(brief.cycle)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(brief.checklist) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.caption.bold())
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hqThemedSurfaceBackground(opacity: 0.58)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}
