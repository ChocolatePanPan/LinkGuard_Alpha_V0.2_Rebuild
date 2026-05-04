import SwiftUI

// MARK: - 人員指派操作視圖

struct PersonnelAssignmentView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var showAssignSheet = false
    @State private var editingAssignment: PersonnelAssignment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // 概覽統計
                    summarySection

                    // 按區域分組顯示
                    if !vm.personnelAssignments.isEmpty {
                        zoneGroupedSection
                    }

                    // 未分配人員
                    unassignedSection

                    // 全部人員列表
                    allAssignmentsSection
                }
                .padding(.bottom)
            }
            .navigationTitle(L("人員指派"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingAssignment = nil
                        showAssignSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
            .sheet(isPresented: $showAssignSheet) {
                AssignPersonnelSheet(vm: vm, editing: $editingAssignment)
            }
        }
    }

    // MARK: - 概覽統計

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 角色分佈
            let roleCounts = Dictionary(grouping: vm.personnelAssignments, by: \.role)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PersonnelRole.allCases, id: \.rawValue) { role in
                    let count = roleCounts[role]?.count ?? 0
                    HStack(spacing: 6) {
                        Image(systemName: role.icon)
                            .foregroundColor(NV.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(count)")
                                .font(.title3).bold()
                            Text(role.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 按區域分組

    private var zoneGroupedSection: some View {
        let grouped = Dictionary(grouping: vm.personnelAssignments.filter { !$0.assignedZone.isEmpty }, by: \.assignedZone)

        return VStack(alignment: .leading, spacing: 12) {
            Text(L("區域配置"))
                .font(.headline)
                .padding(.horizontal)

            ForEach(grouped.keys.sorted(), id: \.self) { zone in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(NV.green)
                        Text(zone)
                            .font(.subheadline).bold()
                        Spacer()
                        Text(L("%lld 人", grouped[zone]?.count ?? 0))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(grouped[zone] ?? []) { person in
                        personnelRow(person)
                    }
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 未分配人員

    private var unassignedSection: some View {
        let unassigned = vm.personnelAssignments.filter { $0.assignedZone.isEmpty }

        return Group {
            if !unassigned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill.questionmark")
                            .foregroundColor(NV.warning)
                        Text(L("未分配區域"))
                            .font(.headline)
                        Spacer()
                        Text(L("%lld 人", unassigned.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    ForEach(unassigned) { person in
                        personnelRow(person)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - 全部人員列表

    private var allAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("全部人員 (%lld)", vm.personnelAssignments.count))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if vm.personnelAssignments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("尚無人員配置資料"))
                        .foregroundColor(.secondary)
                    Text(L("可從指揮中心接收，或手動新增"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ForEach(vm.personnelAssignments) { person in
                    personnelRow(person)
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - 人員列

    private func personnelRow(_ person: PersonnelAssignment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: person.role.icon)
                .foregroundColor(NV.green)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayLabel)
                    .font(.subheadline).bold()
                HStack(spacing: 6) {
                    Text(person.role.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .glassEffect(.regular.tint(NV.green.opacity(0.3)), in: .rect(cornerRadius: 4))
                    if !person.assignedFloor.isEmpty {
                        Text(person.assignedFloor)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if !person.assignedZone.isEmpty {
                Text(person.assignedZone)
                    .font(.caption).bold()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular.tint(NV.info.opacity(0.3)), in: .rect(cornerRadius: 6))
            }

            // 編輯按鈕
            Button {
                editingAssignment = person
                showAssignSheet = true
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundColor(NV.greenMedium)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}

// MARK: - 新增/編輯人員指派 Sheet

struct AssignPersonnelSheet: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Binding var editing: PersonnelAssignment?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var nickname = ""
    @State private var selectedRole: PersonnelRole = .search
    @State private var selectedZone = ""
    @State private var selectedFloor = ""

    private var isEditing: Bool { editing != nil }

    private var availableZones: [String] {
        var zones = vm.disasterSite?.zones.map(\.name) ?? []
        if zones.isEmpty {
            zones = [L("A區"), L("B區"), L("C區"), L("D區")]
        }
        return zones
    }

    private var availableFloors: [String] {
        var floors = vm.disasterSite?.floors.map(\.id) ?? []
        if floors.isEmpty {
            floors = ["1F", "2F", "3F", "B1"]
        }
        return floors
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    if !isEditing {
                        TextField(L("姓名/代號"), text: $name)
                    } else {
                        Text(name)
                            .foregroundColor(.secondary)
                    }
                    TextField(L("暱稱（選填，用於 @ 提及）"), text: $nickname)
                }

                Section(L("角色")) {
                    Picker(L("角色"), selection: $selectedRole) {
                        ForEach(PersonnelRole.allCases, id: \.rawValue) { role in
                            Label(role.label, systemImage: role.icon)
                                .tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(L("指派區域")) {
                    Picker(L("區域"), selection: $selectedZone) {
                        Text(L("未指定")).tag("")
                        ForEach(availableZones, id: \.self) { zone in
                            Text(zone).tag(zone)
                        }
                    }

                    Picker(L("樓層"), selection: $selectedFloor) {
                        Text(L("未指定")).tag("")
                        ForEach(availableFloors, id: \.self) { floor in
                            Text(floor).tag(floor)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let id = editing?.id {
                                vm.personnelAssignments.removeAll { $0.id == id }
                            }
                            dismiss()
                        } label: {
                            Label(L("移除此人員"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? L("編輯指派") : L("新增人員"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? L("儲存") : L("新增")) {
                        saveAssignment()
                        dismiss()
                    }
                    .disabled(!isEditing && name.trimmingCharacters(in: .whitespaces).isEmpty)
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
            .onAppear {
                if let edit = editing {
                    name = edit.name
                    nickname = edit.nickname ?? ""
                    selectedRole = edit.role
                    selectedZone = edit.assignedZone
                    selectedFloor = edit.assignedFloor
                }
            }
        }
    }

    private func saveAssignment() {
        if let edit = editing {
            // 更新現有 — 替換整個元素觸發 SwiftUI 更新
            if let idx = vm.personnelAssignments.firstIndex(where: { $0.id == edit.id }) {
                var updated = vm.personnelAssignments[idx]
                updated.nickname = nickname.isEmpty ? nil : nickname
                updated.role = selectedRole
                updated.assignedZone = selectedZone
                updated.assignedFloor = selectedFloor
                var newArray = vm.personnelAssignments
                newArray[idx] = updated
                vm.personnelAssignments = newArray
            }
        } else {
            // 新增
            let assignment = PersonnelAssignment(
                name: name.trimmingCharacters(in: .whitespaces),
                nickname: nickname.isEmpty ? nil : nickname,
                assignedZone: selectedZone,
                assignedFloor: selectedFloor,
                role: selectedRole
            )
            vm.personnelAssignments.append(assignment)
        }
    }
}
