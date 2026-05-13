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
    case globalIncidentOverview
    case sectorCreation
    case subSectorCreation
    case commandDispatch
    case taskAssignment
    case sosHandling
    case gpsTracking
    case photoReport
    case patientUpload
    case startTriage
    case evacuationManagement
    case patientStatusUpdate
    case aiDecisionAnalysis
    case offlineCache
    case safetyControl
    case eventLog
    case briefing
    case radioMonitoring
}

public enum LinkGuardFeatureAccessMatrix {
    public static func accessLevel(for appID: LinkGuardAppID, feature: LinkGuardFeature) -> FeatureAccessLevel {
        matrix[canonicalAppID(for: appID)]?[feature] ?? .none
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

    private static let matrix: [LinkGuardAppID: [LinkGuardFeature: FeatureAccessLevel]] = [
        .ucc: [
            .globalIncidentOverview: .primary,
            .sectorCreation: .limited,
            .subSectorCreation: .none,
            .commandDispatch: .primary,
            .taskAssignment: .limited,
            .sosHandling: .limited,
            .gpsTracking: .primary,
            .photoReport: .limited,
            .patientUpload: .none,
            .startTriage: .none,
            .evacuationManagement: .none,
            .patientStatusUpdate: .none,
            .aiDecisionAnalysis: .primary,
            .offlineCache: .primary,
            .safetyControl: .limited,
            .eventLog: .primary,
            .briefing: .limited,
            .radioMonitoring: .primary
        ],
        .scc: [
            .globalIncidentOverview: .primary,
            .sectorCreation: .primary,
            .subSectorCreation: .limited,
            .commandDispatch: .primary,
            .taskAssignment: .primary,
            .sosHandling: .primary,
            .gpsTracking: .primary,
            .photoReport: .primary,
            .patientUpload: .limited,
            .startTriage: .limited,
            .evacuationManagement: .limited,
            .patientStatusUpdate: .limited,
            .aiDecisionAnalysis: .primary,
            .offlineCache: .primary,
            .safetyControl: .primary,
            .eventLog: .primary,
            .briefing: .primary,
            .radioMonitoring: .primary
        ],
        .teamLeader: [
            .globalIncidentOverview: .limited,
            .sectorCreation: .primary,
            .subSectorCreation: .primary,
            .commandDispatch: .limited,
            .taskAssignment: .primary,
            .sosHandling: .primary,
            .gpsTracking: .primary,
            .photoReport: .primary,
            .patientUpload: .primary,
            .startTriage: .primary,
            .evacuationManagement: .none,
            .patientStatusUpdate: .primary,
            .aiDecisionAnalysis: .limited,
            .offlineCache: .primary,
            .safetyControl: .primary,
            .eventLog: .limited,
            .briefing: .primary,
            .radioMonitoring: .limited
        ],
        .teamMember: [
            .globalIncidentOverview: .none,
            .sectorCreation: .none,
            .subSectorCreation: .none,
            .commandDispatch: .none,
            .taskAssignment: .none,
            .sosHandling: .primary,
            .gpsTracking: .primary,
            .photoReport: .primary,
            .patientUpload: .limited,
            .startTriage: .none,
            .evacuationManagement: .none,
            .patientStatusUpdate: .none,
            .aiDecisionAnalysis: .none,
            .offlineCache: .primary,
            .safetyControl: .none,
            .eventLog: .none,
            .briefing: .none,
            .radioMonitoring: .none
        ],
        .emt: [
            .globalIncidentOverview: .limited,
            .sectorCreation: .none,
            .subSectorCreation: .none,
            .commandDispatch: .none,
            .taskAssignment: .none,
            .sosHandling: .primary,
            .gpsTracking: .primary,
            .photoReport: .primary,
            .patientUpload: .primary,
            .startTriage: .primary,
            .evacuationManagement: .primary,
            .patientStatusUpdate: .primary,
            .aiDecisionAnalysis: .none,
            .offlineCache: .primary,
            .safetyControl: .none,
            .eventLog: .limited,
            .briefing: .none,
            .radioMonitoring: .none
        ],
        .volunteer: [
            .globalIncidentOverview: .none,
            .sectorCreation: .none,
            .subSectorCreation: .none,
            .commandDispatch: .none,
            .taskAssignment: .none,
            .sosHandling: .limited,
            .gpsTracking: .primary,
            .photoReport: .primary,
            .patientUpload: .none,
            .startTriage: .none,
            .evacuationManagement: .none,
            .patientStatusUpdate: .none,
            .aiDecisionAnalysis: .none,
            .offlineCache: .primary,
            .safetyControl: .none,
            .eventLog: .none,
            .briefing: .none,
            .radioMonitoring: .none
        ]
    ]
}