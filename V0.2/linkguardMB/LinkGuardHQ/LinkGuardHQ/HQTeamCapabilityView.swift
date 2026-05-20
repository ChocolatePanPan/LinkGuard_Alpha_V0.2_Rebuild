import SwiftUI

struct HQTeamCapabilityView: View {
    @ObservedObject var vm: HQViewModel

    private var reports: [TeamCapabilityReport] {
        vm.teamCapabilityReports.sorted { $0.timestamp > $1.timestamp }
    }

    private var totalMembers: Int {
        reports.reduce(0) { $0 + $1.totalMembers }
    }

    private var rescueVehicles: Int {
        reports.reduce(0) { $0 + $1.rescueVehicles }
    }

    private var activeTeams: Int {
        reports.filter { $0.missionStatus != "不可派遣" }.count
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
            Label(L("隊伍能力概況"), systemImage: "person.3.fill")
                .font(.title2.bold())
                .foregroundStyle(NV.green)
            Text(L("前線支援隊回報的人力、車輛、專長與支援需求集中顯示於此。"))
                .foregroundStyle(.secondary)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            metricCard(title: L("回報隊伍"), value: "\(reports.count)", icon: "doc.text.fill", color: NV.info)
            metricCard(title: L("可用隊伍"), value: "\(activeTeams)", icon: "checkmark.seal.fill", color: NV.green)
            metricCard(title: L("總人力"), value: "\(totalMembers)", icon: "person.3.sequence.fill", color: NV.team)
            metricCard(title: L("救援車"), value: "\(rescueVehicles)", icon: "truck.box.fill", color: NV.command)
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
            Text(L("尚未收到隊伍能力概況"))
                .font(.headline)
            Text(L("前線在 iPhone 的能力概況表送出後，會自動出現在這裡。"))
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
                    Text([report.unitCode, report.currentLocation].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge(report.missionStatus)
                    Text(report.timeText).font(.caption).foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                infoRow(L("人力"), report.personnelSummary)
                infoRow(L("車輛裝備"), report.vehicleSummary)
                infoRow(L("可出勤"), L("%lld 分鐘內", report.availableInMinutes))
                infoRow(L("作業 / 自給"), L("%lld 小時 / %lld 小時", report.operationalHours, report.selfSufficiencyHours))
            }

            detailBlock(title: L("能力項目"), content: report.capabilitySummary)
            detailBlock(title: L("主要裝備"), content: report.equipmentNotes)
            detailBlock(title: L("支援需求"), content: report.supportNeeds)
            detailBlock(title: L("備註"), content: report.remarks)

            HStack {
                if !report.leaderName.isEmpty {
                    Label(report.leaderName, systemImage: "person.crop.circle")
                }
                if !report.contactPhone.isEmpty {
                    Label(report.contactPhone, systemImage: "phone.fill")
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
        let color = colorForStatus(status)
        return Text(L(status))
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(NV.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func detailBlock(title: String, content: String) -> some View {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(trimmed).font(.subheadline)
            }
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "可派遣": return NV.green
        case "集結中": return NV.warning
        case "出勤中": return NV.command
        case "整補中": return NV.info
        case "不可派遣": return NV.danger
        default: return NV.info
        }
    }
}