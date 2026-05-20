import Foundation

public enum UCCAudience: String, Codable, CaseIterable, Sendable {
    case fireDepartment
    case emergencyOperationsCenter
    case jointResponseCenter
}

public enum UCCPhaseID: Int, Codable, CaseIterable, Identifiable, Sendable {
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

    public var id: Int { rawValue }
    public var label: String { "UCC Phase \(rawValue)" }
}

public enum UCCPhaseImplementationState: String, Codable, CaseIterable, Sendable {
    case sharedCoreBacked
    case externalIntegrationPlanned
    case strategicProductPlanned
}

public struct UCCPhase: Codable, Hashable, Identifiable, Sendable {
    public var id: UCCPhaseID
    public var moduleName: String
    public var capability: String
    public var purpose: String
    public var requiredFeatures: [LinkGuardFeature]
    public var requiredPermissions: [LinkGuardPermission]
    public var relatedMessageTypes: [SyncMessageType]
    public var primarySections: [ICSSection]
    public var implementationState: UCCPhaseImplementationState

    public init(
        id: UCCPhaseID,
        moduleName: String,
        capability: String,
        purpose: String,
        requiredFeatures: [LinkGuardFeature],
        requiredPermissions: [LinkGuardPermission],
        relatedMessageTypes: [SyncMessageType],
        primarySections: [ICSSection],
        implementationState: UCCPhaseImplementationState
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

public enum UCCPhaseCatalog {
    public static let appID: LinkGuardAppID = .ucc
    public static let positioning = "跨區域戰略指揮平台"
    public static let audiences: [UCCAudience] = [.fireDepartment, .emergencyOperationsCenter, .jointResponseCenter]

    public static let phases: [UCCPhase] = [
        UCCPhase(
            id: .phase1,
            moduleName: "全區儀表板",
            capability: "全災區監控",
            purpose: "戰情中心",
            requiredFeatures: [.globalMapOverview, .personnelOverview, .disasterStatistics],
            requiredPermissions: [.viewIncident, .manageIncident],
            relatedMessageTypes: [.incidentUpsert, .personnelStatusUpsert, .photoReportUpsert, .disasterReportUpsert, .sosReportUpsert],
            primarySections: [.command, .operations, .planning],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase2,
            moduleName: "ICS架構",
            capability: "UCC/SCC/TL管理",
            purpose: "指揮體系",
            requiredFeatures: [.commandAuthoritySwitch, .briefing],
            requiredPermissions: [.assignRole, .issueCommand, .manageIncident],
            relatedMessageTypes: [.roleAssignmentUpsert, .commandUpsert, .decisionRecordUpsert],
            primarySections: [.command, .planning],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase3,
            moduleName: "跨區調度",
            capability: "區域派遣",
            purpose: "資源協同",
            requiredFeatures: [.commandDispatch, .taskAssignment, .resourceManagement],
            requiredPermissions: [.issueCommand, .updateTask, .manageLogistics],
            relatedMessageTypes: [.commandUpsert, .taskUpsert, .purchaseRequestUpsert, .personnelHoursUpsert],
            primarySections: [.command, .operations, .logistics],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase4,
            moduleName: "AI分析",
            capability: "AI決策建議",
            purpose: "高階指揮",
            requiredFeatures: [.aiDecisionAnalysis, .aiChat, .briefing],
            requiredPermissions: [.issueCommand, .manageIncident],
            relatedMessageTypes: [.decisionRecordUpsert, .commandUpsert],
            primarySections: [.command, .planning],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase5,
            moduleName: "災情統計",
            capability: "搜救統計",
            purpose: "決策依據",
            requiredFeatures: [.disasterStatistics, .resourceManagement, .eventLog],
            requiredPermissions: [.viewIncident, .manageIncident, .exportAAR],
            relatedMessageTypes: [.taskUpsert, .photoReportUpsert, .disasterReportUpsert, .auditEventAppend],
            primarySections: [.operations, .planning, .afterActionReview],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase6,
            moduleName: "電台監聽",
            capability: "PTT轉錄",
            purpose: "通訊掌握",
            requiredFeatures: [.radioMonitoring, .speechTranscription, .communicationChannel],
            requiredPermissions: [.monitorRadio, .viewIncident],
            relatedMessageTypes: [.voiceReportAppend, .groupChatMessageAppend],
            primarySections: [.command, .operations],
            implementationState: .externalIntegrationPlanned
        ),
        UCCPhase(
            id: .phase7,
            moduleName: "事件日誌",
            capability: "AAR紀錄",
            purpose: "災後檢討",
            requiredFeatures: [.eventLog],
            requiredPermissions: [.exportAAR, .viewIncident],
            relatedMessageTypes: [.auditEventAppend, .decisionRecordUpsert],
            primarySections: [.afterActionReview, .planning],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase8,
            moduleName: "PWS整合",
            capability: "地震警報",
            purpose: "提前應變",
            requiredFeatures: [.pwsIntegration, .alertPush],
            requiredPermissions: [.issueCommand, .forceAcknowledgeAlert],
            relatedMessageTypes: [.alertUpsert, .alertAcknowledgementUpsert],
            primarySections: [.command, .operations],
            implementationState: .externalIntegrationPlanned
        ),
        UCCPhase(
            id: .phase9,
            moduleName: "EMIC整合",
            capability: "災情同步",
            purpose: "政府協同",
            requiredFeatures: [.emicIntegration, .disasterStatistics],
            requiredPermissions: [.manageIncident, .submitReport],
            relatedMessageTypes: [.incidentUpsert, .disasterReportUpsert, .auditEventAppend],
            primarySections: [.planning, .operations],
            implementationState: .externalIntegrationPlanned
        ),
        UCCPhase(
            id: .phase10,
            moduleName: "資源總控",
            capability: "人力物資管理",
            purpose: "戰略配置",
            requiredFeatures: [.resourceManagement, .teamCapabilityOverview],
            requiredPermissions: [.manageLogistics, .manageFinance],
            relatedMessageTypes: [.purchaseRequestUpsert, .personnelHoursUpsert, .personnelStatusUpsert],
            primarySections: [.logistics, .finance],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase11,
            moduleName: "安全管制",
            capability: "危險區總覽",
            purpose: "全區安全",
            requiredFeatures: [.safetyControlBoard, .hazardZoneManagement, .hazardWarning],
            requiredPermissions: [.manageMap, .issueCommand],
            relatedMessageTypes: [.safetyZoneUpsert, .safetyEntryLogUpsert, .alertUpsert],
            primarySections: [.command, .operations],
            implementationState: .sharedCoreBacked
        ),
        UCCPhase(
            id: .phase12,
            moduleName: "多指揮中心",
            capability: "備援切換",
            purpose: "容錯能力",
            requiredFeatures: [.commandCenterRedundancy, .commandAuthoritySwitch],
            requiredPermissions: [.assignRole, .provisionDevice, .issueCommand],
            relatedMessageTypes: [.roleAssignmentUpsert, .commandUpsert, .auditEventAppend],
            primarySections: [.command, .logistics, .afterActionReview],
            implementationState: .strategicProductPlanned
        ),
        UCCPhase(
            id: .phase13,
            moduleName: "國際協作",
            capability: "INSARAG模式",
            purpose: "國際接軌",
            requiredFeatures: [.internationalCoordination, .briefing, .eventLog],
            requiredPermissions: [.manageIncident, .issueCommand, .exportAAR],
            relatedMessageTypes: [.incidentUpsert, .decisionRecordUpsert, .auditEventAppend],
            primarySections: [.command, .planning, .afterActionReview],
            implementationState: .strategicProductPlanned
        )
    ]

    public static var sharedCoreBackedPhases: [UCCPhase] {
        phases.filter { $0.implementationState == .sharedCoreBacked }
    }

    public static var integrationPlannedPhases: [UCCPhase] {
        phases.filter { $0.implementationState == .externalIntegrationPlanned }
    }

    public static var strategicProductPlannedPhases: [UCCPhase] {
        phases.filter { $0.implementationState == .strategicProductPlanned }
    }

    public static func phase(id: UCCPhaseID) -> UCCPhase {
        guard let phase = phases.first(where: { $0.id == id }) else {
            preconditionFailure("Missing LinkGuard-UCC phase \(id.rawValue)")
        }
        return phase
    }

    public static func phases(for appID: LinkGuardAppID) -> [UCCPhase] {
        appID == .ucc ? phases : []
    }

    public static func isVisibleInUCC(_ phase: UCCPhase) -> Bool {
        phase.requiredFeatures.allSatisfy { LinkGuardFeatureAccessMatrix.isAvailable($0, for: .ucc) }
    }
}