import SwiftUI

// MARK: - HQ 統計儀表板

struct HQStatsDashboardView: View {
    @ObservedObject var vm: HQViewModel

    private var stats: [String: Any] { vm.latestStatsUpdate ?? [:] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("統計儀表板"))
                    .font(.title).bold()
                    .padding(.horizontal)

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
                } else {
                    // 傷員統計
                    if let patients = stats["patients"] as? [String: Any] {
                        StatsSectionView(title: "傷員統計", icon: "person.fill.questionmark") {
                            HStack(spacing: 16) {
                                StatsNumberCard(label: "總計", value: patients["total"] as? Int ?? 0, color: NV.info)
                                StatsNumberCard(label: "即刻", value: patients["immediate"] as? Int ?? 0, color: NV.danger)
                                StatsNumberCard(label: "延遲", value: patients["delayed"] as? Int ?? 0, color: NV.warning)
                                StatsNumberCard(label: "輕微", value: patients["minor"] as? Int ?? 0, color: NV.green)
                                StatsNumberCard(label: "期望", value: patients["expectant"] as? Int ?? 0, color: .gray)
                            }
                        }
                    }

                    // 人員
                    if let personnel = stats["personnel"] as? [String: Any] {
                        let total = personnel["total"] as? Int ?? 0
                        let online = personnel["online"] as? Int ?? 0
                        StatsSectionView(title: "人員狀態", icon: "person.3.fill") {
                            HStack(spacing: 16) {
                                StatsNumberCard(label: "總人員", value: total, color: NV.info)
                                StatsNumberCard(label: "線上", value: online, color: NV.green)
                                StatsNumberCard(label: "離線", value: total - online, color: .gray)
                            }
                        }
                    }

                    // 通訊統計
                    if let comms = stats["communications"] as? [String: Any] {
                        StatsSectionView(title: "通訊統計", icon: "bubble.left.and.bubble.right.fill") {
                            HStack(spacing: 16) {
                                StatsNumberCard(label: "聊天", value: comms["chat_count"] as? Int ?? 0, color: NV.command)
                                StatsNumberCard(label: "會報", value: comms["radio_reports"] as? Int ?? 0, color: NV.team)
                                StatsNumberCard(label: "命令", value: comms["commands"] as? Int ?? 0, color: NV.green)
                            }
                        }
                    }

                    // 其他
                    let decisions = stats["decisions_count"] as? Int ?? 0
                    let photos = stats["photos_count"] as? Int ?? 0
                    let duration = stats["event_duration_minutes"] as? Int ?? 0
                    StatsSectionView(title: "事件概覽", icon: "chart.bar.fill") {
                        HStack(spacing: 16) {
                            StatsNumberCard(label: "決策", value: decisions, color: NV.info)
                            StatsNumberCard(label: "照片", value: photos, color: NV.team)
                            StatsNumberCard(label: "持續(分)", value: duration, color: NV.warning)
                        }
                    }
                }
            }
            .padding()
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
        .padding()
        .background(NV.surface.opacity(0.5))
        .cornerRadius(12)
        .padding(.horizontal)
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
        .cornerRadius(8)
    }
}
