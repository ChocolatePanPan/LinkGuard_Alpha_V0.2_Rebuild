import SwiftUI
import LinkGuardV03Core

// The legacy copied-HQ code defines its own `CommandType`, `TaskStatus`,
// `WorksiteStatus` and `ASRLevel` inside this same module. These aliases pin our
// display extensions to the LinkGuardV03Core types so they attach to the model
// values we actually read from the snapshot.
typealias CCCommandType = LinkGuardV03Core.CommandType
typealias CCTaskStatus = LinkGuardV03Core.TaskStatus
typealias CCWorksiteStatus = LinkGuardV03Core.WorksiteStatus
typealias CCASRLevel = LinkGuardV03Core.ASRLevel

// MARK: - Generic list section used by most console modules

struct ConsoleListSection<Item, Row: View>: View {
    let title: String
    var systemImage: String
    var accent: Color = CCTheme.accent
    let items: [Item]
    var emptyMessage: String = "目前沒有資料。"
    var maxRows: Int = 200
    let row: (Item) -> Row

    var body: some View {
        ConsolePanel(title + "（\(items.count)）", systemImage: systemImage, accent: accent) {
            if items.isEmpty {
                Text(emptyMessage).font(.caption).foregroundColor(CCTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(items.prefix(maxRows).enumerated()), id: \.offset) { _, item in row(item) }
                    if items.count > maxRows {
                        Text("…另有 \(items.count - maxRows) 筆").font(.caption2).foregroundColor(CCTheme.muted)
                    }
                }
            }
        }
    }
}

// MARK: - Snapshot-derived query helpers shared across modules

extension OperationSnapshot {
    var sortedSOS: [SOSReport] {
        sosReports.values.sorted { lhs, rhs in
            if lhs.status == rhs.status { return lhs.createdAt > rhs.createdAt }
            return lhs.status.consoleRank < rhs.status.consoleRank
        }
    }

    var activeSOSCount: Int { sosReports.values.filter { $0.status == .active }.count }

    var openTasks: [FieldTask] {
        tasks.values
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { $0.priority > $1.priority }
    }

    var sortedTasks: [FieldTask] {
        tasks.values.sorted { lhs, rhs in
            if lhs.status.consoleRank == rhs.status.consoleRank { return lhs.priority > rhs.priority }
            return lhs.status.consoleRank < rhs.status.consoleRank
        }
    }

    var sortedPersonnel: [PersonnelStatusReport] {
        personnelStatusReports.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var sortedPatients: [PatientRecord] {
        patients.values.sorted { lhs, rhs in
            if lhs.triageCategory.consoleRank == rhs.triageCategory.consoleRank { return lhs.updatedAt > rhs.updatedAt }
            return lhs.triageCategory.consoleRank < rhs.triageCategory.consoleRank
        }
    }

    var sortedAlerts: [IncidentAlert] {
        alerts.values.sorted { $0.issuedAt > $1.issuedAt }
    }

    var sortedCommands: [OperationalCommand] {
        commands.values.sorted { $0.issuedAt > $1.issuedAt }
    }

    var sortedAudit: [AuditEvent] {
        auditEvents.sorted { $0.createdAt > $1.createdAt }
    }

    var activeHazardZones: [SafetyZone] {
        safetyZones.values.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.severity > rhs.severity
        }
    }

    func triageCount(_ category: TriageCategory) -> Int {
        patients.values.filter { $0.triageCategory == category }.count
            + patientOperationalSummaries.values.filter { $0.triageCategory == category }.count
    }

    var onlinePersonnelCount: Int {
        personnelStatusReports.values.filter { $0.connectivity == .online }.count
    }

