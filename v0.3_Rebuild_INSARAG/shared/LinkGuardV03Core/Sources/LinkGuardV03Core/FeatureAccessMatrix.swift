import Foundation

public enum FeatureAccessLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case limited = 1
    case primary = 2

    public static func < (lhs: FeatureAccessLevel, rhs: FeatureAccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isAvailable: Bool {
        self != .none
    }
}

public enum LinkGuardFeature: String, Codable, CaseIterable, Sendable {
    case accountIdentity
    case disasterReport
    case offlineDraftQueue
    case hazardWarning
    case simplifiedMode

    case globalMapOverview
    case sectorCreation
    case subSectorCreation
    case pointMarker
    case lineMarker
    case areaMarker
    case hazardZoneManagement
    case searchProgressColoring
    case worksiteMarkerSystem
    case offlineMap

    case personnelOverview
    case gpsTracking
    case personnelEntryLog
    case teamCapabilityOverview
    case personnelStatusUpdate
    case safetyControlBoard
    case taskAssignment
    case taskReport

    case patientCreation
    case startTriage
    case patientLocation
    case patientPhoto
    case patientStatusUpdate
    case medicalEvacuation
    case hospitalCapacityView
    case patientHistory

    case communicationChannel
    case radioMonitoring
    case speechTranscription
    case voiceReport
    case realtimeTranslation
    case voiceTranslation
    case photoReport
    case multiPointPhotoReport
    case alertPush
    case alertRead
    case sosSending
    case sosDetail

    case aiDecisionAnalysis
    case aiPatientWarning
    case aiChat
    case quickCommand
    case briefing
    case commandDispatch
    case commandAuthoritySwitch
    case eventLog
    case disasterStatistics
    case resourceManagement
    case pwsIntegration
    case emicIntegration
    case commandCenterRedundancy
    case internationalCoordination
}

public enum LinkGuardFeatureAccessMatrix {
    public static func accessLevel(for appID: LinkGuardAppID, feature: LinkGuardFeature) -> FeatureAccessLevel {
        matrix[feature]?.level(for: canonicalAppID(for: appID)) ?? .none
    }

    public static func isAvailable(_ feature: LinkGuardFeature, for appID: LinkGuardAppID) -> Bool {
        accessLevel(for: appID, feature: feature).isAvailable
    }

    public static func features(for appID: LinkGuardAppID, minimumAccess: FeatureAccessLevel = .limited) -> [LinkGuardFeature] {
        LinkGuardFeature.allCases.filter { accessLevel(for: appID, feature: $0) >= minimumAccess }
    }

    private static func canonicalAppID(for appID: LinkGuardAppID) -> LinkGuardAppID {
        switch appID {
        case .sccIPad:
            return .scc
        case .teamLeaderIPad:
            return .teamLeader
        case .emtIPad:
            return .emt
        case .ucc, .scc, .teamLeader, .teamMember, .emt, .volunteer:
            return appID
        }
    }

