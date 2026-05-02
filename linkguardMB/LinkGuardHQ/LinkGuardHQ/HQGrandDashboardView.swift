import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - HQ 大儀表板（Phase C）
// 整合 6 大面板：AI 主機健康度、受困者即時排序、AI 推送模式控制、
// 全節點清單、AI 對話時間軸、決策審計。
// 後端依賴此 Mac 內建 gemma4_server.py port 8001：
//   /ai/health, /ai/models, /ai/command/list, /ai/command/cancel/{id},
//   /ai/command/auto_dispatch
// host 來源：vm.effectiveBackendHost（內建模式固定為 127.0.0.1）
// 不使用 emoji。

struct HQGrandDashboardView: View {
    @ObservedObject var vm: HQViewModel
    @State private var aiHealth: AIHealthSnapshot? = nil
    @State private var pendingCommands: [AIProposal] = []
    @State private var lastFetchError: String? = nil
    @State private var pollTimer: Timer? = nil
    @State private var isLoading = false

    // 16 種指令的本地 mode 覆寫（HQ 緊急鎖定切全手動）
    @AppStorage("ai.modeOverride.global") private var globalModeOverride: String = "auto"  // auto | manual | locked

    private var port: Int { 8001 }
    private var host: String { vm.effectiveBackendHost }

