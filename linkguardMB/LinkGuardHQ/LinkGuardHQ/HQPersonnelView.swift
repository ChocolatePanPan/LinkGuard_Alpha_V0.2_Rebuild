import SwiftUI

struct HQPersonnelView: View {
    @ObservedObject var vm: HQViewModel
    @State private var showAddSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 統計
                HStack(spacing: 16) {
                    StatLabel(icon: "person.3.fill", label: L("已配置"), value: "\(vm.personnelAssignments.count)", color: NV.info)
                    StatLabel(icon: "star.fill", label: L("指揮"), value: "\(countByRole(.commander))", color: NV.command)
                    StatLabel(icon: "cross.fill", label: L("醫療"), value: "\(countByRole(.medical))", color: NV.danger)
                }
                .padding(.horizontal)

                // 配置列表
                if vm.personnelAssignments.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.personnelAssignments) { assignment in
                        PersonnelCard(assignment: assignment) {
                            vm.removePersonnelAssignment(assignment.id)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(L("人員配置"))
        .overlay(alignment: .bottomLeading) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? Color.accentColor : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("新增人員配置"))
        }
        .sheet(isPresented: $showAddSheet) {
            AddPersonnelSheet(vm: vm)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text(L("尚未配置人員"))
                .foregroundColor(.secondary)
            Text(L("點按右下角 + 新增人員配置"))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func countByRole(_ role: PersonnelRole) -> Int {
        vm.personnelAssignments.filter { $0.role == role }.count
    }
}

struct StatLabel: View {
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

struct PersonnelCard: View {
    let assignment: PersonnelAssignment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: assignment.role.icon)
                .font(.title2)
                .foregroundColor(NV.info)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.displayLabel)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(assignment.role.label)
                        .font(.caption).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NV.info.opacity(NV.tagOpacity))
                        .cornerRadius(NV.tagRadius)
                    if !assignment.assignedZone.isEmpty {
                        Text(assignment.assignedZone)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !assignment.assignedFloor.isEmpty {
                        Text("\(assignment.assignedFloor)F")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(role: .destructive) { onRemove() } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - 新增人員配置 Sheet

struct AddPersonnelSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var memberName = ""
    @State private var deviceID = ""
    @State private var nickname = ""
    @State private var role: PersonnelRole = .rescue
    @State private var zone = ""
    @State private var floor = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    TextField(L("姓名"), text: $memberName)
                    TextField(L("暱稱（選填，用於 @ 提及）"), text: $nickname)
                    TextField(L("裝置 ID"), text: $deviceID)
                    Picker(L("角色"), selection: $role) {
                        ForEach(PersonnelRole.allCases, id: \.self) { r in
                            Label(r.label, systemImage: r.icon).tag(r)
                        }
                    }
                }
                Section(L("指派位置")) {
                    TextField(L("分區（選填）"), text: $zone)
                    TextField(L("樓層（選填）"), text: $floor)
                }
                Section(L("傳送目標")) {
                    HStack {
                        Image(systemName: vm.targetMode == .broadcast ? "antenna.radiowaves.left.and.right" : "person.2.circle")
                            .foregroundColor(NV.command)
                        Text(vm.targetMode == .broadcast ? L("全體廣播") : L("指定 %lld 台裝置", vm.selectedTargetDeviceIDs.count))
                            .font(.subheadline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("新增人員配置"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("儲存")) {
                        let assignment = PersonnelAssignment(
                            name: memberName,
                            nickname: nickname.isEmpty ? nil : nickname,
                            assignedZone: zone,
                            assignedFloor: floor,
                            role: role
                        )
                        vm.assignPersonnel(assignment)
                        dismiss()
                    }
                    .disabled(memberName.isEmpty)
                }
            }
        }
    }
}
