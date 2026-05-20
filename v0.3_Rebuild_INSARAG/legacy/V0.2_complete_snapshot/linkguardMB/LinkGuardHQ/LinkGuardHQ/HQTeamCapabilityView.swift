import SwiftUI

struct HQTeamCapabilityView: View {
    @ObservedObject var vm: HQViewModel

    private var reports: [TeamCapabilityReport] {
        vm.teamCapabilityReports.sorted { $0.timestamp > $1.timestamp }
    }

    private var totalMembers: Int {
        reports.reduce(0) { $0 + $1.totalMembers }
    }

    private var totalDogs: Int {
        reports.reduce(0) { $0 + ($1.searchDogCount ?? 0) }
    }

    private var groundTransportRequests: Int {
        reports.filter { $0.needsGroundTransport == true || $0.evacuationNeedsGroundTransport == true }.count
    }

    private var totalEquipmentWeight: Double {
        reports.reduce(0) { $0 + ($1.equipmentWeightTons ?? 0) + ($1.evacuationEquipmentWeightTons ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryGrid

                if reports.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(reports) { report in
                            capabilityCard(report)
                        }
                    }
                }
            }
            .padding()
        }
        .background(NV.bg.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("城市搜索與救援隊隊伍概況表"), systemImage: "person.3.fill")
                .font(.title2.bold())
                .foregroundStyle(NV.green)
            Text(L("前線回傳的 USAR 隊伍資訊、支援需求、聯絡方式與撤離資料集中顯示於此。"))
                .foregroundStyle(.secondary)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            metricCard(title: L("回報隊伍"), value: "\(reports.count)", icon: "doc.text.fill", color: NV.info)
            metricCard(title: L("出隊人數"), value: "\(totalMembers)", icon: "person.3.sequence.fill", color: NV.team)
            metricCard(title: L("搜救犬"), value: "\(totalDogs)", icon: "pawprint.fill", color: NV.green)
            metricCard(title: L("需地面運輸"), value: "\(groundTransportRequests)", icon: "truck.box.fill", color: NV.command)
            metricCard(title: L("裝備重量"), value: "\(formatNumber(totalEquipmentWeight)) t", icon: "shippingbox.fill", color: NV.warning)
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold())
            }
            Spacer()
        }
        .padding(12)
        .background(NV.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25)))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L("尚未收到隊伍概況表"))
                .font(.headline)
            Text(L("前線在 iPhone 送出 USAR 隊伍概況表後，會自動出現在這裡。"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(NV.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func capabilityCard(_ report: TeamCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.teamName)
                        .font(.headline)
                    Text(compact([report.usarTeamCode, report.country, report.arrivalPoint]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !report.responseSummary.isEmpty {
                        statusBadge(report.responseSummary)
                    }
                    Text(report.timeText).font(.caption).foregroundStyle(.secondary)
                }
            }

            infoGrid([
                (L("出隊 / 搜救犬"), "\(report.totalMembers) / \(report.searchDogCount ?? 0)"),
                (L("抵達"), compact([report.arrivalDate, report.arrivalTime])),
                (L("支援需求"), supportRequestText(report)),
                (L("裝備"), "\(formatNumber(report.equipmentWeightTons)) t / \(formatNumber(report.equipmentVolumeCubicMeters)) m³")
            ])

            detailGroup(L("A. 隊伍資訊")) {
                infoGrid([
                    (L("A0 隊伍代碼"), value(report.usarTeamCode)),
                    (L("A1 所屬國"), value(report.country)),
                    (L("A2 隊伍名稱"), value(report.teamName)),
                    (L("A3 出隊總人數"), "\(report.totalMembers)"),
                    (L("A4 搜救犬總數"), "\(report.searchDogCount ?? 0)"),
                    (L("A5 響應類型"), value(report.responseType)),
                    (L("A6 分級測評"), value(report.classificationStatus)),
                    (L("A7 技術搜索"), yesNo(report.hasTechnicalSearch)),
                    (L("A8 犬搜索"), yesNo(report.hasDogSearch)),
                    (L("A9 營救"), yesNo(report.hasRescueCapability)),
                    (L("A10 醫療"), yesNo(report.hasMedicalCapability)),
                    (L("A11 危險品偵檢"), yesNo(report.hasHazmatDetection)),
                    (L("A12 結構工程師"), "\(report.structuralEngineerCount ?? 0)"),
                    (L("A13 OSOCC/RDC"), yesNo(report.canEstablishOSOCCRDC)),
                    (L("A14 USAR 協調"), yesNo(report.canSupportUSARCoordination)),
                    (L("A16 抵達日期"), value(report.arrivalDate)),
                    (L("A17 抵達時間"), value(report.arrivalTime)),
                    (L("A18 抵達地點"), value(report.arrivalPoint)),
                    (L("A19 飛機類型"), value(report.aircraftType))
                ])
                detailBlock(title: L("A15 其他能力"), content: report.otherCapabilities)
            }

            detailGroup(L("B. 支援需求")) {
                infoGrid([
                    (L("B1 水可持續"), "\(report.waterDays ?? 0) 天"),
                    (L("B2 食物可持續"), "\(report.foodDays ?? 0) 天"),
                    (L("B3 地面運輸"), yesNo(report.needsGroundTransport)),
                    (L("B4 物資支持"), yesNo(report.needsLogisticsSupport)),
                    (L("B5 運輸人員"), "\(report.transportPersonnelCount ?? 0)"),
                    (L("B6 運輸搜救犬"), "\(report.transportDogCount ?? 0)"),
                    (L("B7 裝備重量"), "\(formatNumber(report.equipmentWeightTons)) t"),
                    (L("B8 裝備體積"), "\(formatNumber(report.equipmentVolumeCubicMeters)) m³"),
                    (L("B9 汽油 / 日"), "\(formatNumber(report.dailyGasolineLiters)) L"),
                    (L("B10 柴油 / 日"), "\(formatNumber(report.dailyDieselLiters)) L"),
                    (L("B11 切割氧氣"), yesNo(report.needsCuttingOxygen)),
                    (L("B12 切割丙烷"), yesNo(report.needsCuttingPropane)),
                    (L("B13 醫用氧氣"), yesNo(report.needsMedicalOxygen)),
                    (L("B14 基地面積"), "\(formatNumber(report.baseAreaSquareMeters)) m²")
                ])
                detailBlock(title: L("B15 其他後勤需求"), content: report.otherLogisticsNeeds)
            }

            detailGroup(L("C. 聯絡方式")) {
                infoGrid([
                    (L("C1 隊伍聯絡人"), value(report.teamContactNameOrRole)),
                    (L("C2 隊伍手機"), value(report.teamContactMobile)),
                    (L("C3 衛星電話"), value(report.teamContactSatellite)),
                    (L("C4 隊伍電子郵件"), value(report.teamContactEmail)),
                    (L("C5 行動聯絡人"), value(report.operationsContactNameOrTitle)),
                    (L("C6 行動手機"), value(report.operationsContactMobile)),
                    (L("C7 行動電子郵件"), value(report.operationsContactEmail)),
                    (L("C8 政策聯絡人"), value(report.policyContactNameOrTitle)),
                    (L("C9 政策手機"), value(report.policyContactMobile)),
                    (L("C10 政策電子郵件"), value(report.policyContactEmail)),
                    (L("C11 行動基地"), value(report.baseLocationAddress)),
                    (L("C12 無線電頻率"), value(report.baseRadioFrequencyMHz)),
                    (L("C13 GPS 坐標"), value(report.baseGPSCoordinates))
                ])
            }

            detailGroup(L("D. 撤離資訊")) {
                infoGrid([
                    (L("D1 撤離日期"), value(report.evacuationDate)),
                    (L("D2 撤離時間"), value(report.evacuationTime)),
                    (L("D3 撤離地點"), value(report.evacuationPoint)),
                    (L("D5 地面運輸"), yesNo(report.evacuationNeedsGroundTransport)),
                    (L("D6 物資支持"), yesNo(report.evacuationNeedsLogisticsSupport)),
                    (L("D7 運輸人員"), "\(report.evacuationTransportPersonnelCount ?? 0)"),
                    (L("D8 運輸搜救犬"), "\(report.evacuationTransportDogCount ?? 0)"),
                    (L("D9 裝備重量"), "\(formatNumber(report.evacuationEquipmentWeightTons)) t"),
                    (L("D10 裝備體積"), "\(formatNumber(report.evacuationEquipmentVolumeCubicMeters)) m³")
                ])
                detailBlock(title: L("D4 離開運輸情況 / 航班資訊"), content: report.departureTransportInfo)
                detailBlock(title: L("D11 裝卸協助需求"), content: report.loadingAssistanceNeeds)
                detailBlock(title: L("D12 臨時住宿需求"), content: report.evacuationTemporaryAccommodationNeeds)
                detailBlock(title: L("D13 其他資訊或後勤需求"), content: report.evacuationOtherInfo)
            }

            HStack {
                if let contact = nonEmpty(report.teamContactNameOrRole ?? report.leaderName) {
                    Label(contact, systemImage: "person.crop.circle")
                }
                if let phone = nonEmpty(report.teamContactMobile ?? report.contactPhone) {
                    Label(phone, systemImage: "phone.fill")
                }
                Spacer()
                Text(report.reporterName.isEmpty ? report.reporterID : report.reporterName)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(14)
        .background(NV.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NV.green.opacity(0.2)))
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(NV.green.opacity(0.18))
            .foregroundStyle(NV.green)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func infoGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    Text(item.1).font(.subheadline).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func detailGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title).font(.subheadline.bold()).foregroundStyle(NV.green)
            content()
        }
    }

    @ViewBuilder
    private func detailBlock(title: String, content: String?) -> some View {
        if let text = nonEmpty(content) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(text).font(.subheadline).textSelection(.enabled)
            }
        }
    }

    private func supportRequestText(_ report: TeamCapabilityReport) -> String {
        var items: [String] = []
        if report.needsGroundTransport == true { items.append(L("地面運輸")) }
        if report.needsLogisticsSupport == true { items.append(L("物資")) }
        if report.needsCuttingOxygen == true { items.append(L("切割氧氣")) }
        if report.needsCuttingPropane == true { items.append(L("切割丙烷")) }
        if report.needsMedicalOxygen == true { items.append(L("醫用氧氣")) }
        return items.isEmpty ? L("未標示") : items.joined(separator: "、")
    }

    private func compact(_ values: [String?]) -> String {
        let items = values.compactMap { nonEmpty($0) }
        return items.isEmpty ? L("未填") : items.joined(separator: " · ")
    }

    private func value(_ text: String?) -> String {
        nonEmpty(text) ?? L("未填")
    }

    private func yesNo(_ value: Bool?) -> String {
        guard let value else { return L("未填") }
        return value ? L("是") : L("否")
    }

    private func formatNumber(_ value: Double?) -> String {
        formatNumber(value ?? 0)
    }

    private func formatNumber(_ value: Double) -> String {
        value == floor(value) ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}