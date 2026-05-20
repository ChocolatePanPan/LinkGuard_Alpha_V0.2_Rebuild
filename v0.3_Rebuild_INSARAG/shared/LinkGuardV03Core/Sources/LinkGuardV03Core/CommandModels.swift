import Foundation

public enum CommandType: String, Codable, CaseIterable, Sendable {
    case incidentObjective
    case sectorAssignment
    case worksiteAssignment
    case evacuation
    case standDown
    case safetyHold
    case medicalPriority
    case logisticsPriority
}

public enum CommandStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case issued
    case received
    case acknowledged
    case executing
    case completed
    case cancelled
}

public struct OperationalCommand: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var type: CommandType
    public var status: CommandStatus
    public var priority: PriorityLevel
    public var title: String
    public var body: String
    public var issuedBy: LinkGuardID
    public var issuedAt: Date
    public var targetRole: ICSPosition?
    public var targetDeviceIDs: [LinkGuardID]
    public var relatedTaskID: LinkGuardID?
    public var relatedAlertID: LinkGuardID?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        type: CommandType,
        status: CommandStatus,
        priority: PriorityLevel,
        title: String,
        body: String,
        issuedBy: LinkGuardID,
        issuedAt: Date,
        targetRole: ICSPosition? = nil,
        targetDeviceIDs: [LinkGuardID] = [],
        relatedTaskID: LinkGuardID? = nil,
        relatedAlertID: LinkGuardID? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.type = type
        self.status = status
        self.priority = priority
        self.title = title
        self.body = body
        self.issuedBy = issuedBy
        self.issuedAt = issuedAt
        self.targetRole = targetRole
        self.targetDeviceIDs = targetDeviceIDs
        self.relatedTaskID = relatedTaskID
        self.relatedAlertID = relatedAlertID
    }
}
