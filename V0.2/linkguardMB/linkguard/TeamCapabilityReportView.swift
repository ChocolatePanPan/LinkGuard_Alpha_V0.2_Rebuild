import SwiftUI

struct TeamCapabilityReportView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var seeded = false
    @State private var teamName = ""
    @State private var unitCode = ""
    @State private var leaderName = ""
    @State private var contactPhone = ""
    @State private var currentLocation = ""
    @State private var stagingArea = ""
    @State private var missionStatus = "可派遣"
    @State private var totalMembers = 6
    @State private var rescueMembers = 4
    @State private var medicalMembers = 1
    @State private var logisticsMembers = 1
    @State private var availableInMinutes = 15
    @State private var operationalHours = 8
    @State private var selfSufficiencyHours = 24
    @State private var ambulances = 0
    @State private var rescueVehicles = 1
    @State private var heavyEquipment = 0
    @State private var boats = 0
    @State private var drones = 0
    @State private var radios = 2
    @State private var selectedCapabilities: Set<String> = ["搜索", "破壞救援", "緊急醫療"]
    @State private var equipmentNotes = ""
    @State private var supportNeeds = ""
    @State private var remarks = ""
    @State private var submissionTitle = ""
    @State private var submissionDetail = ""
    @State private var showSubmissionAlert = false

    private let missionStatuses = ["可派遣", "集結中", "出勤中", "整補中", "不可派遣"]
    private let capabilityOptions = ["搜索", "破壞救援", "緊急醫療", "繩索救援", "水域救援", "化災處置", "無人機偵搜", "通訊中繼", "後勤補給", "重機具操作"]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: vm.commandClient.isConnected ? "wifi" : "wifi.slash")
                        .foregroundStyle(vm.commandClient.isConnected ? NV.green : NV.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.commandClient.isConnected ? L("HQ 已連線") : L("HQ 未連線"))
                            .font(.subheadline.bold())
                        Text(vm.commandClient.isConnected ? L("送出後會立即同步到 HQ") : L("送出後會暫存，連線恢復後自動補送"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !vm.pendingTeamCapabilityReportIDs.isEmpty {
                        Text(L("待送 %lld", vm.pendingTeamCapabilityReportIDs.count))
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NV.warning.opacity(0.18))
                            .foregroundStyle(NV.warning)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if !vm.commandClient.isConnected {
                        Button {
                            vm.commandClient.startBrowsing()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section(L("隊伍識別")) {
                TextField(L("隊伍名稱"), text: $teamName)
                TextField(L("單位代碼"), text: $unitCode)
                TextField(L("隊長 / 聯絡人"), text: $leaderName)
                TextField(L("聯絡電話 / 無線電呼號"), text: $contactPhone)
            }

            Section(L("位置與狀態")) {
                TextField(L("目前位置"), text: $currentLocation)
                TextField(L("集結 / 待命地點"), text: $stagingArea)
                Picker(L("任務狀態"), selection: $missionStatus) {
                    ForEach(missionStatuses, id: \.self) { status in
                        Text(L(status)).tag(status)
                    }
                }
                Stepper(value: $availableInMinutes, in: 0...240, step: 5) {
                    Text(L("可出勤時間：%lld 分鐘", availableInMinutes))
                }
            }

            Section(L("人力")) {
                Stepper(value: $totalMembers, in: 0...99) { Text(L("總員額：%lld", totalMembers)) }
                Stepper(value: $rescueMembers, in: 0...99) { Text(L("救援人員：%lld", rescueMembers)) }
                Stepper(value: $medicalMembers, in: 0...99) { Text(L("醫療人員：%lld", medicalMembers)) }
                Stepper(value: $logisticsMembers, in: 0...99) { Text(L("後勤人員：%lld", logisticsMembers)) }
                Stepper(value: $operationalHours, in: 0...72) { Text(L("連續作業：%lld 小時", operationalHours)) }
                Stepper(value: $selfSufficiencyHours, in: 0...168) { Text(L("自給能力：%lld 小時", selfSufficiencyHours)) }
            }

            Section(L("車輛與裝備數量")) {
                Stepper(value: $rescueVehicles, in: 0...20) { Text(L("救援車：%lld", rescueVehicles)) }
                Stepper(value: $ambulances, in: 0...20) { Text(L("救護車：%lld", ambulances)) }
                Stepper(value: $heavyEquipment, in: 0...20) { Text(L("重機具：%lld", heavyEquipment)) }
                Stepper(value: $boats, in: 0...20) { Text(L("船艇：%lld", boats)) }
                Stepper(value: $drones, in: 0...20) { Text(L("無人機：%lld", drones)) }
                Stepper(value: $radios, in: 0...50) { Text(L("無線電：%lld", radios)) }
            }

            Section(L("能力項目")) {
                ForEach(capabilityOptions, id: \.self) { capability in
                    Toggle(L(capability), isOn: capabilityBinding(capability))
                }
            }

            Section(L("裝備 / 支援需求")) {
                TextField(L("主要裝備摘要"), text: $equipmentNotes, axis: .vertical)
                    .lineLimit(2...5)
                TextField(L("需要 HQ 支援"), text: $supportNeeds, axis: .vertical)
                    .lineLimit(2...5)
                TextField(L("備註"), text: $remarks, axis: .vertical)
                    .lineLimit(2...5)
            }

            if !vm.teamCapabilityReports.isEmpty {
                Section(L("最近送出")) {
                    ForEach(vm.teamCapabilityReports.prefix(5)) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(report.teamName).bold()
                                Spacer()
                                if vm.pendingTeamCapabilityReportIDs.contains(report.id) {
                                    Text(L("待送"))
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(NV.warning.opacity(0.18))
                                        .foregroundStyle(NV.warning)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                Text(report.timeText).foregroundStyle(.secondary)
                            }
                            Text(report.personnelSummary).font(.caption).foregroundStyle(.secondary)
                            Text(report.capabilitySummary).font(.caption).lineLimit(2)
                        }
                    }
                }
            }
        }
        .onAppear(perform: seedDefaultsIfNeeded)
        .safeAreaInset(edge: .bottom) {
            Button(action: submitReport) {
                Label(L("送出能力概況"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .padding()
            .background(.bar)
        }
        .alert(submissionTitle, isPresented: $showSubmissionAlert) {
            Button(L("完成"), role: .cancel) { }
        } message: {
            if !submissionDetail.isEmpty {
                Text(submissionDetail)
            }
        }
    }

    private var canSubmit: Bool {
        !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currentLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func capabilityBinding(_ capability: String) -> Binding<Bool> {
        Binding(
            get: { selectedCapabilities.contains(capability) },
            set: { isSelected in
                if isSelected {
                    selectedCapabilities.insert(capability)
                } else {
                    selectedCapabilities.remove(capability)
                }
            }
        )
    }

    private func seedDefaultsIfNeeded() {
        guard !seeded else { return }
        seeded = true
        unitCode = vm.nodeStatus.deptCode
        teamName = "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
        currentLocation = vm.disasterSite?.buildingName ?? ""
        stagingArea = vm.disasterSite?.rallyPoint ?? ""
        leaderName = vm.userNickname
    }

    private func submitReport() {
        let trimmedTeamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = currentLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = TeamCapabilityReport(
            teamName: trimmedTeamName,
            unitCode: unitCode.trimmingCharacters(in: .whitespacesAndNewlines),
            leaderName: leaderName.trimmingCharacters(in: .whitespacesAndNewlines),
            contactPhone: contactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            currentLocation: trimmedLocation,
            stagingArea: stagingArea.trimmingCharacters(in: .whitespacesAndNewlines),
            missionStatus: missionStatus,
            totalMembers: totalMembers,
            rescueMembers: rescueMembers,
            medicalMembers: medicalMembers,
            logisticsMembers: logisticsMembers,
            availableInMinutes: availableInMinutes,
            operationalHours: operationalHours,
            selfSufficiencyHours: selfSufficiencyHours,
            ambulances: ambulances,
            rescueVehicles: rescueVehicles,
            heavyEquipment: heavyEquipment,
            boats: boats,
            drones: drones,
            radios: radios,
            capabilities: selectedCapabilities.sorted(),
            equipmentNotes: equipmentNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            supportNeeds: supportNeeds.trimmingCharacters(in: .whitespacesAndNewlines),
            remarks: remarks.trimmingCharacters(in: .whitespacesAndNewlines),
            reporterID: vm.nodeStatus.nodeID,
            reporterName: "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
        )
        let queuedForSend = vm.sendTeamCapabilityReport(report)
        submissionTitle = queuedForSend ? L("已送出隊伍能力概況") : L("已暫存隊伍能力概況")
        submissionDetail = queuedForSend ? L("封包已送往 HQ。") : L("目前未連線 HQ，系統會在連線恢復後自動補送。")
        showSubmissionAlert = true
    }
}