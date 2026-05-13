import Foundation

public enum EMTMedicalPhaseID: Int, Codable, CaseIterable, Identifiable, Sendable {
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
    public var label: String { "EMT Phase \(rawValue)" }
}

public enum EMTMedicalPhaseImplementationState: String, Codable, CaseIterable, Sendable {
    case coreBacked
    case productPlanned
    case deviceIntegration
}

public struct EMTMedicalPhase: Codable, Hashable, Identifiable, Sendable {
    public var id: EMTMedicalPhaseID
    public var moduleName: String
    public var capability: String
    public var purpose: String
    public var requiredFeatures: [LinkGuardFeature]
    public var relatedMessageTypes: [SyncMessageType]
    public var operationalPrincipleIDs: [String]
    public var implementationState: EMTMedicalPhaseImplementationState

    public init(
        id: EMTMedicalPhaseID,
        moduleName: String,
        capability: String,
        purpose: String,
        requiredFeatures: [LinkGuardFeature],
        relatedMessageTypes: [SyncMessageType],
        operationalPrincipleIDs: [String],
        implementationState: EMTMedicalPhaseImplementationState
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

public enum LinkGuardEMTMedicalVersion {
    public static let appName = "LinkGuard-EMT"
    public static let editionName = "醫療版本"
    public static let targetUsers = ["EMT", "醫療後送人員", "醫療支援組"]
    public static let corePositioning = "醫療後送與傷患管理系統"
    public static var phases: [EMTMedicalPhase] { EMTMedicalPhaseCatalog.phases }
}

public enum EMTMedicalPhaseCatalog {
    public static let phases: [EMTMedicalPhase] = [
        EMTMedicalPhase(
            id: .phase1,
            moduleName: "傷患建立",
            capability: "傷患資料",
            purpose: "傷患管理",
            requiredFeatures: [.patientCreation],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["three-second-action", "short-command-flow"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase2,
            moduleName: "START檢傷",
            capability: "紅黃綠黑分類",
            purpose: "醫療排序",
            requiredFeatures: [.startTriage],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["low-false-touch", "night-contrast"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase3,
            moduleName: "生理監測",
            capability: "心率血氧",
            purpose: "傷患監控",
            requiredFeatures: [.patientStatusUpdate],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["three-second-action"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase4,
            moduleName: "傷患狀態更新",
            capability: "病況更新",
            purpose: "醫療同步",
            requiredFeatures: [.patientStatusUpdate, .patientHistory],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["connection-continuity", "short-command-flow"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase5,
            moduleName: "後送管理",
            capability: "醫院派送",
            purpose: "醫療調度",
            requiredFeatures: [.medicalEvacuation],
            relatedMessageTypes: [.evacuationRequestUpsert],
            operationalPrincipleIDs: ["connection-continuity"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase6,
            moduleName: "醫療照片",
            capability: "傷勢照片",
            purpose: "醫療紀錄",
            requiredFeatures: [.patientPhoto, .photoReport],
            relatedMessageTypes: [.photoReportUpsert],
            operationalPrincipleIDs: ["three-second-action"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase7,
            moduleName: "醫療語音紀錄",
            capability: "語音輸入",
            purpose: "高壓輸入",
            requiredFeatures: [.voiceReport, .speechTranscription],
            relatedMessageTypes: [.voiceReportAppend],
            operationalPrincipleIDs: ["one-hand", "short-command-flow"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase8,
            moduleName: "離線模式",
            capability: "離線病歷",
            purpose: "災後運作",
            requiredFeatures: [.patientHistory],
            relatedMessageTypes: [.patientUpsert, .evacuationRequestUpsert, .photoReportUpsert, .voiceReportAppend],
            operationalPrincipleIDs: ["connection-continuity", "offline-capable", "crash-resistance"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase9,
            moduleName: "多語翻譯",
            capability: "外籍患者",
            purpose: "國際災援",
            requiredFeatures: [.realtimeTranslation, .voiceTranslation],
            relatedMessageTypes: [.groupChatMessageAppend, .voiceReportAppend],
            operationalPrincipleIDs: ["short-command-flow"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase10,
            moduleName: "醫療AI預警",
            capability: "惡化預測",
            purpose: "緊急優先",
            requiredFeatures: [.aiPatientWarning],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["low-false-touch"],
            implementationState: .productPlanned
        ),
        EMTMedicalPhase(
            id: .phase11,
            moduleName: "醫院資訊",
            capability: "可收治醫院",
            purpose: "後送決策",
            requiredFeatures: [.hospitalCapacityView],
            relatedMessageTypes: [.hospitalCapacityUpsert],
            operationalPrincipleIDs: ["short-command-flow"],
            implementationState: .coreBacked
        ),
        EMTMedicalPhase(
            id: .phase12,
            moduleName: "手錶整合",
            capability: "Apple Watch等",
            purpose: "生理感測",
            requiredFeatures: [.patientStatusUpdate],
            relatedMessageTypes: [.patientUpsert],
            operationalPrincipleIDs: ["connection-continuity"],
            implementationState: .deviceIntegration
        )
    ]

    public static var coreBackedPhases: [EMTMedicalPhase] {
        phases.filter { $0.implementationState == .coreBacked }
    }

    public static var plannedPhases: [EMTMedicalPhase] {
        phases.filter { $0.implementationState == .productPlanned }
    }

    public static var deviceIntegrationPhases: [EMTMedicalPhase] {
        phases.filter { $0.implementationState == .deviceIntegration }
    }

    public static func phase(id: EMTMedicalPhaseID) -> EMTMedicalPhase {
        guard let phase = phases.first(where: { $0.id == id }) else {
            preconditionFailure("Missing LinkGuard-EMT phase \(id.rawValue)")
        }
        return phase
    }

    public static func phases(for appID: LinkGuardAppID) -> [EMTMedicalPhase] {
        switch appID {
        case .emt, .emtIPad:
            return phases
        case .ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad, .teamMember, .volunteer:
            return []
        }
    }

    public static func isExecutableByEMT(_ phase: EMTMedicalPhase) -> Bool {
        guard phase.implementationState == .coreBacked else { return false }
        return phase.requiredFeatures.allSatisfy { LinkGuardFeatureAccessMatrix.isAvailable($0, for: .emt) }
    }
}