    var maydayPersonnel: [PersonnelStatusReport] {
        personnelStatusReports.values.filter { $0.operationalState == .mayday }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

extension SOSStatus {
    var consoleRank: Int {
        switch self {
        case .active: return 0
        case .acknowledged: return 1
        case .responding: return 2
        case .resolved: return 3
        case .cancelled: return 4
        }
    }
    var consoleLabel: String {
        switch self {
        case .active: return "待處理"
        case .acknowledged: return "已確認"
        case .responding: return "處理中"
        case .resolved: return "已解除"
        case .cancelled: return "已取消"
        }
    }
    var consoleColor: Color {
        switch self {
        case .active: return CCTheme.danger
        case .acknowledged: return CCTheme.warning
        case .responding: return CCTheme.info
        case .resolved: return CCTheme.accent
        case .cancelled: return CCTheme.muted
        }
    }
}

extension SOSDangerType {
    var consoleLabel: String {
        switch self {
        case .trapped: return "受困"
        case .injured: return "傷患"
        case .collapseRisk: return "倒塌風險"
        case .fireOrSmoke: return "火災/濃煙"
        case .hazardousMaterial: return "危險物質"
        case .communicationsFailure: return "通訊中斷"
        case .missingTeam: return "失聯隊伍"
        case .other: return "其他"
        }
    }
}

extension CCTaskStatus {
    var consoleRank: Int {
        switch self {
        case .inProgress: return 0
        case .accepted: return 1
        case .assigned: return 2
        case .blocked: return 3
        case .draft: return 4
        case .completed: return 5
        case .cancelled: return 6
        }
    }
    var consoleLabel: String {
        switch self {
        case .draft: return "草稿"
        case .assigned: return "已派遣"
        case .accepted: return "已接收"
        case .inProgress: return "執行中"
        case .blocked: return "受阻"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }
    var consoleColor: Color {
        switch self {
        case .inProgress: return CCTheme.info
        case .accepted, .assigned: return CCTheme.accent
        case .blocked: return CCTheme.danger
        case .draft: return CCTheme.muted
        case .completed: return CCTheme.accent.opacity(0.7)
        case .cancelled: return CCTheme.muted
        }
    }
}

extension TaskType {
    var consoleLabel: String {
        switch self {
        case .search: return "搜索"
        case .rescue: return "救援"
        case .recon: return "勘查"
        case .safetyCheck: return "安全檢查"
        case .supplyDelivery: return "物資運送"
        case .medicalSupport: return "醫療支援"
        case .evacuationSupport: return "撤離支援"
        }
    }
}

extension TriageCategory {
    var consoleRank: Int {
        switch self {
        case .red: return 0
        case .yellow: return 1
        case .green: return 2
        case .black: return 3
        }
    }
    var consoleLabel: String {
        switch self {
        case .red: return "紅 (危急)"
        case .yellow: return "黃 (緊急)"
        case .green: return "綠 (輕傷)"
        case .black: return "黑 (死亡)"
        }
    }
    var consoleColor: Color {
        switch self {
        case .red: return CCTheme.danger
        case .yellow: return CCTheme.warning
        case .green: return CCTheme.accent
        case .black: return CCTheme.muted
        }
    }
}

extension PersonnelOperationalState {
    var consoleLabel: String {
        switch self {
        case .available: return "待命"
        case .assigned: return "已派遣"
        case .entering: return "進入中"
        case .inWorksite: return "工址內"
        case .exiting: return "撤出中"
        case .resting: return "休整"
        case .mayday: return "MAYDAY"
        case .offline: return "離線"
        }
    }
    var consoleColor: Color {
        switch self {
        case .mayday: return CCTheme.danger
        case .inWorksite, .entering: return CCTheme.info
        case .assigned, .exiting: return CCTheme.accent
        case .available, .resting: return CCTheme.muted
        case .offline: return CCTheme.muted.opacity(0.6)
        }
    }
}

extension DeviceConnectivityStatus {
    var consoleLabel: String {
        switch self {
        case .online: return "在線"
        case .degraded: return "弱訊"
        case .offline: return "離線"
        case .unknown: return "未知"
        }
    }
    var consoleColor: Color {
        switch self {
        case .online: return CCTheme.accent
        case .degraded: return CCTheme.warning
        case .offline, .unknown: return CCTheme.muted
        }
    }
}

extension SafetyZoneType {
    var consoleLabel: String {
        switch self {
        case .hotZone: return "熱區 (高危)"
        case .warmZone: return "溫區"
        case .coldZone: return "冷區"
        case .noEntry: return "禁止進入"
        case .collapseRisk: return "倒塌風險"
        case .hazardousMaterial: return "危險物質"
        }
    }
    var consoleColor: Color {
        switch self {
        case .hotZone, .collapseRisk: return CCTheme.danger
        case .noEntry, .hazardousMaterial: return CCTheme.warning
        case .warmZone: return CCTheme.info
        case .coldZone: return CCTheme.accent
        }
    }
}

extension ICSPosition {
    var consoleLabel: String {
        switch self {
        case .incidentCommander: return "事故指揮官"
        case .publicInformationOfficer: return "公共資訊官"
        case .safetyOfficer: return "安全官"
        case .liaisonOfficer: return "聯絡官"
        case .operationsSectionChief: return "作業組長"
        case .planningSectionChief: return "計畫組長"
        case .logisticsSectionChief: return "後勤組長"
        case .financeSectionChief: return "財務組長"
        case .sectorCommander: return "分區指揮"
        case .teamLeader: return "小隊長"
        case .teamMember: return "搜救員"
        case .volunteer: return "志工"
        case .emtLead: return "醫療組長"
        case .emt: return "醫療人員"
        }
    }
}

extension CCWorksiteStatus {
    var consoleRank: Int {
        switch self {
        case .inProgress: return 0
        case .assigned: return 1
        case .blocked: return 2
        case .proposed: return 3
        case .completed: return 4
        case .abandoned: return 5
        }
    }
    var consoleLabel: String {
        switch self {
        case .proposed: return "提案"
        case .assigned: return "已指派"
        case .inProgress: return "搜救中"
        case .blocked: return "受阻"
        case .completed: return "已淨空"
        case .abandoned: return "放棄"
        }
    }
    var consoleColor: Color {
        switch self {
        case .inProgress: return CCTheme.info
        case .assigned: return CCTheme.accent
        case .blocked: return CCTheme.danger
        case .proposed: return CCTheme.muted
        case .completed: return CCTheme.accent.opacity(0.7)
        case .abandoned: return CCTheme.muted
        }
    }
}

extension CCASRLevel {
    var consoleLabel: String {
        switch self {
        case .asr1: return "ASR-1"
        case .asr2: return "ASR-2"
        case .asr3: return "ASR-3"
        case .asr4: return "ASR-4"
        case .asr5: return "ASR-5"
        }
    }
}

extension MapFeatureType {
    var consoleLabel: String {
        switch self {
        case .victimPoint: return "受困者點"
        case .assemblyPoint: return "集結點"
        case .safetyZone: return "安全區"
        case .restrictedZone: return "管制區"
        case .roadBlockLine: return "封鎖線"
        case .hazardPolygon: return "危險區面"
        case .collapsedAreaPolygon: return "倒塌區面"
        case .triageArea: return "檢傷區"
        case .casualtyCollectionPoint: return "傷患集中點"
        case .medicalStation: return "醫療站"
        case .evacuationRoute: return "撤離路線"
        case .worksiteBoundary: return "工址邊界"
        }
    }
    var systemImage: String {
        switch self {
        case .victimPoint: return "person.fill.viewfinder"
        case .assemblyPoint: return "flag.fill"
        case .safetyZone: return "shield.fill"
        case .restrictedZone: return "nosign"
        case .roadBlockLine: return "road.lanes"
        case .hazardPolygon: return "exclamationmark.triangle.fill"
        case .collapsedAreaPolygon: return "square.stack.3d.down.forward.fill"
        case .triageArea: return "cross.case.fill"
        case .casualtyCollectionPoint: return "cross.circle.fill"
        case .medicalStation: return "cross.fill"
        case .evacuationRoute: return "arrow.triangle.turn.up.right.diamond.fill"
        case .worksiteBoundary: return "square.dashed"
        }
    }
}

extension GeometryType {
    var consoleLabel: String {
        switch self {
        case .point: return "點"
        case .polyline: return "線"
        case .polygon: return "面"
        }
    }
}

extension AlertType {
    var consoleLabel: String {
        switch self {
        case .evacuation: return "撤離"
        case .collapseRisk: return "倒塌風險"
        case .fireOrSmoke: return "火災/濃煙"
        case .hazardousMaterial: return "危險物質"
        case .medicalSurge: return "醫療激增"
        case .missingTeam: return "失聯隊伍"
        case .communicationsFailure: return "通訊中斷"
        case .sos: return "SOS"
        case .weather: return "天氣"
        }
    }
}

extension CCCommandType {
    var consoleLabel: String {
        switch self {
        case .incidentObjective: return "事故目標"
        case .sectorAssignment: return "分區指派"
        case .worksiteAssignment: return "工址指派"
        case .evacuation: return "撤離"
        case .standDown: return "解除"
        case .safetyHold: return "安全暫停"
        case .medicalPriority: return "醫療優先"
        case .logisticsPriority: return "後勤優先"
        }
    }
}

extension EvacuationStatus {
    var consoleLabel: String {
        switch self {
        case .pending: return "待派"
        case .assigned: return "已指派"
        case .departing: return "出發中"
        case .arrived: return "已抵達"
        case .handedOff: return "已交接"
        case .cancelled: return "已取消"
        }
    }
    var consoleColor: Color {
        switch self {
        case .pending: return CCTheme.warning
        case .assigned, .departing: return CCTheme.info
        case .arrived, .handedOff: return CCTheme.accent
        case .cancelled: return CCTheme.muted
        }
    }
}

extension AuditAction {
    var consoleLabel: String {
        switch self {
        case .create: return "建立"
        case .update: return "更新"
        case .delete: return "刪除"
        case .issueCommand: return "下達命令"
        case .acknowledgeAlert: return "確認警報"
        case .assignRole: return "指派角色"
        case .login: return "登入"
        case .logout: return "登出"
        case .sendSOS: return "發送 SOS"
        case .submitReport: return "提交回報"
        case .mapUpdate: return "地圖更新"
        case .safetyControl: return "安全管制"
        case .communication: return "通訊"
        case .syncQueued: return "同步排隊"
        case .syncDelivered: return "同步送達"
        case .syncFailed: return "同步失敗"
        case .conflictDetected: return "衝突偵測"
        case .export: return "匯出"
        }
    }
    var isSyncEvent: Bool {
        self == .syncQueued || self == .syncDelivered || self == .syncFailed
    }
}

extension DisasterReportKind {
    var consoleLabel: String {
        switch self {
        case .collapse: return "倒塌"
        case .fire: return "火災"
        case .trapped: return "受困"
        case .blockedRoute: return "道路阻斷"
        case .infrastructureDamage: return "基礎設施損壞"
        case .other: return "其他"
        }
    }
}

extension USARTeamResponseType {
    var consoleLabel: String {
        switch self {
        case .light: return "輕型"
        case .medium: return "中型"
        case .heavy: return "重型"
        case .other: return "其他"
        }
    }
}

extension USARTeamClassificationStatus {
    var consoleLabel: String {
        switch self {
        case .classified: return "已分級"
        case .notClassified: return "未分級"
        case .unclassified: return "無分級"
        case .reclassificationInProgress: return "重分級中"
        }
    }
}
