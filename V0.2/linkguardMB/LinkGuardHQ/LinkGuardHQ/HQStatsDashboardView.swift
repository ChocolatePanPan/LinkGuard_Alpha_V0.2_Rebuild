import SwiftUI

// MARK: - HQ 統計儀表板

struct HQStatsDashboardView: View {
    @ObservedObject var vm: HQViewModel

    private var stats: [String: Any] { vm.latestStatsUpdate ?? [:] }

    var body: some View {
        HQPage {
            HQPageHeader(L("統計儀表板"), icon: "chart.bar.xaxis", accent: NV.team)

            if stats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L("等待統計資料…"))
                        .foregroundColor(.secondary)
                    Text(L("統計伺服器每 30 秒推送一次"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .hqPanelChrome(accent: NV.team)
            } else {
                if let patients = stats["patients"] as? [String: Any] {
                    StatsSectionView(title: L("傷員統計"), icon: "person.fill.questionmark") {
                        HStack(spacing: NV.panelSpacing) {
                            StatsNumberCard(label: L("總計"), value: patients["total"] as? Int ?? 0, color: NV.info)
                            StatsNumberCard(label: L("即刻"), value: patients["immediate"] as? Int ?? 0, color: NV.danger)
                            StatsNumberCard(label: L("延遲"), value: patients["delayed"] as? Int ?? 0, color: NV.warning)
                            StatsNumberCard(label: L("輕微"), value: patients["minor"] as? Int ?? 0, color: NV.green)
                            StatsNumberCard(label: L("期望"), value: patients["expectant"] as? Int ?? 0, color: .gray)
                        }
                    }
                }

                if let personnel = stats["personnel"] as? [String: Any] {
                    let total = personnel["total"] as? Int ?? 0
                    let online = personnel["online"] as? Int ?? 0
                    StatsSectionView(title: L("人員狀態"), icon: "person.3.fill") {
                        HStack(spacing: NV.panelSpacing) {
                            StatsNumberCard(label: L("總人員"), value: total, color: NV.info)
                            StatsNumberCard(label: L("線上"), value: online, color: NV.green)
                            StatsNumberCard(label: L("離線"), value: total - online, color: .gray)
                        }
                    }
                }

                if let comms = stats["communications"] as? [String: Any] {
                    StatsSectionView(title: L("通訊統計"), icon: "bubble.left.and.bubble.right.fill") {
                        HStack(spacing: NV.panelSpacing) {
                            StatsNumberCard(label: L("聊天"), value: comms["chat_count"] as? Int ?? 0, color: NV.command)
                            StatsNumberCard(label: L("會報"), value: comms["radio_reports"] as? Int ?? 0, color: NV.team)
                            StatsNumberCard(label: L("命令"), value: comms["commands"] as? Int ?? 0, color: NV.green)
                        }
                    }
                }

                let decisions = stats["decisions_count"] as? Int ?? 0
                let photos = stats["photos_count"] as? Int ?? 0
                let duration = stats["event_duration_minutes"] as? Int ?? 0
                StatsSectionView(title: L("事件概覽"), icon: "chart.bar.fill") {
                    HStack(spacing: NV.panelSpacing) {
                        StatsNumberCard(label: L("決策"), value: decisions, color: NV.info)
                        StatsNumberCard(label: L("照片"), value: photos, color: NV.team)
                        StatsNumberCard(label: L("持續(分)"), value: duration, color: NV.warning)
                    }
                }
            }
        }
    }
}

// MARK: - 統計區段

struct StatsSectionView<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .hqPanelChrome(accent: NV.team)
    }
}

struct StatsNumberCard: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .rounded).bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: NV.tagRadius, style: .continuous))
    }
}
