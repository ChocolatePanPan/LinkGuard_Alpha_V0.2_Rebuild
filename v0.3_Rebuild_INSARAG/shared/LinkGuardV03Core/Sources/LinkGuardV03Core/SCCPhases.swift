import Foundation

public enum SCCPhaseID: Int, Codable, CaseIterable, Identifiable, Sendable {
    case phase1 = 1
    case phase2 = 2
    case phase3 = 3
    case phase4 = 4
    case phase5 = 5
    case phase6 = 6
    case phase7 = 7
    case phase8 = 8
    case phase9 = 9
    case phase10 = 10
    case phase11 = 11
    case phase12 = 12
    case phase13 = 13
    case phase14 = 14
    case phase15 = 15
    case phase16 = 16
    case phase17 = 17
    case phase18 = 18
    case phase19 = 19
    case phase20 = 20
    case phase21 = 21
    case phase22 = 22
    case phase23 = 23
    case phase24 = 24
    case phase25 = 25

    public var id: Int { rawValue }
    public var label: String { "SCC Phase \(rawValue)" }
}

public enum SCCPhaseImplementationState: String, Codable, CaseIterable, Sendable {
    case coreBacked
    case externalIntegrationPlanned
    case productPlanned
}

public struct SCCPhase: Codable, Hashable, Identifiable, Sendable {
    public var id: SCCPhaseID
    public var moduleName: String
    public var capability: String
    public var purpose: String
    public var requiredFeatures: [LinkGuardFeature]
    public var requiredPermissions: [LinkGuardPermission]
    public var relatedMessageTypes: [SyncMessageType]
    public var primarySections: [ICSSection]
    public var implementationState: SCCPhaseImplementationState

    public init(
        id: SCCPhaseID,
        moduleName: String,
        capability: String,
        purpose: String,
        requiredFeatures: [LinkGuardFeature],
        requiredPermissions: [LinkGuardPermission],
        relatedMessageTypes: [SyncMessageType],
        primarySections: [ICSSection],
        implementationState: SCCPhaseImplementationState
    ) {
        self.id = id
        self.moduleName = moduleName
        self.capability = capability
        self.purpose = purpose
        self.requiredFeatures = requiredFeatures
        self.requiredPermissions = requiredPermissions
        self.relatedMessageTypes = relatedMessageTypes
        self.primarySections = primarySections
        self.implementationState = implementationState
    }

    public var label: String { id.label }
}

public enum LinkGuardSCCVersion {
    public static let appID: LinkGuardAppID = .scc
    public static let appName = "LinkGuard-SCC"
    public static let editionName = "現場指揮中心版本"
    public static let targetUsers = ["現場指揮官", "特搜隊現場總指揮", "分區統籌官", "災區前進指揮所"]
    public static let corePositioning = "災區現場戰術指揮中心"
    public static var phases: [SCCPhase] { SCCPhaseCatalog.phases }
}

