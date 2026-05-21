import LinkGuardV03Core
import SwiftUI

struct TeamCapabilityReportFormView: View {
    @State private var report: USARTeamCapabilityReport
    let onCancel: () -> Void
    let onSubmit: (USARTeamCapabilityReport) -> Void

    init(
        initialReport: USARTeamCapabilityReport,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (USARTeamCapabilityReport) -> Void
    ) {
        _report = State(initialValue: initialReport)
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                teamInformationSection
                supportNeedsSection
                contactsSection
                evacuationSection
            }
            .scrollContentBackground(.hidden)
            .background(FieldTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("城市搜索與救援隊隊伍概況表")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        var outgoing = report
                        outgoing.createdAt = Date()
                        onSubmit(outgoing)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(FieldTheme.green)
        .preferredColorScheme(.dark)
    }

    private var teamInformationSection: some View {
        Section("A. 隊伍資訊") {
            textField("A0 隊伍代碼", text: $report.team.teamCode)
            textField("A1 所屬國", text: $report.team.country)
            textField("A2 隊伍名稱", text: $report.team.teamName)
            intField("A3 出隊總人數", value: $report.team.totalMembers)
            intField("A4 搜救犬總數", value: $report.team.searchDogCount)
            Picker("A5 響應類型", selection: $report.team.responseType) {
                ForEach(USARTeamResponseType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            Picker("A6 分級測評", selection: $report.team.classificationStatus) {
                ForEach(USARTeamClassificationStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)
            Toggle("A7 技術搜索", isOn: $report.team.hasTechnicalSearch)
            Toggle("A8 犬搜索", isOn: $report.team.hasDogSearch)
            Toggle("A9 營救", isOn: $report.team.hasRescueCapability)
            Toggle("A10 醫療", isOn: $report.team.hasMedicalCapability)
            Toggle("A11 危險品偵檢", isOn: $report.team.hasHazmatDetection)
            intField("A12 結構工程師", value: $report.team.structuralEngineerCount)
            Toggle("A13 可建立 OSOCC/RDC", isOn: $report.team.canEstablishOSOCCRDC)
            Toggle("A14 可支援 USAR 協調", isOn: $report.team.canSupportUSARCoordination)
            textField("A15 其他能力", text: $report.team.otherCapabilities, axis: .vertical)
            textField("A16 抵達日期", text: $report.team.arrivalDate)
            textField("A17 抵達時間", text: $report.team.arrivalTime)
            textField("A18 抵達地點", text: $report.team.arrivalPoint)
            textField("A19 飛機類型", text: $report.team.aircraftType)
        }
    }

    private var supportNeedsSection: some View {
        Section("B. 支援需求") {
            intField("B1 水可持續天數", value: $report.supportNeeds.waterDays)
            intField("B2 食物可持續天數", value: $report.supportNeeds.foodDays)
            Toggle("B3 需要地面運輸", isOn: $report.supportNeeds.needsGroundTransport)
            Toggle("B4 需要物資支持", isOn: $report.supportNeeds.needsLogisticsSupport)
            intField("B5 運輸人員數", value: $report.supportNeeds.transportPersonnelCount)
            intField("B6 運輸搜救犬數", value: $report.supportNeeds.transportDogCount)
            doubleField("B7 裝備重量 t", value: $report.supportNeeds.equipmentWeightTons)
            doubleField("B8 裝備體積 m³", value: $report.supportNeeds.equipmentVolumeCubicMeters)
            doubleField("B9 每日汽油 L", value: $report.supportNeeds.dailyGasolineLiters)
            doubleField("B10 每日柴油 L", value: $report.supportNeeds.dailyDieselLiters)
            Toggle("B11 需要切割氧氣", isOn: $report.supportNeeds.needsCuttingOxygen)
            Toggle("B12 需要切割丙烷", isOn: $report.supportNeeds.needsCuttingPropane)
            Toggle("B13 需要醫用氧氣", isOn: $report.supportNeeds.needsMedicalOxygen)
            doubleField("B14 行動基地面積 m²", value: $report.supportNeeds.baseAreaSquareMeters)
            textField("B15 其他後勤需求", text: $report.supportNeeds.otherLogisticsNeeds, axis: .vertical)
        }
    }

    private var contactsSection: some View {
        Section("C. 聯絡方式") {
            textField("C1 隊伍聯絡人", text: $report.contacts.teamContactNameOrRole)
            textField("C2 隊伍手機", text: $report.contacts.teamContactMobile)
            textField("C3 衛星電話", text: $report.contacts.teamContactSatellite)
            textField("C4 隊伍電子郵件", text: $report.contacts.teamContactEmail)
            textField("C5 行動聯絡人", text: $report.contacts.operationsContactNameOrTitle)
            textField("C6 行動手機", text: $report.contacts.operationsContactMobile)
            textField("C7 行動電子郵件", text: $report.contacts.operationsContactEmail)
            textField("C8 政策聯絡人", text: $report.contacts.policyContactNameOrTitle)
            textField("C9 政策手機", text: $report.contacts.policyContactMobile)
            textField("C10 政策電子郵件", text: $report.contacts.policyContactEmail)
            textField("C11 行動基地地址", text: $report.contacts.baseLocationAddress, axis: .vertical)
            textField("C12 無線電頻率 MHz", text: $report.contacts.baseRadioFrequencyMHz)
            textField("C13 GPS 坐標", text: $report.contacts.baseGPSCoordinates)
        }
    }

    private var evacuationSection: some View {
        Section("D. 撤離資訊") {
            textField("D1 撤離日期", text: $report.evacuation.evacuationDate)
            textField("D2 撤離時間", text: $report.evacuation.evacuationTime)
            textField("D3 撤離地點", text: $report.evacuation.evacuationPoint)
            textField("D4 離開運輸情況 / 航班資訊", text: $report.evacuation.departureTransportInfo, axis: .vertical)
            Toggle("D5 需要地面運輸", isOn: $report.evacuation.needsGroundTransport)
            Toggle("D6 需要物資支持", isOn: $report.evacuation.needsLogisticsSupport)
            intField("D7 運輸人員數", value: $report.evacuation.transportPersonnelCount)
            intField("D8 運輸搜救犬數", value: $report.evacuation.transportDogCount)
            doubleField("D9 裝備重量 t", value: $report.evacuation.equipmentWeightTons)
            doubleField("D10 裝備體積 m³", value: $report.evacuation.equipmentVolumeCubicMeters)
            textField("D11 裝卸協助需求", text: $report.evacuation.loadingAssistanceNeeds, axis: .vertical)
            textField("D12 臨時住宿需求", text: $report.evacuation.temporaryAccommodationNeeds, axis: .vertical)
            textField("D13 其他資訊或後勤需求", text: $report.evacuation.otherInfoOrLogisticsNeeds, axis: .vertical)
        }
    }

    private func textField(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("請輸入", text: text, axis: axis)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
        }
    }

    private func intField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("請輸入", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .keyboardType(.numberPad)
        }
    }

    private func doubleField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("請輸入", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .keyboardType(.decimalPad)
        }
    }
}