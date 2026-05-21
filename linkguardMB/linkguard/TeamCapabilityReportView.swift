import SwiftUI

struct TeamCapabilityReportView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var seeded = false

    @State private var usarTeamCode = ""
    @State private var country = ""
    @State private var teamName = ""
    @State private var totalMembers = 6
    @State private var searchDogCount = 0
    @State private var responseType = "中型"
    @State private var classificationStatus = "已通過分級測評"
    @State private var hasTechnicalSearch = true
    @State private var hasDogSearch = false
    @State private var hasRescueCapability = true
    @State private var hasMedicalCapability = true
    @State private var hasHazmatDetection = false
    @State private var structuralEngineerCount = 0
    @State private var canEstablishOSOCCRDC = false
    @State private var canSupportUSARCoordination = false
    @State private var otherCapabilities = ""
    @State private var arrivalDate = ""
    @State private var arrivalTime = ""
    @State private var arrivalPoint = ""
    @State private var aircraftType = ""

    @State private var waterDays = 3
    @State private var foodDays = 3
    @State private var needsGroundTransport = false
    @State private var needsLogisticsSupport = false
    @State private var transportPersonnelCount = 0
    @State private var transportDogCount = 0
    @State private var equipmentWeightTons = 0.0
    @State private var equipmentVolumeCubicMeters = 0.0
    @State private var dailyGasolineLiters = 0.0
    @State private var dailyDieselLiters = 0.0
    @State private var needsCuttingOxygen = false
    @State private var needsCuttingPropane = false
    @State private var needsMedicalOxygen = false
    @State private var baseAreaSquareMeters = 0.0
    @State private var otherLogisticsNeeds = ""

    @State private var teamContactNameOrRole = ""
    @State private var teamContactMobile = ""
    @State private var teamContactSatellite = ""
    @State private var teamContactEmail = ""
    @State private var operationsContactNameOrTitle = ""
    @State private var operationsContactMobile = ""
    @State private var operationsContactEmail = ""
    @State private var policyContactNameOrTitle = ""
    @State private var policyContactMobile = ""
    @State private var policyContactEmail = ""
    @State private var baseLocationAddress = ""
    @State private var baseRadioFrequencyMHz = ""
    @State private var baseGPSCoordinates = ""

    @State private var evacuationDate = ""
    @State private var evacuationTime = ""
    @State private var evacuationPoint = ""
    @State private var departureTransportInfo = ""
    @State private var evacuationNeedsGroundTransport = false
    @State private var evacuationNeedsLogisticsSupport = false
    @State private var evacuationTransportPersonnelCount = 0
    @State private var evacuationTransportDogCount = 0
    @State private var evacuationEquipmentWeightTons = 0.0
    @State private var evacuationEquipmentVolumeCubicMeters = 0.0
    @State private var loadingAssistanceNeeds = ""
    @State private var evacuationTemporaryAccommodationNeeds = ""
    @State private var evacuationOtherInfo = ""

    @State private var submissionTitle = ""
    @State private var submissionDetail = ""
    @State private var showSubmissionAlert = false

    private let responseTypes = ["輕型", "中型", "重型", "其他"]
    private let classificationStatuses = ["已通過分級測評", "未通過分級測評", "未分級", "重新分級中"]

    var body: some View {
        Form {
            connectionSection
            photoAttachmentSection
            teamInformationSection
            supportNeedsSection
            contactSection
            evacuationSection
            recentReportsSection
        }
        .onAppear(perform: seedDefaultsIfNeeded)
        .safeAreaInset(edge: .bottom) {
            Button(action: submitReport) {
                Label(L("送出 USAR 隊伍概況"), systemImage: "paperplane.fill")
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
            if !submissionDetail.isEmpty { Text(submissionDetail) }
        }
    }

    private var connectionSection: some View {
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
                    Button { vm.commandClient.startBrowsing() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var teamInformationSection: some View {
        Section(L("A. 隊伍資訊")) {
            fixedUppercaseTextField(L("A0 隊伍代碼（國家代碼 + 隊伍編碼）"), text: $usarTeamCode)
            fixedTextField(L("A1 隊伍所屬國"), text: $country)
            fixedTextField(L("A2 隊伍名稱"), text: $teamName)
            Stepper(value: $totalMembers, in: 0...999) { Text(L("A3 出隊總人數：%lld", totalMembers)) }
            Stepper(value: $searchDogCount, in: 0...99) { Text(L("A4 出隊搜救犬：%lld", searchDogCount)) }
            Picker(L("A5 響應類型"), selection: $responseType) {
                ForEach(responseTypes, id: \.self) { Text(L($0)).tag($0) }
            }
            Picker(L("A6 分級測評狀態"), selection: $classificationStatus) {
                ForEach(classificationStatuses, id: \.self) { Text(L($0)).tag($0) }
            }
            Toggle(L("A7 技術搜索能力"), isOn: $hasTechnicalSearch)
            Toggle(L("A8 犬搜索能力"), isOn: $hasDogSearch)
            Toggle(L("A9 營救能力"), isOn: $hasRescueCapability)
            Toggle(L("A10 醫療能力"), isOn: $hasMedicalCapability)
            Toggle(L("A11 危險品偵檢能力"), isOn: $hasHazmatDetection)
            Stepper(value: $structuralEngineerCount, in: 0...99) { Text(L("A12 結構工程師：%lld", structuralEngineerCount)) }
            Toggle(L("A13 可建立臨時 OSOCC / RDC"), isOn: $canEstablishOSOCCRDC)
            Toggle(L("A14 可支援 USAR 協調"), isOn: $canSupportUSARCoordination)
            fixedMultilineTextField(L("A15 其他能力"), text: $otherCapabilities, lines: 2...5)
            fixedTextField(L("A16 預計抵達日期（日/月/年）"), text: $arrivalDate)
            fixedTextField(L("A17 預計抵達時間（24 小時制）"), text: $arrivalTime)
            fixedTextField(L("A18 抵達地點（機場、城市、港口等）"), text: $arrivalPoint)
            fixedTextField(L("A19 飛機類型（型號、大小）"), text: $aircraftType)
        }
    }

    private var photoAttachmentSection: some View {
        Section(L("照片附件")) {
            ReportPhotoAttachmentView(
                vm: vm,
                reportType: L("隊伍能力概況"),
                context: "\(trim(teamName)) \(trim(usarTeamCode))"
            )
        }
    }

    private var supportNeedsSection: some View {
        Section(L("B. 支援需求")) {
            Stepper(value: $waterDays, in: 0...30) { Text(L("B1 自備水可持續：%lld 天", waterDays)) }
            Stepper(value: $foodDays, in: 0...30) { Text(L("B2 自備食物可持續：%lld 天", foodDays)) }
            Toggle(L("B3 需要地面運輸支持"), isOn: $needsGroundTransport)
            Toggle(L("B4 需要物資支持"), isOn: $needsLogisticsSupport)
            Stepper(value: $transportPersonnelCount, in: 0...999) { Text(L("B5 運輸人員：%lld", transportPersonnelCount)) }
            Stepper(value: $transportDogCount, in: 0...99) { Text(L("B6 運輸搜救犬：%lld", transportDogCount)) }
            decimalField(L("B7 裝備總重量（噸）"), value: $equipmentWeightTons)
            decimalField(L("B8 裝備總體積（立方米）"), value: $equipmentVolumeCubicMeters)
            decimalField(L("B9 每日汽油需求（升）"), value: $dailyGasolineLiters)
            decimalField(L("B10 每日柴油需求（升）"), value: $dailyDieselLiters)
            Toggle(L("B11 需要切割用氧氣"), isOn: $needsCuttingOxygen)
            Toggle(L("B12 需要切割用丙烷"), isOn: $needsCuttingPropane)
            Toggle(L("B13 需要醫用氧氣補給"), isOn: $needsMedicalOxygen)
            decimalField(L("B14 行動基地用地面積（平方米）"), value: $baseAreaSquareMeters)
            fixedMultilineTextField(L("B15 其他後勤需求"), text: $otherLogisticsNeeds, lines: 2...5)
        }
    }

    private var contactSection: some View {
        Section(L("C. 聯絡方式")) {
            fixedTextField(L("C1 隊伍聯絡人姓名或職務"), text: $teamContactNameOrRole)
            fixedTextField(L("C2 隊伍聯絡人手機"), text: $teamContactMobile)
            fixedTextField(L("C3 隊伍聯絡人衛星電話"), text: $teamContactSatellite)
            fixedNoCapsTextField(L("C4 隊伍聯絡人電子郵件"), text: $teamContactEmail)
            fixedTextField(L("C5 行動聯絡人姓名或職稱"), text: $operationsContactNameOrTitle)
            fixedTextField(L("C6 行動聯絡人手機"), text: $operationsContactMobile)
            fixedNoCapsTextField(L("C7 行動聯絡人電子郵件"), text: $operationsContactEmail)
            fixedTextField(L("C8 政策聯絡人姓名或職稱"), text: $policyContactNameOrTitle)
            fixedTextField(L("C9 政策聯絡人手機"), text: $policyContactMobile)
            fixedNoCapsTextField(L("C10 政策聯絡人電子郵件"), text: $policyContactEmail)
            fixedTextField(L("C11 行動基地位置或地址"), text: $baseLocationAddress)
            fixedTextField(L("C12 行動基地無線電頻率（MHz）"), text: $baseRadioFrequencyMHz)
            fixedTextField(L("C13 行動基地 GPS 坐標（WGS84）"), text: $baseGPSCoordinates)
        }
    }

    private var evacuationSection: some View {
        Section(L("D. 撤離資訊")) {
            fixedTextField(L("D1 預計撤離日期（日/月/年）"), text: $evacuationDate)
            fixedTextField(L("D2 預計撤離時間（24 小時制）"), text: $evacuationTime)
            fixedTextField(L("D3 撤離地點（機場、城市、港口等）"), text: $evacuationPoint)
            fixedMultilineTextField(L("D4 離開運輸情況 / 航班資訊"), text: $departureTransportInfo, lines: 2...4)
            Toggle(L("D5 需要地面運輸支持"), isOn: $evacuationNeedsGroundTransport)
            Toggle(L("D6 需要物資支持"), isOn: $evacuationNeedsLogisticsSupport)
            Stepper(value: $evacuationTransportPersonnelCount, in: 0...999) { Text(L("D7 運輸人員：%lld", evacuationTransportPersonnelCount)) }
            Stepper(value: $evacuationTransportDogCount, in: 0...99) { Text(L("D8 運輸搜救犬：%lld", evacuationTransportDogCount)) }
            decimalField(L("D9 裝備總重量（噸）"), value: $evacuationEquipmentWeightTons)
            decimalField(L("D10 裝備總體積（立方米）"), value: $evacuationEquipmentVolumeCubicMeters)
            fixedMultilineTextField(L("D11 裝卸協助需求"), text: $loadingAssistanceNeeds, lines: 2...4)
            fixedMultilineTextField(L("D12 撤離地點臨時住宿需求"), text: $evacuationTemporaryAccommodationNeeds, lines: 2...4)
            fixedMultilineTextField(L("D13 其他資訊或後勤需求"), text: $evacuationOtherInfo, lines: 2...5)
        }
    }

    @ViewBuilder
    private var recentReportsSection: some View {
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
                        Text([report.usarTeamCode, report.country, report.responseSummary].compactMap { value in
                            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            return trimmed.isEmpty ? nil : trimmed
                        }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(report.personnelSummary).font(.caption).foregroundStyle(.secondary)
                        Text(report.capabilitySummary).font(.caption).lineLimit(2)
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !trim(usarTeamCode).isEmpty && !trim(teamName).isEmpty
    }

    private func fixedTextField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 96, maxWidth: 180)
        }
    }

    private func fixedUppercaseTextField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 96, maxWidth: 180)
        }
    }

    private func fixedNoCapsTextField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 96, maxWidth: 220)
        }
    }

    private func fixedMultilineTextField(_ title: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: text, axis: .vertical)
                .lineLimit(lines)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func decimalField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 88, maxWidth: 140)
        }
    }

    private func seedDefaultsIfNeeded() {
        guard !seeded else { return }
        seeded = true
        usarTeamCode = vm.nodeStatus.deptCode
        country = "TWN"
        teamName = "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
        arrivalPoint = vm.disasterSite?.buildingName ?? ""
        baseLocationAddress = vm.disasterSite?.rallyPoint ?? ""
        teamContactNameOrRole = vm.userNickname
        operationsContactNameOrTitle = vm.userNickname
    }

    private func submitReport() {
        let capabilityList = selectedCapabilityList()
        let equipmentSummary = String(format: "裝備 %.1f 噸 / %.1f 立方米", equipmentWeightTons, equipmentVolumeCubicMeters)
        let report = TeamCapabilityReport(
            usarTeamCode: trim(usarTeamCode),
            country: trim(country),
            teamName: trim(teamName),
            unitCode: trim(usarTeamCode),
            leaderName: trim(teamContactNameOrRole),
            contactPhone: trim(teamContactMobile),
            currentLocation: trim(arrivalPoint),
            stagingArea: trim(baseLocationAddress),
            missionStatus: responseType,
            totalMembers: totalMembers,
            rescueMembers: hasRescueCapability ? totalMembers : 0,
            medicalMembers: hasMedicalCapability ? totalMembers : 0,
            logisticsMembers: 0,
            availableInMinutes: 0,
            operationalHours: 0,
            selfSufficiencyHours: min(waterDays, foodDays) * 24,
            ambulances: 0,
            rescueVehicles: 0,
            heavyEquipment: 0,
            boats: 0,
            drones: 0,
            radios: 0,
            capabilities: capabilityList,
            equipmentNotes: equipmentSummary,
            supportNeeds: trim(otherLogisticsNeeds),
            remarks: trim(evacuationOtherInfo),
            searchDogCount: searchDogCount,
            responseType: responseType,
            classificationStatus: classificationStatus,
            hasTechnicalSearch: hasTechnicalSearch,
            hasDogSearch: hasDogSearch,
            hasRescueCapability: hasRescueCapability,
            hasMedicalCapability: hasMedicalCapability,
            hasHazmatDetection: hasHazmatDetection,
            structuralEngineerCount: structuralEngineerCount,
            canEstablishOSOCCRDC: canEstablishOSOCCRDC,
            canSupportUSARCoordination: canSupportUSARCoordination,
            otherCapabilities: trim(otherCapabilities),
            arrivalDate: trim(arrivalDate),
            arrivalTime: trim(arrivalTime),
            arrivalPoint: trim(arrivalPoint),
            aircraftType: trim(aircraftType),
            waterDays: waterDays,
            foodDays: foodDays,
            needsGroundTransport: needsGroundTransport,
            needsLogisticsSupport: needsLogisticsSupport,
            transportPersonnelCount: transportPersonnelCount,
            transportDogCount: transportDogCount,
            equipmentWeightTons: equipmentWeightTons,
            equipmentVolumeCubicMeters: equipmentVolumeCubicMeters,
            dailyGasolineLiters: dailyGasolineLiters,
            dailyDieselLiters: dailyDieselLiters,
            needsCuttingOxygen: needsCuttingOxygen,
            needsCuttingPropane: needsCuttingPropane,
            needsMedicalOxygen: needsMedicalOxygen,
            baseAreaSquareMeters: baseAreaSquareMeters,
            otherLogisticsNeeds: trim(otherLogisticsNeeds),
            teamContactNameOrRole: trim(teamContactNameOrRole),
            teamContactMobile: trim(teamContactMobile),
            teamContactSatellite: trim(teamContactSatellite),
            teamContactEmail: trim(teamContactEmail),
            operationsContactNameOrTitle: trim(operationsContactNameOrTitle),
            operationsContactMobile: trim(operationsContactMobile),
            operationsContactEmail: trim(operationsContactEmail),
            policyContactNameOrTitle: trim(policyContactNameOrTitle),
            policyContactMobile: trim(policyContactMobile),
            policyContactEmail: trim(policyContactEmail),
            baseLocationAddress: trim(baseLocationAddress),
            baseRadioFrequencyMHz: trim(baseRadioFrequencyMHz),
            baseGPSCoordinates: trim(baseGPSCoordinates),
            evacuationDate: trim(evacuationDate),
            evacuationTime: trim(evacuationTime),
            evacuationPoint: trim(evacuationPoint),
            departureTransportInfo: trim(departureTransportInfo),
            evacuationNeedsGroundTransport: evacuationNeedsGroundTransport,
            evacuationNeedsLogisticsSupport: evacuationNeedsLogisticsSupport,
            evacuationTransportPersonnelCount: evacuationTransportPersonnelCount,
            evacuationTransportDogCount: evacuationTransportDogCount,
            evacuationEquipmentWeightTons: evacuationEquipmentWeightTons,
            evacuationEquipmentVolumeCubicMeters: evacuationEquipmentVolumeCubicMeters,
            loadingAssistanceNeeds: trim(loadingAssistanceNeeds),
            evacuationTemporaryAccommodationNeeds: trim(evacuationTemporaryAccommodationNeeds),
            evacuationOtherInfo: trim(evacuationOtherInfo),
            reporterID: vm.nodeStatus.nodeID,
            reporterName: "\(vm.nodeStatus.deptCode)-\(vm.nodeStatus.nodeID)"
        )
        let queuedForSend = vm.sendTeamCapabilityReport(report)
        submissionTitle = queuedForSend ? L("已送出 USAR 隊伍概況") : L("已暫存 USAR 隊伍概況")
        submissionDetail = queuedForSend ? L("封包已送往 HQ。") : L("目前未連線 HQ，系統會在連線恢復後自動補送。")
        showSubmissionAlert = true
    }

    private func selectedCapabilityList() -> [String] {
        var items: [String] = []
        if hasTechnicalSearch { items.append("技術搜索") }
        if hasDogSearch { items.append("犬搜索") }
        if hasRescueCapability { items.append("營救") }
        if hasMedicalCapability { items.append("醫療") }
        if hasHazmatDetection { items.append("危險品偵檢") }
        if structuralEngineerCount > 0 { items.append("結構工程師 \(structuralEngineerCount)") }
        if canEstablishOSOCCRDC { items.append("OSOCC/RDC") }
        if canSupportUSARCoordination { items.append("USAR 協調支援") }
        if !trim(otherCapabilities).isEmpty { items.append(trim(otherCapabilities)) }
        return items
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}