    var body: some View {
        HQPage(spacing: NV.pageSpacing) {
            headerBar
            if let err = lastFetchError {
                Text("[ERROR] \(err)")
                    .font(.caption.monospaced())
                    .foregroundColor(NV.danger)
            }
            operationalSummaryGrid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: NV.panelSpacing),
                GridItem(.flexible(), spacing: NV.panelSpacing)
            ], spacing: NV.panelSpacing) {
                readinessPanel
                fieldOverviewPanel
                urgentWorkPanel
                backendServicesPanel
            }
            recentActivityPanel

            if hasAIBackendData {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: NV.panelSpacing),
                    GridItem(.flexible(), spacing: NV.panelSpacing)
                ], spacing: NV.panelSpacing) {
                    aiHealthPanel
                    rankedPatientsPanel
                }
                conversationTimelinePanel
                decisionAuditPanel
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HQPageTitleBar(L("HQ 大儀表板"), icon: "square.grid.3x3.fill", accent: NV.command) {
            HStack(spacing: 8) {
                statusChip("SERVER", vm.systemStatus.text,
                           ok: vm.server.isRunning || vm.peerClient.isConnected)
                statusChip("BACKEND", host.isEmpty ? "未連線" : host,
                           ok: !host.isEmpty)
                statusChip("MODE", globalModeOverride.uppercased(),
                           ok: globalModeOverride != "locked")
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label(L("重新整理"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || host.isEmpty)
            }
        }
    }

    private func statusChip(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? NV.green : NV.danger).frame(width: 8, height: 8)
            Text("\(label) ▸ \(value)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(NV.surface).cornerRadius(6)
    }

    // MARK: - 作戰概況

    private var hasAIBackendData: Bool {
        aiHealth != nil || !vm.backendBridge.rankedPatients.isEmpty ||
        !pendingCommands.isEmpty || !vm.backendBridge.backendDecisions.isEmpty
    }

    private var operationalSummaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: NV.panelSpacing)], spacing: NV.panelSpacing) {
            summaryTile(title: L("前線裝置"), value: "\(vm.connectedCount)/\(fieldUnitCount)", icon: "iphone.radiowaves.left.and.right", color: NV.green)
            summaryTile(title: L("受困者"), value: "\(vm.onlineVictimCount)/\(vm.totalVictimCount)", icon: "person.fill.questionmark", color: NV.info)
            summaryTile(title: "SOS", value: "\(vm.sosCount)", icon: "sos", color: vm.sosCount > 0 ? NV.danger : .gray)
            summaryTile(title: L("進行任務"), value: "\(vm.activeTaskCount)", icon: "checklist", color: NV.warning)
            summaryTile(title: L("後端服務"), value: "\(runningBackendCount)/\(vm.backendSupervisor.services.count)", icon: "cpu", color: backendProblemCount > 0 ? NV.warning : NV.green)
        }
    }

    private func summaryTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 68)
        .background(NV.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: NV.strokeWidth)
        )
    }

    private var readinessPanel: some View {
        panelCard(title: L("系統就緒度"), icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 8) {
                readinessRow(L("指揮伺服器"), detail: vm.server.isRunning ? L("運行中") : L("已停止"), ok: vm.server.isRunning)
                readinessRow(L("後端橋接"), detail: vm.isBackendConnected ? host : L("未連線"), ok: vm.isBackendConnected)
                readinessRow(L("照片伺服器"), detail: vm.photoServer.isRunning ? L("運行中") : L("已停止"), ok: vm.photoServer.isRunning)
                readinessRow(L("電台監聽"), detail: vm.udpAudioServer.isRunning ? L("運行中") : L("已停止"), ok: vm.udpAudioServer.isRunning)
                readinessRow(L("AI 服務"), detail: aiReadinessText, ok: !vm.backendSupervisor.isAIServicePaused)
            }
        }
    }

    private func readinessRow(_ title: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? NV.green : NV.warning)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.primary)
            Spacer()
            Text(detail)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var fieldOverviewPanel: some View {
        panelCard(title: L("前線與傷患"), icon: "person.3.sequence.fill") {
            if fieldUnitCount == 0 {
                emptyState(L("尚無前線裝置連線"), icon: "iphone.slash")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(fieldRows.prefix(6))) { row in
                        HStack(spacing: 8) {
                            Circle().fill(row.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                Text(row.detail)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(row.trailing)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var urgentWorkPanel: some View {
        panelCard(title: L("待處理重點"), icon: "exclamationmark.triangle.fill") {
            let items = urgentItems
            if items.isEmpty {
                emptyState(L("目前無緊急項目"), icon: "checkmark.shield")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.prefix(7))) { item in
                        infoRow(icon: item.icon, color: item.color, title: item.title, detail: item.detail, trailing: item.trailing)
                    }
                }
            }
        }
    }

    private var backendServicesPanel: some View {
        panelCard(title: L("後端健康度"), icon: "server.rack") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.backendSupervisor.services) { service in
                    let metrics = vm.backendSupervisor.metrics(for: service.id)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(backendStatusColor(service.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.spec.displayName)
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                            Text("\(service.spec.scriptName) · :\(service.spec.port)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(backendMetricsText(metrics))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var recentActivityPanel: some View {
        panelCard(title: L("最近動態"), icon: "clock.arrow.circlepath") {
            let rows = activityRows
            if rows.isEmpty {
                emptyState(L("尚無事件、通訊或廣播"), icon: "tray")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.prefix(8))) { row in
                        infoRow(icon: row.icon, color: row.color, title: row.title, detail: row.detail, trailing: row.trailing)
                    }
                }
            }
        }
    }

    private func infoRow(icon: String, color: Color, title: String, detail: String, trailing: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(trailing)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(NV.bg.opacity(0.3))
        .cornerRadius(6)
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var fieldUnitCount: Int {
        vm.hqRole == .peer ? vm.peerFieldUnitCount : vm.server.fieldUnits.count
    }

    private var runningBackendCount: Int {
        vm.backendSupervisor.services.filter { service in
            switch service.status {
            case .starting, .healthy, .unhealthy: return true
            case .stopped, .crashed: return false
            }
        }.count
    }

    private var backendProblemCount: Int {
        vm.backendSupervisor.services.filter { $0.status == .unhealthy || $0.status == .crashed }.count
    }

    private var aiReadinessText: String {
        if vm.backendSupervisor.isAIServicePaused {
            return vm.backendSupervisor.aiServicePauseReason ?? L("AI服務暫停")
        }
        guard let service = vm.backendSupervisor.services.first(where: { $0.id == BackendServiceSpec.aiServiceID }) else {
            return L("未設定")
        }
        if service.status == .stopped { return L("待命") }
        return backendStatusText(service.status)
    }

    private var fieldRows: [DashboardInfoRow] {
        if vm.hqRole == .peer, let units = vm.peerClient.serverStatus?.fieldUnits {
            return units.map { unit in
                DashboardInfoRow(
                    id: unit.id,
                    icon: "iphone.radiowaves.left.and.right",
                    color: unit.isOnline ? NV.green : .gray,
                    title: unit.deviceID,
                    detail: "\(unit.deptCode) · 傷患 \(unit.victimCount) · 人員 \(unit.teamCount)",
                    trailing: "BAT \(unit.battery)%"
                )
            }
        }
        return vm.server.fieldUnits.map { unit in
            DashboardInfoRow(
                id: unit.id,
                icon: "iphone.radiowaves.left.and.right",
                color: unit.isOnline ? NV.green : .gray,
                title: unit.deviceID,
                detail: "\(unit.deptCode) · 傷患 \(unit.victims.count) · 人員 \(unit.teamMembers.count)",
                trailing: "BAT \(unit.battery)%"
            )
        }
    }

    private var urgentItems: [DashboardInfoRow] {
        var rows: [DashboardInfoRow] = []

        rows += vm.activeSOSAlerts.sorted { $0.timestamp > $1.timestamp }.map { alert in
            DashboardInfoRow(
                id: "sos-\(alert.id)",
                icon: "sos",
                color: NV.danger,
                title: "SOS · \(alert.senderName)",
                detail: alert.deviceID,
                trailing: relativeTime(alert.timestamp)
            )
        }

        rows += vm.pwsAlerts.filter(\.isActive).sorted { $0.publishTime > $1.publishTime }.map { alert in
            DashboardInfoRow(
                id: "pws-\(alert.id)",
                icon: alert.alertType.icon,
                color: alert.severity.color,
                title: alert.title,
                detail: "\(alert.alertType.label) · \(alert.severity.label)",
                trailing: relativeTime(alert.publishTime)
            )
        }

        rows += vm.patientWarnings.sorted { $0.timestamp > $1.timestamp }.map { warning in
            DashboardInfoRow(
                id: "warning-\(warning.id.uuidString)",
                icon: "heart.text.square.fill",
                color: NV.warning,
                title: warning.patientName.isEmpty ? warning.patientId : warning.patientName,
                detail: warning.warningMessage,
                trailing: relativeTime(warning.timestamp)
            )
        }

        rows += vm.tasks.filter(\.isActive).sorted { $0.createdAt > $1.createdAt }.map { task in
            DashboardInfoRow(
                id: "task-\(task.id)",
                icon: "checklist",
                color: task.taskPriority.color,
                title: task.title,
                detail: task.assigneeName.isEmpty ? task.zone : task.assigneeName,
                trailing: task.taskStatus.label
            )
        }

        rows += vm.reinforcementRequests.filter { $0.status == .pending }.sorted { $0.timestamp > $1.timestamp }.map { request in
            DashboardInfoRow(
                id: "reinforce-\(request.id)",
                icon: "person.2.badge.plus",
                color: NV.reinforce,
                title: request.fromTeam,
                detail: request.message,
                trailing: relativeTime(request.timestamp)
            )
        }

        rows += vm.hazardReports.sorted { $0.timestamp > $1.timestamp }.prefix(3).map { hazard in
            DashboardInfoRow(
                id: "hazard-\(hazard.id)",
                icon: hazard.hazard?.icon ?? "exclamationmark.triangle.fill",
                color: hazard.hazard?.color ?? NV.warning,
                title: hazard.hazard?.label ?? hazard.hazardType,
                detail: hazard.description.isEmpty ? hazard.zone : hazard.description,
                trailing: hazard.timeText
            )
        }

        return rows
    }

    private var activityRows: [DashboardInfoRow] {
        var rows: [DashboardInfoRow] = []

        rows += vm.timelineEvents.prefix(5).map { event in
            DashboardInfoRow(
                id: "timeline-\(event.id)",
                icon: event.eventType.icon,
                color: event.eventType.color,
                title: event.title,
                detail: event.detail,
                trailing: event.relativeTimeText
            )
        }

        rows += vm.chatMessages.suffix(3).reversed().map { message in
            DashboardInfoRow(
                id: "chat-\(message.id)",
                icon: "bubble.left.and.bubble.right.fill",
                color: NV.team,
                title: message.senderName,
                detail: message.content,
                trailing: message.timeText
            )
        }

        rows += vm.textBroadcasts.prefix(3).map { broadcast in
            DashboardInfoRow(
                id: "broadcast-\(broadcast.broadcastId)",
                icon: "megaphone.fill",
                color: NV.danger,
                title: broadcast.senderName,
                detail: broadcast.message,
                trailing: broadcast.timeText
            )
        }

        rows += vm.radioReports.prefix(3).map { report in
            DashboardInfoRow(
                id: "radio-\(report.id.uuidString)",
                icon: "antenna.radiowaves.left.and.right",
                color: NV.green,
                title: report.senderName,
                detail: report.transcription,
                trailing: shortTime(report.timestamp)
            )
        }

        return rows
    }

    private func backendStatusText(_ status: BackendServiceStatus) -> String {
        switch status {
        case .stopped: return L("已停止")
        case .starting: return L("啟動中")
        case .healthy: return L("運行中")
        case .unhealthy: return L("異常")
        case .crashed: return L("已崩潰")
        }
    }

    private func backendStatusColor(_ status: BackendServiceStatus) -> Color {
        switch status {
        case .stopped: return .gray
        case .starting: return NV.warning
        case .healthy: return NV.green
        case .unhealthy: return NV.warning
        case .crashed: return NV.danger
        }
    }

    private func backendMetricsText(_ metrics: BackendProcessMetrics) -> String {
        if !metrics.cpu.isEmpty && !metrics.memMB.isEmpty {
            return "CPU \(metrics.cpu)% · \(metrics.memMB) MB"
        }
        return "--"
    }

    private func relativeTime(_ timestamp: Double) -> String {
        relativeTime(Date(timeIntervalSince1970: timestamp))
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return L("剛剛") }
        if seconds < 3600 { return "\(seconds / 60) 分前" }
        if seconds < 86400 { return "\(seconds / 3600) 小時前" }
        return shortTime(date)
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Panel 1: AI 主機健康度

    private var aiHealthPanel: some View {
        panelCard(title: L("AI 主機健康度"), icon: "cpu") {
            if let h = aiHealth {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(h.hosts, id: \.name) { host in
                        hostRow(host)
                    }
                    Divider().background(NV.greenDim)
                    HStack {
                        Text(L("Tier 路由："))
                            .font(.caption).foregroundColor(.secondary)
                        Text(h.tierRoutingSummary)
                            .font(.caption.monospaced())
                            .foregroundColor(.primary)
                    }
                }
            } else {
                Text(host.isEmpty ? L("請先連接 backend") : L("載入中…"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func hostRow(_ host: AIHostStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: host.ollama_ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(host.ollama_ok ? NV.green : NV.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(host.models.joined(separator: " / "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("queue \(host.queue)")
                    .font(.caption.monospaced())
                Text("err \(host.errors_5min)")
                    .font(.caption.monospaced())
                    .foregroundColor(host.errors_5min > 0 ? NV.warning : .secondary)
            }
        }
        .padding(8)
        .background(NV.bg.opacity(0.4))
        .cornerRadius(6)
    }

    // MARK: - Panel 2: 受困者即時排序

    private var rankedPatientsPanel: some View {
        panelCard(title: L("受困者即時排序（Top 10）"), icon: "person.fill.questionmark") {
            let top = Array(vm.backendBridge.rankedPatients.prefix(10))
            if top.isEmpty {
                Text(L("無資料"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(top.enumerated()), id: \.offset) { idx, p in
                        HStack(spacing: 8) {
                            Text("#\(idx + 1)")
                                .font(.caption.monospaced().bold())
                                .foregroundColor(NV.green)
                                .frame(width: 28, alignment: .leading)
                            Circle()
                                .fill(triageColor(p.priority))
                                .frame(width: 8, height: 8)
                            Text(p.location.isEmpty ? p.id : p.location)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f", p.totalScore))
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func triageColor(_ level: String) -> Color {
        switch level.uppercased() {
        case "RED", "P1", "重傷": return NV.danger
        case "YELLOW", "P2", "中傷": return Color.orange
        case "GREEN", "P3", "輕傷": return NV.green
        case "BLACK", "P5", "死亡": return Color.black
        default: return Color.gray
        }
    }

    // MARK: - Panel 5: AI 對話時間軸

    private var conversationTimelinePanel: some View {
        panelCard(title: L("AI 對話時間軸（最近）"), icon: "bubble.left.and.bubble.right") {
            if pendingCommands.isEmpty {
                Text(L("尚無待審/進行中提案"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingCommands) { p in
                        proposalTimelineRow(p)
                    }
                }
            }
        }
    }

    private func proposalTimelineRow(_ p: AIProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack {
                Image(systemName: p.iconName)
                    .foregroundColor(p.priorityColor)
                Text(p.priorityLabel.prefix(2))
                    .font(.caption2.monospaced())
                    .foregroundColor(p.priorityColor)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.typeLabel)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(p.id)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    if p.isAutoMode {
                        Text("AUTO \(p.countdown_sec)s")
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(NV.warning.opacity(0.3))
                            .foregroundColor(NV.warning)
                            .cornerRadius(3)
                    }
                    if p.requiresDoubleConfirm {
                        Text("DOUBLE-CONFIRM")
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(NV.danger.opacity(0.3))
                            .foregroundColor(NV.danger)
                            .cornerRadius(3)
                    }
                }
                Text(p.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 4) {
                Button(L("執行")) {
                    Task { await dispatchCommand(p.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(globalModeOverride == "locked")
                Button(L("取消")) {
                    Task { await cancelCommand(p.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(NV.bg.opacity(0.3))
        .cornerRadius(6)
    }

    // MARK: - Panel 6: 決策審計（簡版：用 backendDecisions）

    private var decisionAuditPanel: some View {
        panelCard(title: L("決策審計（最近 20 筆）"), icon: "list.bullet.clipboard") {
            let entries = Array(vm.backendBridge.backendDecisions.prefix(20))
            if entries.isEmpty {
                Text(L("無決策紀錄"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { d in
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(NV.green)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.decision)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Text("\(d.model) · \(d.timestamp)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if d.escalated {
                                Text("ESC")
                                    .font(.caption2.bold())
                                    .foregroundColor(NV.warning)
                            }
                        }
                        .padding(6)
                        .background(NV.bg.opacity(0.3))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Card wrapper

    private func panelCard<Content: View>(title: String, icon: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HQPanel(title: title, icon: icon, accent: NV.green) {
            content()
        }
    }

    // MARK: - Polling & API

    private func startPolling() {
        Task { await refreshAll() }
        pollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { await refreshAll() }
        }
        timer.tolerance = 3.0
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshAll() async {
        guard !host.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await fetchAIHealth()
        await fetchPendingCommands()
    }

    private func fetchAIHealth() async {
        guard let url = makeBackendURL(host: host, port: port, path: "/ai/health") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.aiHealth = AIHealthSnapshot(json: json)
                self.lastFetchError = nil
            }
        } catch {
            self.lastFetchError = "ai/health: \(error.localizedDescription)"
        }
    }

    private func fetchPendingCommands() async {
        guard let url = makeBackendURL(host: host, port: port, path: "/ai/command/list") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["commands"] as? [[String: Any]] else { return }
            let decoder = JSONDecoder()
            var out: [AIProposal] = []
            for item in arr {
                if let d = try? JSONSerialization.data(withJSONObject: item),
                   let p = try? decoder.decode(AIProposal.self, from: d) {
                    out.append(p)
                }
            }
            self.pendingCommands = out
        } catch {
            self.lastFetchError = "ai/command/list: \(error.localizedDescription)"
        }
    }

    private func dispatchCommand(_ id: String) async {
        guard let url = makeBackendURL(host: host, port: port,
                                        path: "/ai/command/auto_dispatch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        _ = try? await URLSession.shared.data(for: req)
        await fetchPendingCommands()
    }

    private func cancelCommand(_ id: String) async {
        guard let url = makeBackendURL(host: host, port: port,
                                        path: "/ai/command/cancel/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
        await fetchPendingCommands()
    }
}

private struct DashboardInfoRow: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let trailing: String
}

// MARK: - AI Health 結構

struct AIHealthSnapshot {
    let hosts: [AIHostStatus]
    let tierRouting: [String: String]

    init(json: [String: Any]) {
        var arr: [AIHostStatus] = []
        if let hosts = json["hosts"] as? [[String: Any]] {
            for h in hosts {
                arr.append(AIHostStatus(
                    name: (h["name"] as? String) ?? "host?",
                    models: (h["models"] as? [String]) ?? [],
                    ollama_ok: (h["ollama_ok"] as? Bool) ?? false,
                    queue: (h["queue"] as? Int) ?? 0,
                    errors_5min: (h["errors_5min"] as? Int) ?? 0
                ))
            }
        }
        self.hosts = arr
        if let tr = json["tier_routing"] as? [String: String] {
            self.tierRouting = tr
        } else if let tr = json["tier_routing"] as? [String: Any] {
            var dict: [String: String] = [:]
            for (k, v) in tr { dict[k] = "\(v)" }
            self.tierRouting = dict
        } else {
            self.tierRouting = [:]
        }
    }

    var tierRoutingSummary: String {
        let order = ["field", "hq_local", "hq_main"]
        return order.compactMap { k in
            tierRouting[k].map { "\(k)=\($0)" }
        }.joined(separator: " ")
    }
}

struct AIHostStatus {
    let name: String
    let models: [String]
    let ollama_ok: Bool
    let queue: Int
    let errors_5min: Int
}