public enum SCCPhaseCatalog {
    public static let phases: [SCCPhase] = [
        SCCPhase(
            id: .phase1,
            moduleName: "現場戰情儀表板",
            capability: "災區即時總覽",
            purpose: "建立現場戰情中心",
            requiredFeatures: [
                .globalMapOverview,           // GPS 定位
                .personnelOverview,           // 人員總覽
                .disasterStatistics,          // 統計資訊
                .sectorCreation,              // 分區管理
                .pointMarker,                 // 點標記
                .lineMarker,                  // 線標記
                .areaMarker,                  // 面標記
                .searchProgressColoring,      // 搜救狀態
                .hazardZoneManagement,        // 危險區
                .gpsTracking,                 // 人員追蹤
                .patientLocation,             // 傷患定位
                .sosSending,                  // SOS 定位
                .photoReport,                 // 照片整合
                .offlineMap                   // 離線地圖
            ],
            requiredPermissions: [.viewIncident, .manageIncident, .manageMap],
            relatedMessageTypes: [
                .incidentUpsert,
                .personnelStatusUpsert,
                .photoReportUpsert,
                .sosReportUpsert,
                .sectorUpsert,
                .taskUpsert
            ],
            primarySections: [.command, .operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase2,
            moduleName: "分區管理",
            capability: "建立A/B/C主區",
            purpose: "災區切割管理",
            requiredFeatures: [.sectorCreation, .globalMapOverview],
            requiredPermissions: [.manageMap, .manageIncident],
            relatedMessageTypes: [.sectorUpsert],
            primarySections: [.operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase3,
            moduleName: "子區域管理",
            capability: "建立D1/D2等副區",
            purpose: "大型倒塌管理",
            requiredFeatures: [.subSectorCreation, .worksiteMarkerSystem],
            requiredPermissions: [.manageMap, .manageIncident],
            relatedMessageTypes: [.subSectorUpsert, .worksiteUpsert],
            primarySections: [.operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase4,
            moduleName: "地圖點線面",
            capability: "點線面標記",
            purpose: "視覺化災區",
            requiredFeatures: [.pointMarker, .lineMarker, .areaMarker],
            requiredPermissions: [.manageMap],
            relatedMessageTypes: [.mapFeatureUpsert],
            primarySections: [.operations],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase5,
            moduleName: "嚴重度分色",
            capability: "紅黃綠黑區域",
            purpose: "危險程度判讀",
            requiredFeatures: [.searchProgressColoring, .hazardZoneManagement],
            requiredPermissions: [.manageMap, .issueCommand],
            relatedMessageTypes: [.mapFeatureUpsert, .safetyZoneUpsert],
            primarySections: [.operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase6,
            moduleName: "搜救狀態管理",
            capability: "搜救中／已淨空／危險區",
            purpose: "區域管理",
            requiredFeatures: [.searchProgressColoring, .worksiteMarkerSystem, .taskAssignment],
            requiredPermissions: [.manageMap, .updateTask],
            relatedMessageTypes: [.worksiteUpsert, .taskUpsert, .safetyZoneUpsert],
            primarySections: [.operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase7,
            moduleName: "人員配置",
            capability: "搜救隊分派",
            purpose: "現場調度",
            requiredFeatures: [.personnelOverview, .taskAssignment, .gpsTracking],
            requiredPermissions: [.issueCommand, .updateTask],
            relatedMessageTypes: [.personnelStatusUpsert, .taskUpsert, .roleAssignmentUpsert],
            primarySections: [.command, .operations, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase8,
            moduleName: "任務派遣",
            capability: "指派搜索任務",
            purpose: "戰術指揮",
            requiredFeatures: [.taskAssignment, .commandDispatch, .quickCommand, .ceocMissionDispatch],
            requiredPermissions: [.issueCommand, .updateTask],
            relatedMessageTypes: [.taskUpsert, .commandUpsert, .ceocMissionUpsert],
            primarySections: [.command, .operations],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase9,
            moduleName: "隊伍能力表",
            capability: "隊伍專長與能力",
            purpose: "最佳化派遣",
            requiredFeatures: [.teamCapabilityOverview, .personnelOverview],
            requiredPermissions: [.manageLogistics, .issueCommand],
            relatedMessageTypes: [.personnelStatusUpsert, .personnelHoursUpsert],
            primarySections: [.operations, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase10,
            moduleName: "SOS統整",
            capability: "SOS優先排序",
            purpose: "緊急應變",
            requiredFeatures: [.sosDetail, .alertPush, .disasterStatistics],
            requiredPermissions: [.viewIncident, .forceAcknowledgeAlert],
            relatedMessageTypes: [.sosReportUpsert, .alertUpsert],
            primarySections: [.command, .operations],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase11,
            moduleName: "傷患統整",
            capability: "傷患總覽",
            purpose: "醫療協調",
            requiredFeatures: [.patientLocation, .hospitalCapacityView, .medicalOperationalSummary],
            requiredPermissions: [.viewMedicalSummary, .manageEvacuation],
            relatedMessageTypes: [.patientOperationalSummaryUpsert, .evacuationRequestUpsert, .hospitalCapacityUpsert],
            primarySections: [.operations, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase12,
            moduleName: "START統計",
            capability: "檢傷分類統計",
            purpose: "MCI管理",
            requiredFeatures: [.startTriage, .disasterStatistics, .medicalOperationalSummary],
            requiredPermissions: [.viewMedicalSummary, .managePatientReport],
            relatedMessageTypes: [.patientOperationalSummaryUpsert],
            primarySections: [.operations, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase13,
            moduleName: "臨時據點",
            capability: "指揮所/集結點建立",
            purpose: "現場部署",
            requiredFeatures: [.pointMarker, .areaMarker, .briefing],
            requiredPermissions: [.manageMap, .issueCommand],
            relatedMessageTypes: [.mapFeatureUpsert, .decisionRecordUpsert],
            primarySections: [.command, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase14,
            moduleName: "安全管制",
            capability: "危險區封鎖",
            purpose: "搜救安全",
            requiredFeatures: [.safetyControlBoard, .hazardZoneManagement, .hazardWarning],
            requiredPermissions: [.manageMap, .issueCommand],
            relatedMessageTypes: [.safetyZoneUpsert, .alertUpsert],
            primarySections: [.command, .operations],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase15,
            moduleName: "人員進出管理",
            capability: "進出災區紀錄",
            purpose: "人員安全",
            requiredFeatures: [.personnelEntryLog, .personnelOverview],
            requiredPermissions: [.viewIncident, .updateTask],
            relatedMessageTypes: [.safetyEntryLogUpsert, .personnelStatusUpsert],
            primarySections: [.operations, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase16,
            moduleName: "會報系統",
            capability: "現場會報",
            purpose: "指揮同步",
            requiredFeatures: [.briefing, .eventLog],
            requiredPermissions: [.issueCommand, .manageIncident],
            relatedMessageTypes: [.decisionRecordUpsert, .auditEventAppend],
            primarySections: [.command, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase17,
            moduleName: "電台監聽",
            capability: "PTT轉錄",
            purpose: "通訊管理",
            requiredFeatures: [.radioMonitoring, .speechTranscription, .communicationChannel],
            requiredPermissions: [.monitorRadio, .viewIncident],
            relatedMessageTypes: [.voiceReportAppend, .groupChatMessageAppend],
            primarySections: [.command, .operations],
            implementationState: .externalIntegrationPlanned
        ),
        SCCPhase(
            id: .phase18,
            moduleName: "多隊伍協調",
            capability: "跨隊任務整合",
            purpose: "大型災害協同",
            requiredFeatures: [.commandDispatch, .briefing, .resourceManagement],
            requiredPermissions: [.issueCommand, .assignRole, .manageLogistics],
            relatedMessageTypes: [.commandUpsert, .taskUpsert, .roleAssignmentUpsert, .decisionRecordUpsert],
            primarySections: [.command, .operations, .logistics],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase19,
            moduleName: "AI決策輔助",
            capability: "AI派遣建議",
            purpose: "降低指揮負荷",
            requiredFeatures: [.aiDecisionAnalysis, .aiChat, .commandDispatch],
            requiredPermissions: [.issueCommand, .manageIncident],
            relatedMessageTypes: [.decisionRecordUpsert, .commandUpsert],
            primarySections: [.command, .planning],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase20,
            moduleName: "AI風險分析",
            capability: "結構風險預警",
            purpose: "搜救安全",
            requiredFeatures: [.aiPatientWarning, .hazardZoneManagement, .hazardWarning],
            requiredPermissions: [.manageMap, .issueCommand],
            relatedMessageTypes: [.safetyZoneUpsert, .alertUpsert],
            primarySections: [.operations, .planning],
            implementationState: .productPlanned
        ),
        SCCPhase(
            id: .phase21,
            moduleName: "離線指揮",
            capability: "離線地圖與資料",
            purpose: "通訊中斷備援",
            requiredFeatures: [.offlineMap, .offlineDraftQueue, .communicationChannel],
            requiredPermissions: [.manageIncident, .issueCommand, .submitReport],
            relatedMessageTypes: [.incidentUpsert, .commandUpsert, .taskUpsert, .alertUpsert],
            primarySections: [.command, .operations],
            implementationState: .coreBacked
        ),
        SCCPhase(
            id: .phase22,
            moduleName: "LoRa中繼",
            capability: "災區自主通訊",
            purpose: "基地台失效備援",
            requiredFeatures: [.communicationChannel, .alertPush, .sosSending],
            requiredPermissions: [.issueCommand, .sendSOS],
            relatedMessageTypes: [.groupChatMessageAppend, .alertUpsert, .sosReportUpsert],
            primarySections: [.command, .operations],
            implementationState: .externalIntegrationPlanned
        ),
        SCCPhase(
            id: .phase23,
            moduleName: "多裝置同步",
            capability: "iPad/Mac同步",
            purpose: "現場協同",
            requiredFeatures: [.commandCenterRedundancy, .offlineDraftQueue, .personnelOverview],
            requiredPermissions: [.provisionDevice, .manageIncident],
            relatedMessageTypes: [.roleAssignmentUpsert, .personnelStatusUpsert, .auditEventAppend],
            primarySections: [.command, .logistics],
            implementationState: .productPlanned
        ),
        SCCPhase(
            id: .phase24,
            moduleName: "UCC同步",
            capability: "與中央戰情同步",
            purpose: "上下層協同",
            requiredFeatures: [.commandAuthoritySwitch, .briefing, .eventLog],
            requiredPermissions: [.assignRole, .manageIncident, .issueCommand],
            relatedMessageTypes: [.incidentUpsert, .commandUpsert, .decisionRecordUpsert, .auditEventAppend],
            primarySections: [.command, .planning, .afterActionReview],
            implementationState: .productPlanned
        ),
        SCCPhase(
            id: .phase25,
            moduleName: "AAR紀錄",
            capability: "災後回放分析",
            purpose: "檢討與訓練",
            requiredFeatures: [.eventLog, .briefing],
            requiredPermissions: [.exportAAR, .viewIncident],
            relatedMessageTypes: [.auditEventAppend, .decisionRecordUpsert],
            primarySections: [.planning, .afterActionReview],
            implementationState: .coreBacked
        )
    ]

    public static var coreBackedPhases: [SCCPhase] {
        phases.filter { $0.implementationState == .coreBacked }
    }

    public static var integrationPlannedPhases: [SCCPhase] {
        phases.filter { $0.implementationState == .externalIntegrationPlanned }
    }

    public static var productPlannedPhases: [SCCPhase] {
        phases.filter { $0.implementationState == .productPlanned }
    }

    public static func phase(id: SCCPhaseID) -> SCCPhase {
        guard let phase = phases.first(where: { $0.id == id }) else {
            preconditionFailure("Missing LinkGuard-SCC phase \(id.rawValue)")
        }
        return phase
    }

    public static func phases(for appID: LinkGuardAppID) -> [SCCPhase] {
        switch appID {
        case .scc, .sccIPad:
            return phases
        case .ucc, .teamLeader, .teamLeaderIPad, .teamMember, .emt, .emtIPad, .volunteer:
            return []
        }
    }

    public static func isVisibleInSCC(_ phase: SCCPhase) -> Bool {
        phase.requiredFeatures.allSatisfy { LinkGuardFeatureAccessMatrix.isAvailable($0, for: .scc) }
    }
}