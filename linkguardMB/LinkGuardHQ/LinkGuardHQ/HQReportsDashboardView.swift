import SwiftUI

// MARK: - 會報儀表板

struct HQReportsDashboardView: View {
    @ObservedObject var vm: HQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.title2)
                    .foregroundColor(NV.command)
                Text(L("會報儀表板"))
                    .font(.title2.bold())
                Spacer()

                // 廣播者狀態
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            Divider()

            if vm.radioReports.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(L("尚無會報紀錄"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(L("前線裝置錄製的會報將顯示在此"))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.radioReports) { report in
                            HQReportCard(report: report)
                        }
                    }
                    .padding()
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
