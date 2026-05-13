import Foundation

public enum TeamMemberPhaseID: Int, Codable, CaseIterable, Identifiable, Sendable {
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

    public var id: Int { rawValue }
    public var label: String { "TE Phase \(rawValue)" }
}

public enum TeamMemberPhaseImplementationState: String, Codable, CaseIterable, Sendable {
    case coreBacked
    case productPlanned
    case fieldPrinciple
}

public struct TeamMemberPhase: Codable, Hashable, Identifiable, Sendable {
    public var id: TeamMemberPhaseID
    public var moduleName: String
    public var capability: String
    public var purpose: String
    public var requiredFeatures: [LinkGuardFeature]
    public var relatedMessageTypes: [SyncMessageType]
    public var operationalPrincipleIDs: [String]
    public var implementationState: TeamMemberPhaseImplementationState

    public init(
        id: TeamMemberPhaseID,
        moduleName: String,
        capability: String,
        purpose: String,
        requiredFeatures: [LinkGuardFeature],
        relatedMessageTypes: [SyncMessageType],
        operationalPrincipleIDs: [String],
        implementationState: TeamMemberPhaseImplementationState
    ) {
        self.id = id
        self.moduleName = moduleName
        self.capability = capability
        self.purpose = purpose
        self.requiredFeatures = requiredFeatures
        self.relatedMessageTypes = relatedMessageTypes
        self.operationalPrincipleIDs = operationalPrincipleIDs
        self.implementationState = implementationState
    }

    public var label: String { id.label }
}

public enum TeamMemberPhaseCatalog {
    public static let phases: [TeamMemberPhase] = [
        TeamMemberPhase(
            id: .phase1,
            moduleName: "任務接收",
            capability: "接收搜索任務",
            purpose: "任務執行",
            requiredFeatures: [.taskReport],
            relatedMessageTypes: [.taskUpsert],
            operationalPrincipleIDs: ["short-command-flow"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase2,
            moduleName: "GPS定位",
            capability: "即時位置同步",
            purpose: "隊伍掌握",
            requiredFeatures: [.gpsTracking, .personnelStatusUpdate],
            relatedMessageTypes: [.personnelStatusUpsert],
            operationalPrincipleIDs: ["connection-continuity"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase3,
            moduleName: "SOS功能",
            capability: "緊急求救",
            purpose: "人員安全",
            requiredFeatures: [.sosSending],
            relatedMessageTypes: [.sosReportUpsert],
            operationalPrincipleIDs: ["three-second-action", "low-false-touch"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase4,
            moduleName: "照片回報",
            capability: "搜救照片上傳",
            purpose: "現場資訊",
            requiredFeatures: [.photoReport],
            relatedMessageTypes: [.photoReportUpsert],
            operationalPrincipleIDs: ["three-second-action"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase5,
            moduleName: "危險標記",
            capability: "危險點回報",
            purpose: "安全警示",
            requiredFeatures: [.pointMarker],
            relatedMessageTypes: [.mapFeatureUpsert],
            operationalPrincipleIDs: ["low-false-touch", "short-command-flow"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase6,
            moduleName: "分區資訊",
            capability: "搜索區域查看",
            purpose: "搜救定位",
            requiredFeatures: [.offlineMap, .worksiteMarkerSystem],
            relatedMessageTypes: [.sectorUpsert, .subSectorUpsert, .worksiteUpsert],
            operationalPrincipleIDs: ["offline-capable", "night-contrast"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase7,
            moduleName: "任務回報",
            capability: "完成/中止回報",
            purpose: "指揮同步",
            requiredFeatures: [.taskReport],
            relatedMessageTypes: [.taskUpsert],
            operationalPrincipleIDs: ["three-second-action", "short-command-flow"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase8,
            moduleName: "離線模式",
            capability: "離線資料同步",
            purpose: "災後穩定",
            requiredFeatures: [],
            relatedMessageTypes: SyncMessageType.allCases,
            operationalPrincipleIDs: ["connection-continuity", "offline-capable", "crash-resistance"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase9,
            moduleName: "語音回報",
            capability: "語音紀錄",
            purpose: "高壓操作",
            requiredFeatures: [.voiceReport, .speechTranscription],
            relatedMessageTypes: [.voiceReportAppend],
            operationalPrincipleIDs: ["three-second-action", "one-hand"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase10,
            moduleName: "安全管制",
            capability: "進出紀錄",
            purpose: "人員管理",
            requiredFeatures: [.personnelEntryLog, .personnelStatusUpdate],
            relatedMessageTypes: [.safetyEntryLogUpsert, .personnelStatusUpsert],
            operationalPrincipleIDs: ["low-false-touch", "short-command-flow"],
            implementationState: .coreBacked
        ),
        TeamMemberPhase(
            id: .phase11,
            moduleName: "LoRa整合",
            capability: "災區通訊",
            purpose: "斷網運作",
            requiredFeatures: [.communicationChannel, .alertPush, .sosSending],
            relatedMessageTypes: [.groupChatMessageAppend, .alertUpsert, .sosReportUpsert],
            operationalPrincipleIDs: ["connection-continuity", "offline-capable"],
            implementationState: .productPlanned
        ),
        TeamMemberPhase(
            id: .phase12,
            moduleName: "高壓模式",
            capability: "手套操作、大按鈕",
            purpose: "高可靠性",
            requiredFeatures: [.sosSending, .taskReport, .photoReport, .voiceReport],
            relatedMessageTypes: [.sosReportUpsert, .taskUpsert, .photoReportUpsert, .voiceReportAppend],
            operationalPrincipleIDs: ["glove-safe", "large-buttons", "night-contrast", "one-hand"],
            implementationState: .fieldPrinciple
        )
    ]

    public static var coreBackedPhases: [TeamMemberPhase] {
        phases.filter { $0.implementationState == .coreBacked }
    }

    public static var plannedPhases: [TeamMemberPhase] {
        phases.filter { $0.implementationState == .productPlanned }
    }

    public static var fieldPrinciplePhases: [TeamMemberPhase] {
        phases.filter { $0.implementationState == .fieldPrinciple }
    }

    public static func phase(id: TeamMemberPhaseID) -> TeamMemberPhase {
        guard let phase = phases.first(where: { $0.id == id }) else {
            preconditionFailure("Missing LinkGuard-TE phase \(id.rawValue)")
        }
        return phase
    }

    public static func phases(for appID: LinkGuardAppID) -> [TeamMemberPhase] {
        appID == .teamMember ? phases : []
    }

    public static func isExecutableByTeamMember(_ phase: TeamMemberPhase) -> Bool {
        guard phase.implementationState == .coreBacked else { return false }
        return phase.requiredFeatures.allSatisfy { LinkGuardFeatureAccessMatrix.isAvailable($0, for: .teamMember) }
    }
}