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
    case safetyControl
    case communication
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

public struct AuditEventQuery: Codable, Hashable, Sendable {
    public var incidentID: LinkGuardID?
    public var actions: Set<AuditAction>
    public var targetTypes: Set<String>
    public var deviceIDs: Set<LinkGuardID>
    public var from: Date?
    public var through: Date?

    public init(
        incidentID: LinkGuardID? = nil,
        actions: Set<AuditAction> = [],
        targetTypes: Set<String> = [],
        deviceIDs: Set<LinkGuardID> = [],
        from: Date? = nil,
        through: Date? = nil
    ) {
        self.incidentID = incidentID
        self.actions = actions
        self.targetTypes = targetTypes
        self.deviceIDs = deviceIDs
        self.from = from
        self.through = through
    }

    public func matches(_ event: AuditEvent) -> Bool {
        if let incidentID, event.incidentID != incidentID { return false }
        if actions.isEmpty == false, actions.contains(event.action) == false { return false }
        if targetTypes.isEmpty == false, targetTypes.contains(event.targetType) == false { return false }
        if deviceIDs.isEmpty == false, deviceIDs.contains(event.deviceID) == false { return false }
        if let from, event.createdAt < from { return false }
        if let through, event.createdAt > through { return false }
        return true
    }
}

public enum AARExportFormat: String, Codable, CaseIterable, Sendable {
    case json
    case csv
}

public struct AARExportBundle: Codable, Sendable {
    public var incidentID: LinkGuardID?
    public var generatedAt: Date
    public var query: AuditEventQuery
    public var auditEvents: [AuditEvent]
    public var decisionRecords: [DecisionRecord]

    public init(
        incidentID: LinkGuardID?,
        generatedAt: Date,
        query: AuditEventQuery,
        auditEvents: [AuditEvent],
        decisionRecords: [DecisionRecord]
    ) {
        self.incidentID = incidentID
        self.generatedAt = generatedAt
        self.query = query
        self.auditEvents = auditEvents
        self.decisionRecords = decisionRecords
    }
}

public enum AARExporter {
    public static func bundle(from snapshot: OperationSnapshot, query: AuditEventQuery, generatedAt: Date) -> AARExportBundle {
        let events = snapshot.auditEvents(matching: query)
        let decisions = snapshot.decisionRecords.values
            .filter { query.incidentID == nil || $0.incidentID == query.incidentID }
            .sorted { $0.decidedAt < $1.decidedAt }
        return AARExportBundle(
            incidentID: query.incidentID,
            generatedAt: generatedAt,
            query: query,
            auditEvents: events,
            decisionRecords: decisions
        )
    }

    public static func export(_ bundle: AARExportBundle, format: AARExportFormat) throws -> Data {
        switch format {
        case .json:
            return try LinkGuardJSON.encode(bundle, prettyPrinted: true)
        case .csv:
            return Data(csv(for: bundle).utf8)
        }
    }

    private static func csv(for bundle: AARExportBundle) -> String {
        var rows = ["createdAt,incidentID,action,targetType,targetID,actorID,appID,deviceID"]
        rows += bundle.auditEvents.map { event in
            [
                event.createdAt.ISO8601Format(),
                event.incidentID.rawValue,
                event.action.rawValue,
                event.targetType,
                event.targetID.rawValue,
                event.actorID.rawValue,
                event.appID.rawValue,
                event.deviceID.rawValue
            ].map(escapeCSV).joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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
