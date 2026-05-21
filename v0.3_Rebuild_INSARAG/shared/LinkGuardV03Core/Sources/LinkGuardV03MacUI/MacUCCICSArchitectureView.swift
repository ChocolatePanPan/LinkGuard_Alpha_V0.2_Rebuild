import LinkGuardV03Core
import SwiftUI

struct MacUCCICSArchitecturePanel: View {
    let architecture: MacUCCICSArchitecture
    @State private var isMappingExpanded = false

    var body: some View {
        HQPanel(title: architecture.title, icon: "building.columns.fill", accent: NV.command) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                mappingSection
                Divider()
                laneList
                Divider()
                boundaryList
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(architecture.commandAuthority.macDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(NV.command)
            Text(architecture.coordinationRole)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut) {
                    isMappingExpanded.toggle()
                }
            }) {
                HStack {
                    Label("ICS 部門與 LinkGuard-E 對照表", systemImage: "list.bullet.indent")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(NV.green)
                    Spacer()
                    Image(systemName: isMappingExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isMappingExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        mappingRow(dept: "Incident Commander", title: "事故指揮官", job: "統一指揮、設定目標、核准行動計畫", desc: "消防指揮官／現場總指揮")
                        mappingRow(dept: "Command Staff", title: "指揮幕僚", job: "安全、媒體、跨單位聯絡", desc: "系統管理、對外通報、安全提醒")
                        mappingRow(dept: "Operations Section", title: "作業組", job: "執行現場搜救與戰術任務", desc: "搜救員終端、任務分派、受困者救援")
                        mappingRow(dept: "Planning Section", title: "計畫組", job: "蒐集資料、判斷災情、建立行動計畫", desc: "AI 分析、受困者排序、災情地圖")
                        mappingRow(dept: "Logistics Section", title: "後勤組", job: "通訊、設備、補給、交通、醫療支援", desc: "LoRa 節點、NFC 傷票、設備電量、通訊維護")
                        mappingRow(dept: "Finance/Admin Section", title: "財務／行政組", job: "成本、採購、工時、文件紀錄", desc: "系統紀錄、任務歷程、災後報告")
                    }
                    .padding(6)
                    .background(NV.nightVisionSurface.opacity(0.5))
                    .cornerRadius(6)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 4)
            }
        }
    }

    private func mappingRow(dept: String, title: String, job: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(dept)
                    .font(.caption2.monospaced().bold())
                    .foregroundColor(.white)
                Spacer()
                Text(title)
                    .font(.caption2.bold())
                    .foregroundColor(NV.command)
            }
            Text("核心職能: \(job)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(NV.green)
                Text("對應 LGE: \(desc)")
                    .font(.system(size: 10).weight(.medium))
                    .foregroundColor(NV.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var laneList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(architecture.lanes) { lane in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: lane.systemImageName)
                        .foregroundColor(NV.green)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lane.title)
                            .font(.caption.weight(.semibold))
                        Text(lane.roleInUCC)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lane.authorityBoundary)
                            .font(.caption2)
                            .foregroundColor(NV.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var boundaryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(architecture.boundaryRules) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title)
                        .font(.caption.weight(.semibold))
                    Text(rule.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
