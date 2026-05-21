import SwiftUI

// MARK: - 前線災情檢視（唯讀，來自 HQ）

struct FieldDisasterView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var showHazardReport = false

    var body: some View {
        ScrollView {
            if let site = vm.disasterSite {
                VStack(alignment: .leading, spacing: 16) {
                    // 建物資訊
                    GroupBox(label: Label(L("建物資訊"), systemImage: "building.2")) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !site.buildingName.isEmpty {
                                HStack {
                                    Text(L("名稱")).font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(site.buildingName).bold()
                                }
                            }
                            if !site.address.isEmpty {
                                HStack {
                                    Text(L("地址")).font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(site.address)
                                }
                            }
                            HStack {
                                Text(L("倒塌類型")).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(site.collapseType.label)
                                    .bold()
                                    .foregroundColor(NV.warning)
                            }
                            HStack {
                                Text(L("影響樓層")).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(L("地上 %lldF / 地下 %lldF", site.aboveGroundFloors, site.undergroundFloors))
                                    .bold()
                            }
                        }
                    }

                    // 樓層狀態
                    if !site.floors.isEmpty {
                        GroupBox(label: Label(L("樓層狀態"), systemImage: "square.stack.3d.up")) {
                            ForEach(site.floors) { floor in
                                HStack {
                                    Text(floor.id).font(.headline).frame(width: 40)
                                    Text(floor.condition.label)
                                        .font(.caption).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(floor.condition.color.opacity(0.2))
                                        .foregroundColor(floor.condition.color)
                                        .cornerRadius(4)
                                    Spacer()
                                    if !floor.note.isEmpty {
                                        Text(floor.note).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // 救援分區
                    if !site.zones.isEmpty {
                        GroupBox(label: Label(L("救援分區"), systemImage: "map")) {
                            ForEach(site.zones) { zone in
                                HStack {
                                    Text(zone.name).font(.subheadline).bold()
                                    Spacer()
                                    Text(zone.status.label)
                                        .font(.caption).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(zone.status.color.opacity(0.2))
                                        .foregroundColor(zone.status.color)
                                        .cornerRadius(4)
                                    if !zone.assignedPersonnel.isEmpty {
                                        Text(zone.assignedPersonnel.joined(separator: ", ")).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // 危害
                    if !site.hazards.isEmpty {
                        GroupBox(label: Label(L("已知危害"), systemImage: "exclamationmark.shield")) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                                ForEach(site.hazards, id: \.self) { hazard in
                                    HStack(spacing: 4) {
                                        Image(systemName: hazard.icon)
                                        Text(hazard.label).font(.caption)
                                    }
                                    .padding(6)
                                    .background(hazard.color.opacity(0.15))
                                    .foregroundColor(hazard.color)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }

                    // 出入口
                    if !site.entryPoints.isEmpty {
                        GroupBox(label: Label(L("出入口"), systemImage: "door.left.hand.open")) {
                            ForEach(site.entryPoints) { entry in
                                HStack {
                                    Image(systemName: entry.isAccessible ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(entry.isAccessible ? NV.green : NV.danger)
                                    Text(entry.name)
                                    Spacer()
                                    Text(entry.isAccessible ? L("可通行") : L("封閉"))
                                        .font(.caption)
                                        .foregroundColor(entry.isAccessible ? NV.green : NV.danger)
                                }
                            }
                        }
                    }

                    // 集結點
                    if !site.rallyPoint.isEmpty {
                        GroupBox(label: Label(L("集結點"), systemImage: "flag.fill")) {
                            Text(site.rallyPoint)
                                .font(.headline)
                        }
                    }

                    // 備註
                    if !site.note.isEmpty {
                        GroupBox(label: Label(L("備註"), systemImage: "note.text")) {
                            Text(site.note)
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "building.2")
                        .font(.system(size: 50)).foregroundColor(.secondary)
                    Text(L("尚未收到災情資訊"))
                        .font(.headline).foregroundColor(.secondary)
                    Text(L("連線指揮中心後將自動接收"))
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            }
        }
        .outerNavigationTitle(L("全區災情概況"))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showHazardReport = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .disabled(!vm.commandClient.isConnected)
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
        .sheet(isPresented: $showHazardReport) {
            HazardReportSheet(vm: vm)
        }
    }
}

// MARK: - 危險回報表單

struct HazardReportSheet: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: HazardType = .gasLeak
    @State private var severity: HazardSeverity = .medium
    @State private var zone = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("危害類型"), selection: $selectedType) {
                    ForEach(HazardType.allCases, id: \.self) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }

                Picker(L("嚴重程度"), selection: $severity) {
                    ForEach(HazardSeverity.allCases, id: \.self) { sev in
                        Text(sev.label).tag(sev)
                    }
                }

                TextField(L("區域"), text: $zone)
                TextField(L("描述"), text: $description, axis: .vertical)
                    .lineLimit(2...4)

                Section(L("照片附件")) {
                    ReportPhotoAttachmentView(
                        vm: vm,
                        reportType: L("危險回報"),
                        context: "\(selectedType.label) \(zone.trimmingCharacters(in: .whitespacesAndNewlines)) \(description.trimmingCharacters(in: .whitespacesAndNewlines))"
                    )
                }
            }
            .navigationTitle(L("回報危險"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("送出")) {
                        vm.reportHazard(type: selectedType, description: description, zone: zone, severity: severity)
                        dismiss()
                    }
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
        }
    }
}
