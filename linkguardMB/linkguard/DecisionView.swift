import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 指揮決策與命令（合併顯示）

/// 統一時間軸項目（決策 or 命令）
private enum CommandTimelineItem: Identifiable {
    case decision(HQDecision)
    case command(CommandOrder)

    var id: String {
        switch self {
        case .decision(let d): return "d-\(d.id)"
        case .command(let c): return "c-\(c.id)"
        }
    }

    var date: Date {
        switch self {
        case .decision(let d): return d.receivedAt
        case .command(let c): return c.time
        }
    }
}

struct DecisionView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var previousCount = 0

    private var timelineItems: [CommandTimelineItem] {
        let dItems = vm.decisions.map { CommandTimelineItem.decision($0) }
        let cItems = vm.commandOrders.map { CommandTimelineItem.command($0) }
        return (dItems + cItems).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if timelineItems.isEmpty {
                    emptyState
                } else {
                    timelineList
                }
            }
            .navigationTitle(L("指揮決策"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .ignoresSafeArea(.container, edges: .top)
            .toolbar {
                if vm.unreadCommandCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L("全部已讀")) {
                            vm.markAllCommandsAsRead()
                        }
                        .font(.subheadline)
                    }
                }
            }
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
        }
        .onChange(of: vm.decisions.count) { oldCount, newCount in
            if newCount > oldCount { triggerHaptic() }
        }
        .onChange(of: vm.commandOrders.count) { oldCount, newCount in
            if newCount > oldCount { triggerHaptic() }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L("尚未收到指揮命令"))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(L("當指揮中心發布決策或命令後，將顯示於此處"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 統一時間軸

    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 資源狀態列
                if let res = vm.resourceStatus {
                    ResourceStatusBar(resource: res)
                }

                ForEach(timelineItems) { item in
                    switch item {
                    case .decision(let decision):
                        DecisionCard(
                            decision: decision,
                            readStatus: vm.readStatuses[decision.decisionId]
                        )
                    case .command(let order):
                        CommandCard(order: order) {
                            vm.markCommandAsRead(order)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 震動

    private func triggerHaptic() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #endif
    }
}

// MARK: - 決策卡片

struct DecisionCard: View {
    let decision: HQDecision
    var readStatus: (total: Int, readCount: Int)?
    @State private var isExpanded = true

    private var receivedTimeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: decision.receivedAt)
    }

    private var triggerLabel: String {
        switch decision.trigger {
        case "patient":    return L("傷員回報觸發")
        case "voice":      return L("語音回報觸發")
        case "manual":     return L("手動觸發")
        case "hq_request": return L("AI 建議觸發")
        case "llm", "ai":  return L("AI 自動觸發")
        default:           return "觸發: \(decision.trigger)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "megaphone.fill")
                        .font(.headline)
                        .foregroundColor(NV.command)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L("指揮決策"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !triggerLabel.isEmpty {
                                Text(triggerLabel)
                                    .font(.caption2)
                                    .foregroundColor(NV.info)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(NV.info.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if !decision.model.isEmpty {
                                Text(decision.model)
                                    .font(.caption2)
                                    .foregroundColor(decision.escalated ? .orange : NV.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background((decision.escalated ? Color.orange : NV.green).opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if decision.escalated {
                                Text("⬆ " + L("升級"))
                                    .font(.caption2).bold()
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if decision.provisional {
                                let label: String = {
                                    switch decision.escalationStatus {
                                    case "queued":
                                        if let pos = decision.queuePosition {
                                            return "🕐 " + L("轉介中") + "・第\(pos)順位"
                                        }
                                        return "🕐 " + L("轉介中")
                                    case "processing":
                                        return "🤖 " + L("大模型分析中")
                                    case "pending":
                                        return "📨 " + L("送出升級")
                                    default:
                                        return "🕐 " + L("初步決策")
                                    }
                                }()
                                Text(label)
                                    .font(.caption2).bold()
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.yellow.opacity(0.18))
                                    .clipShape(Capsule())
                            } else if decision.escalationStatus == "failed" {
                                Text("⚠ " + L("升級失敗"))
                                    .font(.caption2).bold()
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(L("收到：%@  ·  發布：%@", receivedTimeText, decision.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, 16)

            // 決策文字
            Text(decision.decision)
                .font(.title3)
                .bold()
                .foregroundColor(NV.command)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 傷員列表
            if isExpanded && !decision.patients.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("傷員優先順序 (%lld 人)", decision.patients.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    ForEach(decision.patients) { patient in
                        PatientEntryRow(entry: patient)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 12)
            }

            // 氣象快照
            if isExpanded, let w = decision.weather {
                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    if let temp = w.temperature {
                        Label("\(temp, specifier: "%.1f")°C", systemImage: "thermometer.medium")
                    }
                    if let hum = w.humidity {
                        Label("\(hum, specifier: "%.0f")%", systemImage: "humidity.fill")
                    }
                    if let wind = w.wind_speed {
                        Label("\(wind, specifier: "%.1f")m/s", systemImage: "wind")
                    }
                    if let rain = w.rainfall, rain > 0 {
                        Label("\(rain, specifier: "%.1f")mm", systemImage: "cloud.rain.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // 已讀回條
            if let status = readStatus, status.total > 0 {
                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(status.readCount >= status.total ? NV.green : .secondary)
                    Text(L("已讀 %lld/%lld", status.readCount, status.total))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(status.readCount), total: Double(status.total))
                        .tint(status.readCount >= status.total ? NV.green : NV.command)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(priorityBorderColor(decision.patients), lineWidth: 1.5)
        )
    }

    private func priorityBorderColor(_ patients: [PatientDecisionEntry]) -> Color {
        if patients.contains(where: { $0.priority.lowercased() == "red" }) { return NV.danger }
        if patients.contains(where: { $0.priority.lowercased() == "yellow" }) { return NV.warning }
        return NV.command.opacity(0.4)
    }
}

// MARK: - 傷員條目列

struct PatientEntryRow: View {
    let entry: PatientDecisionEntry

    private var priorityColor: Color {
        let p = entry.priority.lowercased()
        if p == "red" || p.contains(L("紅")) { return NV.danger }
        if p == "black" || p.contains(L("黑")) { return Color(white: 0.15) }
        if p == "yellow" || p.contains(L("黃")) { return NV.warning }
        if p == "green" || p.contains(L("綠")) { return NV.green }
        return .gray
    }

    private var priorityLabel: String {
        let p = entry.priority.lowercased()
        if p == "red" || p.contains(L("紅")) { return L("紅") }
        if p == "black" || p.contains(L("黑")) { return L("黑") }
        if p == "yellow" || p.contains(L("黃")) { return L("黃") }
        if p == "green" || p.contains(L("綠")) { return L("綠") }
        return entry.priority
    }

    var body: some View {
        HStack(spacing: 10) {
            // 優先色條
            RoundedRectangle(cornerRadius: 3)
                .fill(priorityColor)
                .frame(width: 5, height: 36)

            // 優先級標籤
            Text(priorityLabel)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(priorityColor, in: Circle())

            // ID 與位置 + 原因
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.id)
                    .font(.subheadline.bold())
                if !entry.location.isEmpty {
                    Text(entry.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !entry.reason.isEmpty {
                    Text(entry.reason)
                        .font(.caption2)
                        .foregroundColor(priorityColor.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(priorityColor.opacity(0.08)), in: .rect(cornerRadius: 8))
    }
}

// MARK: - 資源狀態列

struct ResourceStatusBar: View {
    let resource: ResourceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("現場資源"))
                .font(.caption).bold()
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                ResourcePill(icon: "cross.case.fill", text: resource.ambulanceText,
                             ratio: Double(resource.ambulanceAvailable) / max(Double(resource.ambulanceTotal), 1))
                ResourcePill(icon: "heart.fill", text: resource.medicalKitText,
                             ratio: Double(resource.medicalKitAvailable) / max(Double(resource.medicalKitTotal), 1))
                ResourcePill(icon: "person.fill", text: resource.personnelText,
                             ratio: Double(resource.personnelAvailable) / max(Double(resource.personnelTotal), 1))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct ResourcePill: View {
    let icon: String
    let text: String
    let ratio: Double

    private var color: Color {
        if ratio > 0.5 { return NV.green }
        if ratio > 0.2 { return .orange }
        return NV.danger
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 命令卡片

struct CommandCard: View {
    let order: CommandOrder
    var onMarkRead: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            HStack(spacing: 10) {
                Image(systemName: order.priority.icon)
                    .font(.headline)
                    .foregroundColor(order.priority.color)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("指揮命令"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(L(order.type.rawValue))
                            .font(.caption2)
                            .foregroundColor(NV.info)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(NV.info.opacity(0.15))
                            .clipShape(Capsule())
                        if !order.isRead {
                            Circle()
                                .fill(NV.info)
                                .frame(width: 8, height: 8)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(order.sender)
                        Text("·")
                        Text(order.timeText)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(order.priority.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundColor(NV.textOnColor)
                        .glassEffect(.regular.tint(order.priority.color), in: .rect(cornerRadius: 4))
                    if !order.isRead {
                        Button(L("已讀")) { onMarkRead?() }
                            .font(.caption2).bold()
                            .buttonStyle(.glass)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            // 命令內容
            Text(order.title)
                .font(.title3)
                .bold()
                .foregroundColor(order.priority.color)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !order.detail.isEmpty {
                Text(order.detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer().frame(height: 14)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(order.priority.color.opacity(0.4), lineWidth: 1.5)
        )
    }
}
