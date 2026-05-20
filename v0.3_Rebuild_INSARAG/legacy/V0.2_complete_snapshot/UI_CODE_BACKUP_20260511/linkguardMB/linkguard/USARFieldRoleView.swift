import SwiftUI

private enum USARFieldRoleMode: String, CaseIterable, Identifiable {
    case sectorCommander
    case worksiteManager
    case squadLeader

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sectorCommander: return L("分區指揮")
        case .worksiteManager: return L("工作點管理")
        case .squadLeader: return L("小隊長")
        }
    }

    var icon: String {
        switch self {
        case .sectorCommander: return "map.fill"
        case .worksiteManager: return "building.2.fill"
        case .squadLeader: return "figure.run.circle.fill"
        }
    }

    init?(role: UCCRole?) {
        switch role {
        case .sectorCommander, .sectorSafety, .sectorLogistics:
            self = .sectorCommander
        case .worksiteManager, .searchLead, .rescueLead, .medicalLead, .logisticsLead:
            self = .worksiteManager
        case .squadLeader:
            self = .squadLeader
        default:
            return nil
        }
    }
}

struct USARFieldRoleView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var roleMode: USARFieldRoleMode = .squadLeader

    var body: some View {
        VStack(spacing: 0) {
            if let scope = vm.currentUSARRoleScope {
                activeRoleBanner(scope)
            }

            Picker(L("角色"), selection: $roleMode) {
                ForEach(USARFieldRoleMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch roleMode {
                case .sectorCommander:
                    SectorCommanderView(vm: vm)
                case .worksiteManager:
                    WorksiteManagerView(vm: vm)
                case .squadLeader:
                    SquadLeaderView(vm: vm)
                }
            }
        }
        .outerNavigationTitle(L("USAR 指揮鏈"))
        .onAppear { syncRoleModeFromAssignment() }
        .onChange(of: vm.currentUSARRoleScope?.role) { _, _ in syncRoleModeFromAssignment() }
    }

    private func activeRoleBanner(_ scope: USARRoleScope) -> some View {
        HStack(spacing: 10) {
            Image(systemName: USARFieldRoleMode(role: scope.role)?.icon ?? roleMode.icon)
                .foregroundColor(NV.team)
            VStack(alignment: .leading, spacing: 2) {
                Text(scope.role.displayText)
                    .font(.caption.bold())
                Text(scope.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(scope.worksiteID ?? scope.sectorID ?? scope.incidentID)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func syncRoleModeFromAssignment() {
        if let assigned = USARFieldRoleMode(role: vm.currentUSARRoleScope?.role) {
            roleMode = assigned
        }
    }
}

private struct SectorCommanderView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var selectedWorksiteID: String?
    @State private var selectedPriority: WorksitePriority = .normal
    @State private var selectedStatus: WorksiteStatus = .assigned
    @State private var sectorNote = ""

    private var worksites: [Worksite] { vm.visibleUSARWorksites }

    private var selectedWorksite: Worksite? {
        if let selectedWorksiteID,
           let worksite = worksites.first(where: { $0.id == selectedWorksiteID }) {
            return worksite
        }
        return worksites.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FieldUSARHeader(
                    icon: "map.fill",
                    title: L("分區指揮"),
                    subtitle: L("工作點排序 / 優先序 / 分區狀態"),
                    stats: [
                        .init(icon: "building.2.fill", title: L("工作點"), value: "\(worksites.count)", color: NV.command),
                        .init(icon: "exclamationmark.triangle.fill", title: L("危害"), value: "\(vm.usarStore.hazards.count)", color: NV.danger),
                        .init(icon: "shippingbox.fill", title: L("資源"), value: "\(vm.usarStore.resourceRequests.count)", color: NV.reinforce)
                    ]
                )

                worksiteList
                FieldINSARAGBriefPanel(profile: .sector, accent: NV.command)
                FieldUSAROperationalLogPanel(
                    vm: vm,
                    worksite: selectedWorksite,
                    taskID: nil,
                    originRole: .sectorCommander,
                    accent: NV.command
                )
                sectorControlPanel
                FieldSquadTaskComposer(
                    vm: vm,
                    worksite: selectedWorksite,
                    originRole: .sectorCommander,
                    accent: NV.command
                )
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear { syncSelection() }
        .onChange(of: worksites.map(\.id)) { _, _ in syncSelection() }
        .onChange(of: selectedWorksite?.id) { _, _ in syncFormFromSelection() }
    }

    private var worksiteList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("工作點"), systemImage: "building.2")
                .font(.headline)
            if worksites.isEmpty {
                FieldUSAREmptyPanel(icon: "building.2", title: L("尚未收到工作點"), detail: L("UCC 建立工作點後，分區指揮會在這裡排序與更新。"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(worksites) { worksite in
                        Button {
                            selectedWorksiteID = worksite.id
                        } label: {
                            FieldUSARWorksiteRow(worksite: worksite, isSelected: selectedWorksite?.id == worksite.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sectorControlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("分區更新"), systemImage: "slider.horizontal.3")
                .font(.headline)
            if let selectedWorksite {
                Text("\(selectedWorksite.code) · \(selectedWorksite.name)")
                    .font(.subheadline.bold())
            }
            Picker(L("優先序"), selection: $selectedPriority) {
                ForEach(WorksitePriority.allCases) { priority in
                    Text(priority.displayText).tag(priority)
                }
            }
            .pickerStyle(.segmented)

            Picker(L("狀態"), selection: $selectedStatus) {
                ForEach([WorksiteStatus.assigned, .assessing, .searching, .rescuing, .paused, .evacuated, .completed]) { status in
                    Text(status.displayText).tag(status)
                }
            }
            .pickerStyle(.menu)

            TextField(L("分區備註"), text: $sectorNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let selectedWorksite else { return }
                vm.sendUSARWorksiteUpdate(
                    worksiteID: selectedWorksite.id,
                    status: selectedStatus,
                    priority: selectedPriority,
                    victimCount: selectedWorksite.victimCount,
                    note: sectorNote,
                    originRole: .sectorCommander
                )
                sectorNote = ""
            } label: {
                Label(L("送出分區更新"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.command)
            .disabled(selectedWorksite == nil)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func syncSelection() {
        if selectedWorksiteID == nil || !(selectedWorksiteID.map { id in worksites.contains { $0.id == id } } ?? false) {
            selectedWorksiteID = worksites.first?.id
        }
        syncFormFromSelection()
    }

    private func syncFormFromSelection() {
        guard let selectedWorksite else { return }
        selectedPriority = selectedWorksite.priority
        selectedStatus = selectedWorksite.status == .unassigned ? .assigned : selectedWorksite.status
    }
}

private struct WorksiteManagerView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var selectedWorksiteID: String?
    @State private var worksiteStatus: WorksiteStatus = .assessing
    @State private var worksitePriority: WorksitePriority = .normal
    @State private var victimCount = 0
    @State private var worksiteNote = ""
    @State private var asrLevel: ASRLevel = .level2
    @State private var structureType: StructureType = .unknown
    @State private var asrPriority: WorksitePriority = .normal
    @State private var asrNotes = ""
    @State private var hazardType: USARHazardType = .structuralInstability
    @State private var hazardSeverity: USARHazardSeverity = .caution
    @State private var hazardDescription = ""
    @State private var hazardMitigation = ""

    private var worksites: [Worksite] { vm.visibleUSARWorksites }

    private var selectedWorksite: Worksite? {
        if let selectedWorksiteID,
           let worksite = worksites.first(where: { $0.id == selectedWorksiteID }) {
            return worksite
        }
        return worksites.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FieldUSARHeader(
                    icon: "building.2.fill",
                    title: L("工作點管理"),
                    subtitle: L("ASR / 危害 / 工作點狀態"),
                    stats: [
                        .init(icon: "magnifyingglass", title: "ASR", value: "\(vm.usarStore.assessments.count)", color: NV.info),
                        .init(icon: "exclamationmark.triangle.fill", title: L("危害"), value: "\(vm.usarStore.hazards.count)", color: NV.danger),
                        .init(icon: "person.fill.questionmark", title: L("估計受困"), value: "\(worksites.reduce(0) { $0 + $1.victimCount })", color: NV.warning)
                    ]
                )

                worksitePicker
                FieldINSARAGBriefPanel(profile: .worksite, accent: NV.green)
                worksiteUpdatePanel
                FieldSquadTaskComposer(
                    vm: vm,
                    worksite: selectedWorksite,
                    originRole: .worksiteManager,
                    accent: NV.green
                )
                asrPanel
                hazardPanel
                FieldRCMMarkingPanel(vm: vm, worksite: selectedWorksite, originRole: .worksiteManager, accent: NV.info)
                FieldUSAROperationalLogPanel(
                    vm: vm,
                    worksite: selectedWorksite,
                    taskID: nil,
                    originRole: .worksiteManager,
                    accent: NV.green
                )
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear { syncSelection() }
        .onChange(of: worksites.map(\.id)) { _, _ in syncSelection() }
        .onChange(of: selectedWorksite?.id) { _, _ in syncFormFromSelection() }
    }

    private var worksitePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("工作點"), systemImage: "building.2")
                .font(.headline)
            if worksites.isEmpty {
                FieldUSAREmptyPanel(icon: "building.2", title: L("尚未收到工作點"), detail: L("UCC 建立或分區指派後，工作點管理可在此更新。"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(worksites) { worksite in
                        Button { selectedWorksiteID = worksite.id } label: {
                            FieldUSARWorksiteRow(worksite: worksite, isSelected: selectedWorksite?.id == worksite.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var worksiteUpdatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("工作點狀態"), systemImage: "flag.fill")
                .font(.headline)
            Picker(L("狀態"), selection: $worksiteStatus) {
                ForEach([WorksiteStatus.assessing, .searching, .rescuing, .paused, .evacuated, .completed]) { status in
                    Text(status.displayText).tag(status)
                }
            }
            .pickerStyle(.segmented)

            Picker(L("優先序"), selection: $worksitePriority) {
                ForEach(WorksitePriority.allCases) { priority in
                    Text(priority.displayText).tag(priority)
                }
            }
            .pickerStyle(.menu)

            Stepper(value: $victimCount, in: 0...999) {
                Text(L("估計受困：%lld", victimCount))
            }

            TextField(L("工作點備註 / 位置細節"), text: $worksiteNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let selectedWorksite else { return }
                vm.sendUSARWorksiteUpdate(
                    worksiteID: selectedWorksite.id,
                    status: worksiteStatus,
                    priority: worksitePriority,
                    victimCount: victimCount,
                    note: worksiteNote,
                    originRole: .worksiteManager
                )
                worksiteNote = ""
            } label: {
                Label(L("送出工作點狀態"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.green)
            .disabled(selectedWorksite == nil)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var asrPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("ASR 回報"), systemImage: "magnifyingglass.circle.fill")
                .font(.headline)

            Picker("ASR", selection: $asrLevel) {
                ForEach(ASRLevel.allCases) { level in
                    Text(level.displayText).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Picker(L("構造"), selection: $structureType) {
                ForEach(StructureType.allCases) { type in
                    Text(type.displayText).tag(type)
                }
            }
            .pickerStyle(.menu)

            Picker(L("建議優先序"), selection: $asrPriority) {
                ForEach(WorksitePriority.allCases) { priority in
                    Text(priority.displayText).tag(priority)
                }
            }
            .pickerStyle(.menu)

            TextField(L("ASR 備註"), text: $asrNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let selectedWorksite else { return }
                vm.sendUSARASRObservation(
                    worksiteID: selectedWorksite.id,
                    level: asrLevel,
                    structureType: structureType,
                    recommendedPriority: asrPriority,
                    notes: asrNotes
                )
                asrNotes = ""
            } label: {
                Label(L("送出 ASR"), systemImage: "paperplane.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.info)
            .disabled(selectedWorksite == nil)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var hazardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("危害回報"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Picker(L("危害"), selection: $hazardType) {
                ForEach(USARHazardType.allCases) { type in
                    Text(type.displayText).tag(type)
                }
            }
            .pickerStyle(.menu)
            Picker(L("嚴重度"), selection: $hazardSeverity) {
                ForEach(USARHazardSeverity.allCases) { severity in
                    Text(severity.displayText).tag(severity)
                }
            }
            .pickerStyle(.segmented)
            TextField(L("危害描述"), text: $hazardDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField(L("控制措施"), text: $hazardMitigation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button {
                guard let selectedWorksite else { return }
                vm.sendUSARHazardReport(
                    worksiteID: selectedWorksite.id,
                    hazardType: hazardType,
                    severity: hazardSeverity,
                    description: hazardDescription,
                    mitigation: hazardMitigation
                )
                hazardDescription = ""
                hazardMitigation = ""
            } label: {
                Label(L("送出危害"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.danger)
            .disabled(selectedWorksite == nil || hazardDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func syncSelection() {
        if selectedWorksiteID == nil || !(selectedWorksiteID.map { id in worksites.contains { $0.id == id } } ?? false) {
            selectedWorksiteID = worksites.first?.id
        }
        syncFormFromSelection()
    }

    private func syncFormFromSelection() {
        guard let selectedWorksite else { return }
        worksiteStatus = selectedWorksite.status == .unassigned ? .assessing : selectedWorksite.status
        worksitePriority = selectedWorksite.priority
        asrPriority = selectedWorksite.priority
        victimCount = selectedWorksite.victimCount
    }
}

struct FieldINSARAGBriefPanel: View {
    let profile: INSARAGRoleProfile
    let accent: Color

    private var brief: INSARAGRoleBrief { profile.brief }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist.checked")
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(brief.title)
                        .font(.headline)
                    Text(brief.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(accent)
                    .frame(width: 18)
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
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct FieldRCMMarkingPanel: View {
    @ObservedObject var vm: LinkGuardViewModel
    let worksite: Worksite?
    let originRole: UCCRole
    let accent: Color
    @State private var markingType: RCMMarkingType = .worksiteClassification
    @State private var markingCode = ""
    @State private var markingMeaning = ""
    @State private var markingLocation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("RCM / 場地標記"), systemImage: "mappin.and.ellipse")
                .font(.headline)
            if let worksite {
                Text("\(worksite.code) · \(worksite.name)")
                    .font(.subheadline.bold())
            }
            Picker(L("標記類型"), selection: $markingType) {
                ForEach(RCMMarkingType.allCases) { type in
                    Text(type.displayText).tag(type)
                }
            }
            .pickerStyle(.menu)
            TextField(L("標記代碼 / 符號"), text: $markingCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
            TextField(L("標記意義"), text: $markingMeaning, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField(L("標記位置"), text: $markingLocation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button {
                guard let worksite else { return }
                vm.sendUSARMarkingUpdate(
                    worksiteID: worksite.id,
                    markingType: markingType,
                    code: markingCode,
                    meaning: markingMeaning,
                    locationDescription: markingLocation,
                    originRole: originRole
                )
                markingCode = ""
                markingMeaning = ""
                markingLocation = ""
            } label: {
                Label(L("送出 RCM 標記"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(worksite == nil || markingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct FieldUSAROperationalLogPanel: View {
    @ObservedObject var vm: LinkGuardViewModel
    let worksite: Worksite?
    let taskID: String?
    let originRole: UCCRole
    let accent: Color
    @State private var eventType: OperationalLogType = .status
    @State private var logTitle = ""
    @State private var logDetail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(L("SITREP / 作戰日誌"), systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Text(originRole.displayText)
                    .font(.caption2.bold())
                    .foregroundColor(accent)
            }
            if let worksite {
                Text("\(worksite.code) · \(worksite.name)")
                    .font(.subheadline.bold())
            }
            Picker(L("事件類型"), selection: $eventType) {
                ForEach(OperationalLogType.allCases) { type in
                    Text(type.displayText).tag(type)
                }
            }
            .pickerStyle(.menu)
            TextField(L("回報標題"), text: $logTitle)
                .textFieldStyle(.roundedBorder)
            TextField(L("回報內容"), text: $logDetail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button {
                vm.sendUSAROperationalLog(
                    eventType: eventType,
                    title: logTitle,
                    detail: logDetail,
                    worksiteID: worksite?.id,
                    taskID: taskID,
                    originRole: originRole
                )
                logTitle = ""
                logDetail = ""
            } label: {
                Label(L("送出 SITREP"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(logTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

private struct FieldSquadTaskComposer: View {
    @ObservedObject var vm: LinkGuardViewModel
    let worksite: Worksite?
    let originRole: UCCRole
    let accent: Color
    @State private var targetDeviceID = ""
    @State private var taskKind: SquadTaskKind = .assess
    @State private var taskTitle = ""
    @State private var taskInstructions = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(L("小隊任務"), systemImage: "figure.run.circle.fill")
                    .font(.headline)
                Spacer()
                Text(originRole.displayText)
                    .font(.caption2.bold())
                    .foregroundColor(accent)
            }

            if let worksite {
                Text("\(worksite.code) · \(worksite.name)")
                    .font(.subheadline.bold())
            }

            TextField(L("小隊長裝置 ID / SQ-ID"), text: $targetDeviceID)
                .textFieldStyle(.roundedBorder)

            Picker(L("任務類型"), selection: $taskKind) {
                ForEach(SquadTaskKind.allCases) { kind in
                    Text(kind.displayText).tag(kind)
                }
            }
            .pickerStyle(.menu)

            TextField(L("任務標題"), text: $taskTitle)
                .textFieldStyle(.roundedBorder)
            TextField(L("任務指示"), text: $taskInstructions, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let worksite else { return }
                vm.sendUSARSquadTask(
                    worksiteID: worksite.id,
                    targetDeviceID: targetDeviceID,
                    kind: taskKind,
                    title: taskTitle,
                    instructions: taskInstructions,
                    originRole: originRole
                )
                taskTitle = ""
                taskInstructions = ""
            } label: {
                Label(L("派發小隊任務"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(worksite == nil
                      || targetDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

private struct FieldUSARStat {
    let icon: String
    let title: String
    let value: String
    let color: Color
}

private struct FieldUSARHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let stats: [FieldUSARStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(NV.command)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    FieldUSARStatTile(icon: stat.icon, title: stat.title, value: stat.value, color: stat.color)
                }
            }
        }
    }
}

private struct FieldUSARStatTile: View {
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

private struct FieldUSARWorksiteRow: View {
    let worksite: Worksite
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(worksite.code)
                    .font(.headline.monospaced())
                    .foregroundColor(NV.command)
                Text(worksite.priority.displayText)
                    .font(.caption.bold())
                    .foregroundColor(priorityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.14))
                    .clipShape(Capsule())
                Spacer()
                Text(worksite.status.displayText)
                    .font(.caption.bold())
                    .foregroundColor(NV.info)
            }
            Text(worksite.name)
                .font(.headline)
                .foregroundColor(.primary)
            Text(worksite.address.isEmpty ? L("未填位置") : worksite.address)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Label("\(worksite.victimCount)", systemImage: "person.fill.questionmark")
                if let asr = worksite.currentASRLevel {
                    Label(asr.displayText, systemImage: "magnifyingglass")
                }
                Label("\(worksite.hazardIDs.count)", systemImage: "exclamationmark.triangle.fill")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
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

    private var priorityColor: Color {
        switch worksite.priority {
        case .immediate: return NV.danger
        case .high: return NV.reinforce
        case .normal: return NV.green
        case .low: return NV.info
        case .deferred: return .secondary
        }
    }
}

private struct FieldUSAREmptyPanel: View {
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
