import Foundation

public enum AuditAction: String, Codable, CaseIterable, Sendable {
    case create
    case update
    case delete
    case issueCommand
    case acknowledgeAlert
    case assignRole
    case login
    case logout
    case sendSOS
    case submitReport
    case mapUpdate
    case syncQueued
    case syncDelivered
    case syncFailed
    case conflictDetected
    case export
}

public struct AuditEvent: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var actorID: LinkGuardID
    public var actorRole: ICSPosition?
    public var appID: LinkGuardAppID
    public var deviceID: LinkGuardID
    public var action: AuditAction
    public var targetType: String
    public var targetID: LinkGuardID
    public var commandChainReferenceID: LinkGuardID?
    public var createdAt: Date

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        actorID: LinkGuardID,
        actorRole: ICSPosition? = nil,
        appID: LinkGuardAppID,
        deviceID: LinkGuardID,
        action: AuditAction,
        targetType: String,
        targetID: LinkGuardID,
        commandChainReferenceID: LinkGuardID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.incidentID = incidentID
        self.actorID = actorID
        self.actorRole = actorRole
        self.appID = appID
        self.deviceID = deviceID
        self.action = action
        self.targetType = targetType
        self.targetID = targetID
        self.commandChainReferenceID = commandChainReferenceID
        self.createdAt = createdAt
    }
}

public struct DecisionRecord: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var title: String
    public var reason: String
    public var decidedBy: LinkGuardID
    public var decidedAt: Date
    public var sourceEventIDs: [LinkGuardID]
    public var expectedOutcome: String?
    public var actualOutcome: String?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        title: String,
        reason: String,
        decidedBy: LinkGuardID,
        decidedAt: Date,
        sourceEventIDs: [LinkGuardID] = [],
        expectedOutcome: String? = nil,
        actualOutcome: String? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.title = title
        self.reason = reason
        self.decidedBy = decidedBy
        self.decidedAt = decidedAt
        self.sourceEventIDs = sourceEventIDs
        self.expectedOutcome = expectedOutcome
        self.actualOutcome = actualOutcome
    }
}

public struct AARTimelineEvent: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var title: String
    public var relatedEventID: LinkGuardID?
    public var occurredAt: Date
    public var priority: PriorityLevel

    public init(id: LinkGuardID, incidentID: LinkGuardID, title: String, relatedEventID: LinkGuardID? = nil, occurredAt: Date, priority: PriorityLevel) {
        self.id = id
        self.incidentID = incidentID
        self.title = title
        self.relatedEventID = relatedEventID
        self.occurredAt = occurredAt
        self.priority = priority
    }
}
