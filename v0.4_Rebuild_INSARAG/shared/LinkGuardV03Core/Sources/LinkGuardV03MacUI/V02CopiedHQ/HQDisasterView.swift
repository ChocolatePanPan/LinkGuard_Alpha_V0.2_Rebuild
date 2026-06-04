import SwiftUI

struct HQDisasterView: View {
    @ObservedObject var vm: HQViewModel
    @State private var editingSite: DisasterSite
    @State private var showAddZone = false
    @State private var showAddFloor = false
    @State private var newZoneName = ""
    @State private var newFloorNumber = 1
    @State private var newFloorCondition: FloorCondition = .unknown

    init(vm: HQViewModel) {
        self._vm = ObservedObject(wrappedValue: vm)
        self._editingSite = State(initialValue: vm.disasterSite ?? DisasterSite())
    }

    var body: some View {
        HQPage(spacing: NV.pageSpacing) {
            HQPageHeader(L("災害狀態"), icon: "building.2", accent: NV.warning)

            buildingInfoSection
            floorSection
            zoneSection
            hazardSection
            HQInlinePhotoStrip(
                vm: vm,
                reportType: "危險回報",
                keywords: disasterPhotoKeywords,
                title: L("現場照片")
            )
            entryPointSection
            miscSection

            DeviceTargetSelector(
                targetMode: $vm.targetMode,
                selectedIDs: $vm.selectedTargetDeviceIDs,
                fieldUnits: vm.server.fieldUnits
            )

            Button {
                vm.updateDisasterSite(editingSite)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(vm.targetMode == .broadcast ? L("儲存並廣播災情狀態") : L("發送至 %lld 台裝置", vm.selectedTargetDeviceIDs.count))
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.warning)
            .disabled(!vm.server.isRunning)
        }
    }

    // MARK: - 建物資訊

    private var buildingInfoSection: some View {
        GroupBox(label: Label(L("建物資訊"), systemImage: "building.2")) {
            VStack(spacing: 10) {
                TextField(L("建物名稱"), text: $editingSite.buildingName)
                    .textFieldStyle(.roundedBorder)
                TextField(L("地址"), text: $editingSite.address)
                    .textFieldStyle(.roundedBorder)

                Picker(L("倒塌類型"), selection: $editingSite.collapseType) {
                    ForEach(CollapseType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(L("影響樓層"))
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Stepper(L("地上 %lldF", editingSite.aboveGroundFloors), value: $editingSite.aboveGroundFloors, in: 1...50)
                    Text("·")
                    Stepper(L("地下 B%lldF", editingSite.undergroundFloors), value: $editingSite.undergroundFloors, in: 0...10)
                }
            }
        }
    }

    // MARK: - 樓層狀態

    private var floorSection: some View {
        GroupBox(label: Label(L("樓層狀態"), systemImage: "square.stack.3d.up")) {
            VStack(spacing: 8) {
                ForEach(editingSite.floors.indices, id: \.self) { i in
                    HStack {
                        Text("\(editingSite.floors[i].id)")
                            .font(.headline).frame(width: 40)
                        Picker("", selection: $editingSite.floors[i].condition) {
                            ForEach(FloorCondition.allCases, id: \.self) { c in
                                Text(c.label).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        TextField(L("備註"), text: $editingSite.floors[i].note)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                    }
                }

                Button {
                    editingSite.floors.append(FloorStatus(id: "\(newFloorNumber)F", condition: .unknown))
                    newFloorNumber += 1
                } label: {
                    Label(L("新增樓層"), systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - 救援分區

    private var zoneSection: some View {
        GroupBox(label: Label(L("救援分區"), systemImage: "map")) {
            VStack(spacing: 8) {
                ForEach(editingSite.zones.indices, id: \.self) { i in
                    HStack {
                        Text(editingSite.zones[i].name)
                            .font(.subheadline).bold()
                        Spacer()
                        Picker("", selection: $editingSite.zones[i].status) {
                            ForEach(ZoneStatus.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack {
                    TextField(L("新分區名稱"), text: $newZoneName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !newZoneName.isEmpty else { return }
                        editingSite.zones.append(RescueZone(name: newZoneName))
                        newZoneName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newZoneName.isEmpty)
                }
            }
        }
    }

    // MARK: - 危害類型

    private var hazardSection: some View {
        GroupBox(label: Label(L("已知危害"), systemImage: "exclamationmark.shield")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(HazardType.allCases, id: \.self) { hazard in
                    let isSelected = editingSite.hazards.contains(hazard)
                    Button {
                        if isSelected {
                            editingSite.hazards.removeAll { $0 == hazard }
                        } else {
                            editingSite.hazards.append(hazard)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hazard.icon)
                            Text(hazard.label)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isSelected ? hazard.color.opacity(NV.tagOpacity) : Color.gray.opacity(0.1))
                        .foregroundColor(isSelected ? hazard.color : .secondary)
                        .cornerRadius(NV.tagRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: NV.tagRadius)
                                .stroke(isSelected ? hazard.color : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 出入口

    private var entryPointSection: some View {
        GroupBox(label: Label(L("出入口"), systemImage: "door.left.hand.open")) {
            VStack(spacing: 8) {
                ForEach(editingSite.entryPoints.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: editingSite.entryPoints[i].isAccessible ?
                              "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(editingSite.entryPoints[i].isAccessible ? NV.green : NV.danger)
                        TextField(L("出入口名稱"), text: $editingSite.entryPoints[i].name)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        Toggle("", isOn: $editingSite.entryPoints[i].isAccessible)
                            .labelsHidden()
                        Button(role: .destructive) {
                            editingSite.entryPoints.remove(at: i)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button {
                    editingSite.entryPoints.append(
                        EntryPoint(name: "出入口 \(editingSite.entryPoints.count + 1)")
                    )
                } label: {
                    Label(L("新增出入口"), systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - 其他

    private var miscSection: some View {
        GroupBox(label: Label(L("其他"), systemImage: "note.text")) {
            VStack(spacing: 10) {
                HStack {
                    Text(L("集結點"))
                        .font(.subheadline).foregroundColor(.secondary)
                    TextField(L("集結點位置"), text: $editingSite.rallyPoint)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(L("備註"))
                        .font(.subheadline).foregroundColor(.secondary)
                    TextField(L("備註"), text: $editingSite.note)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var disasterPhotoKeywords: [String] {
        [
            editingSite.buildingName,
            editingSite.address,
            editingSite.note,
            editingSite.rallyPoint,
            editingSite.collapseType.label
        ].filter { !$0.isEmpty }
    }
}
