import SwiftUI

struct HQZoneMapView: View {
    @ObservedObject var vm: HQViewModel
    @State private var showAddZone = false
    @State private var editingZone: RescueZone?

    private var zones: [RescueZone] {
        vm.disasterSite?.zones ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // 統計條
            statsBar
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider()

            // 分區卡片網格
            ScrollView {
                if zones.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(zones) { zone in
                            ZoneCard(zone: zone, personnel: matchedPersonnel(for: zone)) {
                                editingZone = zone
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(L("分區地圖"))
        .overlay(alignment: .bottomLeading) {
            Button {
                showAddZone = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? NV.green : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("新增搜救分區"))
        }
        .sheet(isPresented: $showAddZone) {
            AddZoneSheet(vm: vm)
        }
        .sheet(item: $editingZone) { zone in
            EditZoneSheet(vm: vm, zone: zone)
        }
    }

    // MARK: - 統計條

    private var statsBar: some View {
        HStack(spacing: 16) {
            ZoneStatLabel(icon: "map.fill", label: L("總分區"), value: "\(zones.count)", color: NV.info)
            ZoneStatLabel(icon: "magnifyingglass", label: L("搜救中"),
                          value: "\(zones.filter { $0.status == .active }.count)", color: NV.green)
            ZoneStatLabel(icon: "checkmark.circle.fill", label: L("已清除"),
                          value: "\(zones.filter { $0.status == .cleared }.count)", color: NV.info)
            ZoneStatLabel(icon: "exclamationmark.triangle.fill", label: L("危險區"),
                          value: "\(zones.filter { $0.status == .dangerous }.count)", color: NV.danger)
            ZoneStatLabel(icon: "person.3.fill", label: L("已指派人員"),
                          value: "\(zones.flatMap(\.assignedPersonnel).count)", color: NV.team)
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text(L("尚未定義搜救分區"))
                .foregroundColor(.secondary)
            Text(L("點按左下角 + 新增分區，或在「災害狀態」頁面中新增"))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func matchedPersonnel(for zone: RescueZone) -> [PersonnelAssignment] {
        vm.personnelAssignments.filter { $0.assignedZone == zone.name }
    }
}

// MARK: - 統計標籤

private struct ZoneStatLabel: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.title3).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(NV.cardPadding)
        .background(.regularMaterial)
        .cornerRadius(NV.cardRadius)
    }
}

// MARK: - 分區卡片

struct ZoneCard: View {
    let zone: RescueZone
    let personnel: [PersonnelAssignment]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // 標題 + 狀態
                HStack {
                    Text(zone.name)
                        .font(.headline)
                    Spacer()
                    Text(zone.status.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(zone.status.color.opacity(NV.tagOpacity))
                        .foregroundColor(zone.status.color)
                        .cornerRadius(NV.tagRadius)
                }

                // 指派人員
                if !personnel.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("指派人員"), systemImage: "person.fill")
                            .font(.caption2).foregroundColor(.secondary)
                        ForEach(personnel) { p in
                            HStack(spacing: 4) {
                                Image(systemName: p.role.icon)
                                    .font(.caption2)
                                    .foregroundColor(NV.info)
                                Text(p.name)
                                    .font(.caption)
                                Text("(\(p.role.label))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                } else if !zone.assignedPersonnel.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(zone.assignedPersonnel.joined(separator: ", "))
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text(L("尚未指派人員"))
                        .font(.caption2).foregroundColor(.secondary)
                }

                // 危害
                if !zone.hazards.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(zone.hazards, id: \.self) { hazard in
                            HStack(spacing: 2) {
                                Image(systemName: hazard.icon)
                                    .font(.caption2)
                                    .foregroundColor(hazard.color)
                                Text(hazard.label)
                                    .font(.caption2)
                                    .foregroundColor(hazard.color)
                            }
                        }
                    }
                }

                // 備註
                if !zone.note.isEmpty {
                    Text(zone.note)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .cornerRadius(NV.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius)
                    .stroke(zone.status.color.opacity(0.4), lineWidth: NV.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新增分區 Sheet

struct AddZoneSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var status: ZoneStatus = .standby
    @State private var note = ""
    @State private var selectedHazards: Set<HazardType> = []

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    TextField(L("分區名稱"), text: $name)
                    Picker(L("狀態"), selection: $status) {
                        ForEach(ZoneStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }

                Section(L("危害因素")) {
                    ForEach(HazardType.allCases, id: \.self) { hazard in
                        Toggle(isOn: Binding(
                            get: { selectedHazards.contains(hazard) },
                            set: { isOn in
                                if isOn { selectedHazards.insert(hazard) }
                                else { selectedHazards.remove(hazard) }
                            }
                        )) {
                            Label(hazard.label, systemImage: hazard.icon)
                        }
                    }
                }

                Section(L("備註")) {
                    TextField(L("備註（選填）"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L("新增搜救分區"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("新增")) {
                        let zone = RescueZone(
                            name: name,
                            status: status,
                            hazards: Array(selectedHazards),
                            note: note
                        )
                        vm.addRescueZone(zone)
                        vm.logEvent(type: .zoneUpdate, title: "新增分區：\(name)", detail: status.label)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }
}

// MARK: - 編輯分區 Sheet

struct EditZoneSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    let zone: RescueZone
    @State private var name: String
    @State private var status: ZoneStatus
    @State private var note: String
    @State private var selectedHazards: Set<HazardType>
    @State private var assignedNames: String

    init(vm: HQViewModel, zone: RescueZone) {
        self._vm = ObservedObject(wrappedValue: vm)
        self.zone = zone
        self._name = State(initialValue: zone.name)
        self._status = State(initialValue: zone.status)
        self._note = State(initialValue: zone.note)
        self._selectedHazards = State(initialValue: Set(zone.hazards))
        self._assignedNames = State(initialValue: zone.assignedPersonnel.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    TextField(L("分區名稱"), text: $name)
                    Picker(L("狀態"), selection: $status) {
                        ForEach(ZoneStatus.allCases, id: \.self) { s in
                            HStack {
                                Circle().fill(s.color).frame(width: 8, height: 8)
                                Text(s.label)
                            }.tag(s)
                        }
                    }
                }

                Section(L("指派人員")) {
                    TextField(L("人員名稱（逗號分隔）"), text: $assignedNames)
                    if !vm.personnelAssignments.isEmpty {
                        Text(L("已配置人員：%@", vm.personnelAssignments.filter { $0.assignedZone == zone.name }.map(\.name).joined(separator: ", ")))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(L("危害因素")) {
                    ForEach(HazardType.allCases, id: \.self) { hazard in
                        Toggle(isOn: Binding(
                            get: { selectedHazards.contains(hazard) },
                            set: { isOn in
                                if isOn { selectedHazards.insert(hazard) }
                                else { selectedHazards.remove(hazard) }
                            }
                        )) {
                            Label(hazard.label, systemImage: hazard.icon)
                        }
                    }
                }

                Section(L("備註")) {
                    TextField(L("備註（選填）"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button(role: .destructive) {
                        vm.disasterSite?.zones.removeAll { $0.id == zone.id }
                        if let site = vm.disasterSite {
                            vm.updateDisasterSite(site)
                        }
                        vm.logEvent(type: .zoneUpdate, title: "刪除分區：\(zone.name)")
                        dismiss()
                    } label: {
                        Label(L("刪除分區"), systemImage: "trash")
                            .foregroundColor(NV.danger)
                    }
                }
            }
            .navigationTitle(L("編輯分區"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("儲存")) {
                        saveChanges()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    private func saveChanges() {
        guard var site = vm.disasterSite,
              let idx = site.zones.firstIndex(where: { $0.id == zone.id }) else { return }

        let personnel = assignedNames.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        site.zones[idx].name = name
        site.zones[idx].status = status
        site.zones[idx].note = note
        site.zones[idx].hazards = Array(selectedHazards)
        site.zones[idx].assignedPersonnel = personnel

        vm.updateDisasterSite(site)
        vm.logEvent(type: .zoneUpdate, title: "更新分區：\(name)", detail: status.label)
        dismiss()
    }
}
