import SwiftUI

// MARK: - 人員總覽

struct HQPersonnelOverviewView: View {
    @ObservedObject var vm: HQViewModel

    @State private var searchText = ""
    @State private var filterOnlineOnly = false
    @State private var filterRole: PersonnelRole? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NV.bg.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HQSectionHeader(L("人員總覽"), icon: "person.3.sequence.fill", accent: NV.team) {
                statsBar
            }

            HStack(spacing: 12) {
                // 搜尋
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(L("搜尋人員 / 裝置 / 部門…"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .hqThemedSurfaceBackground()
                .cornerRadius(8)
                .frame(maxWidth: 300)

                // 上線篩選
                Toggle(L("僅上線"), isOn: $filterOnlineOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                // 角色篩選
                Picker(L("角色"), selection: $filterRole) {
                    Text(L("全部角色")).tag(PersonnelRole?.none)
                    ForEach(PersonnelRole.allCases, id: \.self) { r in
                        Label(r.label, systemImage: r.icon).tag(PersonnelRole?.some(r))
                    }
                }
                .frame(width: 130)
            }
            .padding(.horizontal, NV.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: NV.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.bottom, 14)
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatBadge(label: "外勤裝置", value: "\(vm.server.fieldUnits.count)", color: NV.team)
            StatBadge(label: "上線", value: "\(vm.connectedCount)", color: NV.green)
            StatBadge(label: "團隊成員", value: "\(vm.teamCount)", color: NV.info)
            StatBadge(label: "人員配置", value: "\(vm.personnelAssignments.count)", color: NV.command)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 外勤裝置列表
                fieldUnitsSection
                // 團隊成員列表
                teamMembersSection
                // HQ 人員配置列表
                personnelAssignmentsSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: NV.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - 外勤裝置區段

    private var fieldUnitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("外勤裝置"), systemImage: "iphone.radiowaves.left.and.right")
                .font(.headline)
                .foregroundColor(NV.team)

            let units = filteredFieldUnits
            if units.isEmpty {
                Text(L("無符合條件的外勤裝置"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 8) {
                    ForEach(units) { unit in
                        FieldUnitOverviewCard(unit: unit)
                    }
                }
            }
        }
    }

    private var filteredFieldUnits: [ConnectedFieldUnit] {
        var result = vm.server.fieldUnits
        if filterOnlineOnly { result = result.filter(\.isOnline) }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.deviceID.lowercased().contains(q) ||
                $0.deptCode.lowercased().contains(q)
            }
        }
        return result
    }

    // MARK: - 團隊成員區段

    private var teamMembersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("團隊成員（LoRa 節點）"), systemImage: "person.2.wave.2.fill")
                .font(.headline)
                .foregroundColor(NV.info)

            let members = filteredTeamMembers
            if members.isEmpty {
                Text(L("無符合條件的團隊成員"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 6) {
                    ForEach(members, id: \.id) { m in
                        TeamMemberCard(member: m)
                    }
                }
            }
        }
    }

    private var filteredTeamMembers: [(id: String, deptCode: String, battery: Int, rssi: Double, isOnline: Bool, victimCount: Int, sourceDevice: String)] {
        var result = vm.allTeamOverview
        if filterOnlineOnly { result = result.filter(\.isOnline) }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.id.lowercased().contains(q) ||
                $0.deptCode.lowercased().contains(q) ||
                $0.sourceDevice.lowercased().contains(q)
            }
        }
        return result
    }

    // MARK: - 人員配置區段

    private var personnelAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("人員配置"), systemImage: "person.text.rectangle.fill")
                .font(.headline)
                .foregroundColor(NV.command)

            let assignments = filteredAssignments
            if assignments.isEmpty {
                Text(L("尚無人員配置"))
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 6) {
                    ForEach(assignments) { a in
                        PersonnelAssignmentCard(assignment: a)
                    }
                }
            }
        }
    }

    private var filteredAssignments: [PersonnelAssignment] {
        var result = vm.personnelAssignments
        if let role = filterRole {
            result = result.filter { $0.role == role }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.assignedZone.lowercased().contains(q) ||
                $0.role.label.lowercased().contains(q)
            }
        }
        return result
    }
}

// MARK: - 子元件

private struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).bold().foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

private struct FieldUnitOverviewCard: View {
    let unit: ConnectedFieldUnit

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(unit.isOnline ? NV.green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(unit.deviceID).font(.headline)
                    Text(unit.deptCode)
                        .font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(NV.team.opacity(NV.tagOpacity))
                        .cornerRadius(NV.tagRadius)
                }
                HStack(spacing: 8) {
                    Label("\(unit.battery)%", systemImage: "battery.50")
                        .font(.caption2)
                    Label(L("%lld 受困者", unit.victims.count), systemImage: "person.fill.questionmark")
                        .font(.caption2)
                    Label(L("%lld 隊員", unit.teamMembers.count), systemImage: "person.2.fill")
                        .font(.caption2)
                    if unit.sosCount > 0 {
                        Text("SOS:\(unit.sosCount)")
                            .font(.caption2).bold()
                            .foregroundColor(NV.danger)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: unit.bleConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundColor(unit.bleConnected ? NV.green : .gray)
                .font(.caption)
        }
        .padding(NV.cardPadding)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }
}

private struct TeamMemberCard: View {
    let member: (id: String, deptCode: String, battery: Int, rssi: Double, isOnline: Bool, victimCount: Int, sourceDevice: String)

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(member.isOnline ? NV.green : .gray)
                .frame(width: NV.dotSize, height: NV.dotSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.id).font(.headline)
                HStack(spacing: 6) {
                    Text(member.deptCode)
                        .font(.caption2).bold()
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(NV.team.opacity(NV.tagOpacity))
                        .cornerRadius(NV.tagRadius)
                    Text("← \(member.sourceDevice)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Label("\(member.battery)%", systemImage: "battery.50")
                    .font(.caption2).foregroundColor(member.battery < 20 ? NV.danger : .secondary)
                Text(L("%lld 受困者", member.victimCount))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(NV.cardPadding)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }
}

private struct PersonnelAssignmentCard: View {
    let assignment: PersonnelAssignment
    private var isFieldSynced: Bool { assignment.id.hasPrefix("field-") }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: assignment.role.icon)
                .foregroundColor(isFieldSynced ? NV.team : NV.command)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(assignment.displayLabel).font(.headline)
                    if isFieldSynced {
                        Text(L("外勤"))
                            .font(.caption2).bold()
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(NV.team.opacity(NV.tagOpacity))
                            .cornerRadius(NV.tagRadius)
                    }
                }
                HStack(spacing: 6) {
                    Text(assignment.role.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(NV.command.opacity(NV.tagOpacity))
                        .cornerRadius(NV.tagRadius)
                    if !assignment.assignedZone.isEmpty {
                        Text(assignment.assignedZone)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if !assignment.assignedFloor.isEmpty {
                        Text(assignment.assignedFloor)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(NV.cardPadding)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }
}
