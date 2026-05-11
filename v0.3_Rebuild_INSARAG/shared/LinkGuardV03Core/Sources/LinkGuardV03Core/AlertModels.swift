import Foundation

public enum AlertType: String, Codable, CaseIterable, Sendable {
    case evacuation
    case collapseRisk
    case fireOrSmoke
    case hazardousMaterial
    case medicalSurge
    case missingTeam
    case communicationsFailure
    case weather
}

public enum AcknowledgementState: String, Codable, CaseIterable, Sendable {
    case unread
    case read
    case acknowledged
    case overdue
    case cancelled
    case forcedRequired
}

public struct IncidentAlert: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var type: AlertType
    public var priority: PriorityLevel
    public var title: String
    public var body: String
    public var issuedBy: LinkGuardID
    public var issuedAt: Date
    public var targetRoleIDs: [LinkGuardID]
    public var targetDeviceIDs: [LinkGuardID]

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        type: AlertType,
        priority: PriorityLevel,
        title: String,
        body: String,
        issuedBy: LinkGuardID,
        issuedAt: Date,
        targetRoleIDs: [LinkGuardID] = [],
        targetDeviceIDs: [LinkGuardID] = []
    ) {
        self.id = id
        self.incidentID = incidentID
        self.type = type
        self.priority = priority
        self.title = title
        self.body = body
        self.issuedBy = issuedBy
        self.issuedAt = issuedAt
        self.targetRoleIDs = targetRoleIDs
        self.targetDeviceIDs = targetDeviceIDs
    }
}

public struct AlertAcknowledgement: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var alertID: LinkGuardID
    public var recipientDeviceID: LinkGuardID
    public var state: AcknowledgementState
    public var readAt: Date?
    public var acknowledgedAt: Date?
    public var location: GeoCoordinate?
    public var forcedReason: String?

    public init(
        id: LinkGuardID,
        alertID: LinkGuardID,
        recipientDeviceID: LinkGuardID,
        state: AcknowledgementState,
        readAt: Date? = nil,
        acknowledgedAt: Date? = nil,
        location: GeoCoordinate? = nil,
        forcedReason: String? = nil
    ) {
        self.id = id
        self.alertID = alertID
        self.recipientDeviceID = recipientDeviceID
        self.state = state
        self.readAt = readAt
        self.acknowledgedAt = acknowledgedAt
        self.location = location
        self.forcedReason = forcedReason
    }
}
