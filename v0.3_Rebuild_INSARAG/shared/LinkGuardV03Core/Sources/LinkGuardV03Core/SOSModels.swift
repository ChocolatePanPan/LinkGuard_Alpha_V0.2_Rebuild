import Foundation

public enum SOSDangerType: String, Codable, CaseIterable, Sendable {
    case trapped
    case injured
    case collapseRisk
    case fireOrSmoke
    case hazardousMaterial
    case communicationsFailure
    case missingTeam
    case other
}

public enum SOSStatus: String, Codable, CaseIterable, Sendable {
    case active
    case acknowledged
    case responding
    case resolved
    case cancelled
}

public struct SOSReport: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var reporterDeviceID: LinkGuardID
    public var reporterAppID: LinkGuardAppID
    public var location: GeoCoordinate
    public var dangerType: SOSDangerType
    public var severity: PriorityLevel
    public var note: String?
    public var status: SOSStatus
    public var createdAt: Date
    public var acknowledgedBy: LinkGuardID?
    public var acknowledgedAt: Date?
    public var resolvedAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        reporterDeviceID: LinkGuardID,
        reporterAppID: LinkGuardAppID,
        location: GeoCoordinate,
        dangerType: SOSDangerType,
        severity: PriorityLevel = .critical,
        note: String? = nil,
        status: SOSStatus = .active,
        createdAt: Date,
        acknowledgedBy: LinkGuardID? = nil,
        acknowledgedAt: Date? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.reporterDeviceID = reporterDeviceID
        self.reporterAppID = reporterAppID
        self.location = location
        self.dangerType = dangerType
        self.severity = severity
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.acknowledgedBy = acknowledgedBy
        self.acknowledgedAt = acknowledgedAt
        self.resolvedAt = resolvedAt
    }

    public func asIncidentAlert(issuedBy: LinkGuardID? = nil) -> IncidentAlert {
        IncidentAlert(
            id: LinkGuardID("ALERT-\(id.rawValue)"),
            incidentID: incidentID,
            type: alertType,
            priority: severity,
            title: "SOS",
            body: note ?? dangerType.rawValue,
            issuedBy: issuedBy ?? reporterDeviceID,
            issuedAt: createdAt,
            targetDeviceIDs: [reporterDeviceID]
        )
    }

    private var alertType: AlertType {
        switch dangerType {
        case .collapseRisk:
            return .collapseRisk
        case .fireOrSmoke:
            return .fireOrSmoke
        case .hazardousMaterial:
            return .hazardousMaterial
        case .communicationsFailure:
            return .communicationsFailure
        case .missingTeam:
            return .missingTeam
        case .trapped, .injured, .other:
            return .sos
        }
    }
}