import SwiftUI

// MARK: - 會報儀表板

struct HQReportsDashboardView: View {
    @ObservedObject var vm: HQViewModel

    var body: some View {
        HQPage {
            HQPageTitleBar(L("會報儀表板"), icon: "doc.richtext", accent: NV.command) {
                // 廣播者狀態
                HStack(spacing: 8) {
                    if let broadcaster = vm.currentBroadcaster {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(NV.danger)
                                .frame(width: 8, height: 8)
                            Text(L("%lld 廣播中", broadcaster))
                                .font(.caption)
                                .foregroundColor(NV.danger)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(NV.danger.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Text(L("%lld 筆報告", vm.radioReports.count))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if vm.radioReports.isEmpty {
                HQEmptyStateView(
                    icon: "doc.text",
                    title: L("尚無會報紀錄"),
                    subtitle: L("前線裝置錄製的會報將顯示在此")
                )
                .hqPanelChrome(accent: NV.command)
            } else {
                LazyVStack(spacing: NV.panelSpacing) {
                    ForEach(vm.radioReports) { report in
                        HQReportCard(report: report)
                    }
                }
            }
        }
    }
}

// MARK: - 報告卡片

private struct HQReportCard: View {
    let report: HQRadioReport
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 標題列
            HStack {
                Image(systemName: report.sourceType == .briefing ? "doc.text.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundColor(report.sourceType == .briefing ? NV.info : NV.command)
                Text(report.senderName)
                    .font(.headline)

                Text(report.sourceType == .briefing ? L("固定會報") : L("即時廣播"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(report.sourceType == .briefing ? NV.info.opacity(0.2) : NV.green.opacity(0.2))
                    )
                    .foregroundColor(report.sourceType == .briefing ? NV.info : NV.green)

                Spacer()
                Text(report.reportId)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Text(formatDate(report.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 位置
            if !report.location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(report.location)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            // 轉錄文字
            if !report.transcription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("轉錄內容"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(report.transcription)
                        .font(.body)
                        .lineLimit(expanded ? nil : 3)
                }
                .onTapGesture { expanded.toggle() }
            }

            // 氣象快照
            if !report.weatherSnapshot.isEmpty {
                DisclosureGroup("氣象快照") {
                    Text(report.weatherSnapshot)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .font(.caption.bold())
            }
        }
        .padding()
        .background(NV.surface)
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}
