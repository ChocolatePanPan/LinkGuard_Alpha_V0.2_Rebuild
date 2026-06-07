import SwiftUI
import LinkGuardV03Core

// MARK: - 電台監聽 (UCC Phase 16 / SCC Phase 17)

struct RadioMonitoringModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let voices = snapshot.voiceReports.values.sorted { $0.recordedAt > $1.recordedAt }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "antenna.radiowaves.left.and.right", title: "PTT 監聽與轉錄",
                                   detail: "監聽現場無線電 PTT，並以語音轉錄 (Whisper) 產生文字記錄。實體電台/UDP 音訊閘道為待接整合；以下為已透過通訊鏈進入快照的語音回報與群組訊息。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "語音回報", value: "\(snapshot.voiceReports.count)", systemImage: "waveform", accent: CCTheme.accent),
                ConsoleStatTile(title: "群組訊息", value: "\(snapshot.groupChatMessages.count)", systemImage: "bubble.left.and.bubble.right.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "已轉錄", value: "\(voices.filter { ($0.transcript?.isEmpty == false) }.count)", systemImage: "text.bubble.fill", accent: CCTheme.command)
            ])
            ConsoleListSection(title: "語音轉錄記錄", systemImage: "waveform.badge.mic", items: voices, maxRows: 30) { v in
                ConsoleRow(title: v.transcript?.isEmpty == false ? v.transcript! : "（未轉錄語音 \(String(format: "%.0f", v.durationSeconds))s）",
                           subtitle: "\(v.senderDeviceID.rawValue) · \(ConsoleFormat.stamp(v.recordedAt))",
                           leadingSystemImage: "mic.fill", leadingColor: CCTheme.priorityColor(v.priority))
            }
        }
    }
}

// MARK: - 事件日誌 (UCC Phase 15)

struct EventLogModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "稽核事件", value: "\(snapshot.auditEvents.count)", systemImage: "clock.arrow.circlepath", accent: CCTheme.accent),
                ConsoleStatTile(title: "決策紀錄", value: "\(snapshot.decisionRecords.count)", systemImage: "checkmark.seal.fill", accent: CCTheme.command),
                ConsoleStatTile(title: "命令", value: "\(snapshot.commands.count)", systemImage: "brain.head.profile", accent: CCTheme.info)
            ])
            ConsoleListSection(title: "全區事件日誌", systemImage: "clock.arrow.circlepath", items: snapshot.sortedAudit, maxRows: 60) { e in
                ConsoleRow(title: "\(e.action.consoleLabel) · \(e.targetType)",
                           subtitle: "\(e.appID.rawValue) · \(e.actorID.rawValue) · \(ConsoleFormat.stamp(e.createdAt))",
                           leadingSystemImage: "circle.fill", leadingColor: e.action.isSyncEvent ? CCTheme.muted : CCTheme.accent)
            }
        }
    }
}

// MARK: - 多裝置同步 (UCC Phase 17 / SCC Phase 21)

struct DeviceSyncModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let devices = snapshot.personnelStatusReports.values
            .sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "已接收封包", value: "\(state.runtime.receivedEnvelopeIDs.count)", systemImage: "tray.and.arrow.down.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "待送佇列", value: "\(state.runtime.pendingOutboundCount)", systemImage: "tray.and.arrow.up.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "在線裝置", value: "\(snapshot.onlinePersonnelCount)", systemImage: "iphone.gen3.radiowaves.left.and.right", accent: CCTheme.info),
                ConsoleStatTile(title: "已處理 idemp.", value: "\(snapshot.processedIdempotencyKeys.count)", systemImage: "checkmark.circle.fill", accent: CCTheme.command)
            ])
            ConsoleIntegrationNote(systemImage: "rectangle.connected.to.line.below", title: "Mac／iPad 指揮協同",
                                   detail: "多台指揮裝置共享同一個 incident 快照：每筆操作以 SyncEnvelope 廣播、依冪等鍵去重、離線時排隊重送。正式 server endpoint 與裝置配發 (provisioning) 為待接產品流程。")
            ConsoleListSection(title: "同步裝置狀態", systemImage: "iphone.gen3", items: devices, maxRows: 40) { d in
                ConsoleRow(title: "\(d.appID.rawValue) · \(d.deviceID.rawValue)",
                           subtitle: "\(d.role.consoleLabel) · 更新 \(ConsoleFormat.stamp(d.updatedAt))",
                           leadingSystemImage: "iphone.gen3", leadingColor: d.connectivity.consoleColor,
                           trailing: AnyView(ConsoleTag(d.connectivity.consoleLabel, color: d.connectivity.consoleColor)))
            }
        }
    }
}

// MARK: - 災後回放 / AAR (UCC Phase 20 / SCC Phase 22)

struct AARReplayModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        // Build a unified, time-ordered replay timeline from audit events, commands,
        // decisions, SOS and alerts.
        struct ReplayEntry: Identifiable {
            let id: String
            let date: Date
            let title: String
            let subtitle: String
            let icon: String
            let color: Color
        }
        var entries: [ReplayEntry] = []
        for e in snapshot.auditEvents {
            entries.append(.init(id: "a-\(e.id.rawValue)", date: e.createdAt,
                                 title: "\(e.action.consoleLabel) · \(e.targetType)",
                                 subtitle: "\(e.appID.rawValue) · \(e.actorID.rawValue)",
                                 icon: "clock", color: CCTheme.muted))
        }
        for c in snapshot.commands.values {
            entries.append(.init(id: "c-\(c.id.rawValue)", date: c.issuedAt,
                                 title: "命令：\(c.title)", subtitle: c.type.consoleLabel,
                                 icon: "brain.head.profile", color: CCTheme.command))
        }
        for d in snapshot.decisionRecords.values {
            entries.append(.init(id: "d-\(d.id.rawValue)", date: d.decidedAt,
                                 title: "決策：\(d.title)", subtitle: d.reason,
                                 icon: "checkmark.seal.fill", color: CCTheme.accent))
        }
        for s in snapshot.sosReports.values {
            entries.append(.init(id: "s-\(s.id.rawValue)", date: s.createdAt,
                                 title: "SOS：\(s.dangerType.consoleLabel)", subtitle: s.status.consoleLabel,
                                 icon: "sos.circle.fill", color: CCTheme.danger))
        }
        let timeline = entries.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "play.rectangle.on.rectangle.fill", title: "災後回放與檢討",
                                   detail: "依時間序重建事故全程：命令、決策、SOS、同步收據與現場操作皆可回放，作為 AAR 檢討與訓練素材。逐格時間軸拖曳重播為產品化中。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "時間軸事件", value: "\(timeline.count)", systemImage: "timeline.selection", accent: CCTheme.accent),
                ConsoleStatTile(title: "命令", value: "\(snapshot.commands.count)", systemImage: "brain.head.profile", accent: CCTheme.command),
                ConsoleStatTile(title: "決策", value: "\(snapshot.decisionRecords.count)", systemImage: "checkmark.seal.fill", accent: CCTheme.info)
            ])
            ConsoleListSection(title: "回放時間軸", systemImage: "timeline.selection", items: timeline, maxRows: 80) { entry in
                ConsoleRow(title: entry.title, subtitle: "\(ConsoleFormat.stamp(entry.date)) · \(entry.subtitle)",
                           leadingSystemImage: entry.icon, leadingColor: entry.color)
            }
        }
    }
}