    private static let matrix: [LinkGuardFeature: RoleFeatureAccess] = [
        .accountIdentity: .init(.primary, .primary, .primary, .primary, .primary, .primary),
        .disasterReport: .init(.limited, .primary, .primary, .primary, .limited, .primary),
        .offlineDraftQueue: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .hazardWarning: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .simplifiedMode: .init(.none, .none, .limited, .primary, .limited, .primary),

        .globalMapOverview: .init(.primary, .primary, .limited, .none, .limited, .none),
        .sectorCreation: .init(.limited, .primary, .primary, .none, .none, .none),
        .subSectorCreation: .init(.none, .limited, .primary, .none, .none, .none),
        .pointMarker: .init(.limited, .primary, .primary, .primary, .primary, .limited),
        .lineMarker: .init(.limited, .primary, .primary, .limited, .none, .none),
        .areaMarker: .init(.limited, .primary, .primary, .none, .none, .none),
        .hazardZoneManagement: .init(.limited, .primary, .primary, .none, .none, .none),
        .searchProgressColoring: .init(.limited, .primary, .primary, .none, .none, .none),
        .worksiteMarkerSystem: .init(.limited, .primary, .primary, .limited, .limited, .none),
        .offlineMap: .init(.limited, .primary, .primary, .primary, .limited, .limited),

        .personnelOverview: .init(.primary, .primary, .primary, .none, .limited, .none),
        .gpsTracking: .init(.primary, .primary, .primary, .primary, .primary, .primary),
        .personnelEntryLog: .init(.limited, .primary, .primary, .limited, .limited, .none),
        .teamCapabilityOverview: .init(.primary, .primary, .primary, .none, .limited, .none),
        .personnelStatusUpdate: .init(.limited, .primary, .primary, .limited, .limited, .none),
        .safetyControlBoard: .init(.limited, .primary, .primary, .none, .none, .none),
        .taskAssignment: .init(.limited, .primary, .primary, .none, .none, .none),
        .taskReport: .init(.limited, .primary, .primary, .primary, .limited, .limited),

        .patientCreation: .init(.none, .limited, .primary, .limited, .primary, .none),
        .startTriage: .init(.none, .limited, .primary, .none, .primary, .none),
        .patientLocation: .init(.limited, .primary, .primary, .limited, .primary, .none),
        .patientPhoto: .init(.none, .limited, .primary, .limited, .primary, .none),
        .patientStatusUpdate: .init(.none, .limited, .primary, .none, .primary, .none),
        .medicalEvacuation: .init(.none, .limited, .none, .none, .primary, .none),
        .hospitalCapacityView: .init(.limited, .primary, .none, .none, .primary, .none),
        .patientHistory: .init(.none, .limited, .primary, .none, .primary, .none),

        .communicationChannel: .init(.primary, .primary, .primary, .primary, .primary, .limited),
        .radioMonitoring: .init(.primary, .primary, .limited, .none, .none, .none),
        .speechTranscription: .init(.limited, .primary, .primary, .limited, .limited, .none),
        .voiceReport: .init(.limited, .primary, .primary, .primary, .limited, .primary),
        .realtimeTranslation: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .voiceTranslation: .init(.none, .limited, .primary, .primary, .primary, .none),
        .photoReport: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .multiPointPhotoReport: .init(.limited, .primary, .primary, .limited, .limited, .none),
        .alertPush: .init(.primary, .primary, .primary, .primary, .primary, .limited),
        .alertRead: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .sosSending: .init(.limited, .primary, .primary, .primary, .primary, .primary),
        .sosDetail: .init(.limited, .primary, .primary, .limited, .primary, .none),

        .aiDecisionAnalysis: .init(.primary, .primary, .limited, .none, .none, .none),
        .aiPatientWarning: .init(.limited, .primary, .limited, .none, .primary, .none),
        .aiChat: .init(.primary, .primary, .limited, .none, .none, .none),
        .quickCommand: .init(.limited, .primary, .primary, .none, .none, .none),
        .briefing: .init(.limited, .primary, .primary, .none, .none, .none),
        .commandDispatch: .init(.primary, .primary, .limited, .none, .none, .none),
        .commandAuthoritySwitch: .init(.primary, .primary, .none, .none, .none, .none),
        .eventLog: .init(.primary, .primary, .limited, .none, .limited, .none),
        .disasterStatistics: .init(.primary, .primary, .limited, .none, .limited, .none),
        .resourceManagement: .init(.primary, .primary, .limited, .none, .limited, .none),
        .pwsIntegration: .init(.primary, .primary, .limited, .none, .none, .none),
        .emicIntegration: .init(.primary, .limited, .none, .none, .none, .none),
        .commandCenterRedundancy: .init(.primary, .primary, .none, .none, .none, .none),
        .internationalCoordination: .init(.primary, .limited, .none, .none, .none, .none)
    ]
}

private struct RoleFeatureAccess: Sendable {
    var ucc: FeatureAccessLevel
    var scc: FeatureAccessLevel
    var teamLeader: FeatureAccessLevel
    var teamMember: FeatureAccessLevel
    var emt: FeatureAccessLevel
    var volunteer: FeatureAccessLevel

    init(
        _ ucc: FeatureAccessLevel,
        _ scc: FeatureAccessLevel,
        _ teamLeader: FeatureAccessLevel,
        _ teamMember: FeatureAccessLevel,
        _ emt: FeatureAccessLevel,
        _ volunteer: FeatureAccessLevel
    ) {
        self.ucc = ucc
        self.scc = scc
        self.teamLeader = teamLeader
        self.teamMember = teamMember
        self.emt = emt
        self.volunteer = volunteer
    }

    func level(for appID: LinkGuardAppID) -> FeatureAccessLevel {
        switch appID {
        case .ucc:
            return ucc
        case .scc:
            return scc
        case .teamLeader:
            return teamLeader
        case .teamMember:
            return teamMember
        case .emt:
            return emt
        case .volunteer:
            return volunteer
        case .sccIPad, .teamLeaderIPad, .emtIPad:
            preconditionFailure("Use canonical app IDs for role feature access")
        }
    }
}