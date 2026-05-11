import Foundation

public enum SyncMessageType: String, Codable, CaseIterable, Sendable {
    case incidentUpsert
    case sectorUpsert
    case worksiteUpsert
    case roleAssignmentUpsert
    case taskUpsert
    case alertUpsert
    case alertAcknowledgementUpsert
    case mapFeatureUpsert
    case patientUpsert
    case evacuationRequestUpsert
    case hospitalCapacityUpsert
    case purchaseRequestUpsert
    case personnelHoursUpsert
    case decisionRecordUpsert
    case auditEventAppend
}

public enum SyncDeliveryState: String, Codable, CaseIterable, Sendable {
    case queued
    case sending
    case delivered
    case failed
    case superseded
}

public struct SyncEnvelope: Codable, Sendable {
    public var id: LinkGuardID
    public var messageType: SyncMessageType
    public var schemaVersion: Int
    public var sourceAppID: LinkGuardAppID
    public var sourceDeviceID: LinkGuardID
    public var sourceRole: ICSPosition?
    public var priority: PriorityLevel
    public var createdAt: Date
    public var idempotencyKey: String
    public var payloadData: Data

    public init(
        id: LinkGuardID,
        messageType: SyncMessageType,
        schemaVersion: Int = 1,
        sourceAppID: LinkGuardAppID,
        sourceDeviceID: LinkGuardID,
        sourceRole: ICSPosition? = nil,
        priority: PriorityLevel,
        createdAt: Date,
        idempotencyKey: String,
        payloadData: Data
    ) {
        self.id = id
        self.messageType = messageType
        self.schemaVersion = schemaVersion
        self.sourceAppID = sourceAppID
        self.sourceDeviceID = sourceDeviceID
        self.sourceRole = sourceRole
        self.priority = priority
        self.createdAt = createdAt
        self.idempotencyKey = idempotencyKey
        self.payloadData = payloadData
    }

    public static func make<Payload: Encodable>(
        id: LinkGuardID = .generated(prefix: "MSG"),
        messageType: SyncMessageType,
        sourceAppID: LinkGuardAppID,
        sourceDeviceID: LinkGuardID,
        sourceRole: ICSPosition? = nil,
        priority: PriorityLevel,
        createdAt: Date,
        idempotencyKey: String,
        payload: Payload
    ) throws -> SyncEnvelope {
        SyncEnvelope(
            id: id,
            messageType: messageType,
            sourceAppID: sourceAppID,
            sourceDeviceID: sourceDeviceID,
            sourceRole: sourceRole,
            priority: priority,
            createdAt: createdAt,
            idempotencyKey: idempotencyKey,
            payloadData: try LinkGuardJSON.encode(payload)
        )
    }

    public func decodePayload<Payload: Decodable>(_ type: Payload.Type) throws -> Payload {
        try LinkGuardJSON.decode(type, from: payloadData)
    }
}

public struct OfflineQueueEntry: Codable, Sendable {
    public var envelope: SyncEnvelope
    public var state: SyncDeliveryState
    public var attempts: Int
    public var lastError: String?
    public var queuedAt: Date
    public var lastAttemptAt: Date?

    public init(
        envelope: SyncEnvelope,
        state: SyncDeliveryState = .queued,
        attempts: Int = 0,
        lastError: String? = nil,
        queuedAt: Date,
        lastAttemptAt: Date? = nil
    ) {
        self.envelope = envelope
        self.state = state
        self.attempts = attempts
        self.lastError = lastError
        self.queuedAt = queuedAt
        self.lastAttemptAt = lastAttemptAt
    }
}
