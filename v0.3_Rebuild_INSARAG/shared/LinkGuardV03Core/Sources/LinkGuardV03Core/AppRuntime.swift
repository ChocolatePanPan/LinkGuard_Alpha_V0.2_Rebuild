import Foundation

public enum LinkGuardRuntimeError: Error, Equatable, Sendable {
    case missingRoleProfile(LinkGuardAppID)
    case missingBlueprint(LinkGuardAppID)
    case permissionDenied(appID: LinkGuardAppID, permission: LinkGuardPermission, messageType: SyncMessageType)
    case deviceNotRegistered(LinkGuardID)
    case payloadEncodingFailed
}

public enum AppLogicGate {
    public static func requiredPermission(for messageType: SyncMessageType) -> LinkGuardPermission? {
        switch messageType {
        case .incidentUpsert, .sectorUpsert, .subSectorUpsert:
            return .manageIncident
        case .roleAssignmentUpsert:
            return .assignRole
        case .commandUpsert:
            return .issueCommand
        case .worksiteUpsert, .safetyZoneUpsert:
            return .manageMap
        case .mapFeatureUpsert:
            return .submitReport
        case .taskUpsert, .safetyEntryLogUpsert:
            return .updateTask
        case .personnelStatusUpsert, .photoReportUpsert, .disasterReportUpsert, .groupChatMessageAppend, .voiceReportAppend:
            return .submitReport
        case .alertUpsert:
            return .issueCommand
        case .alertAcknowledgementUpsert:
            return .acknowledgeAlert
        case .sosReportUpsert:
            return .sendSOS
        case .patientUpsert:
            return .managePatientReport
        case .evacuationRequestUpsert:
            return .manageEvacuation
        case .hospitalCapacityUpsert:
            return .manageMedicalPatient
        case .purchaseRequestUpsert, .personnelHoursUpsert:
            return .manageFinance
        case .decisionRecordUpsert:
            return .issueCommand
        case .auditEventAppend:
            return nil
        }
    }

    public static func defaultPriority(for messageType: SyncMessageType) -> PriorityLevel {
        switch messageType {
        case .alertUpsert, .sosReportUpsert, .patientUpsert, .evacuationRequestUpsert:
            return .critical
        case .commandUpsert, .worksiteUpsert, .personnelStatusUpsert, .photoReportUpsert, .disasterReportUpsert, .mapFeatureUpsert, .safetyZoneUpsert, .safetyEntryLogUpsert, .voiceReportAppend, .hospitalCapacityUpsert:
            return .high
        case .taskUpsert, .alertAcknowledgementUpsert, .roleAssignmentUpsert, .groupChatMessageAppend:
            return .medium
        case .incidentUpsert, .sectorUpsert, .subSectorUpsert, .purchaseRequestUpsert, .personnelHoursUpsert, .decisionRecordUpsert:
            return .low
        case .auditEventAppend:
            return .routine
        }
    }
}

public struct LinkGuardAppRuntime: Codable, Sendable {
    public var device: DeviceIdentity
    public var profile: RoleProfile
    public var blueprint: AppBlueprint
    public private(set) var snapshot: OperationSnapshot
    public private(set) var outboundQueue: OfflineQueue
    public private(set) var receivedEnvelopeIDs: [LinkGuardID]

    public init(device: DeviceIdentity, snapshot: OperationSnapshot = OperationSnapshot(), outboundQueue: OfflineQueue = OfflineQueue()) {
        self.device = device
        self.profile = RoleProfileCatalog.profile(for: device.appID)
        self.blueprint = AppBlueprintCatalog.blueprint(for: device.appID)
        self.snapshot = snapshot
        self.outboundQueue = outboundQueue
        self.receivedEnvelopeIDs = []
    }

    public func canSend(_ messageType: SyncMessageType) -> Bool {
        guard let permission = AppLogicGate.requiredPermission(for: messageType) else { return true }
        return profile.allows(permission)
    }

    public func makeEnvelope<Payload: Encodable>(
        messageType: SyncMessageType,
        payload: Payload,
        priority: PriorityLevel? = nil,
        createdAt: Date,
        idempotencyKey: String? = nil,
        sourceRole: ICSPosition? = nil
    ) throws -> SyncEnvelope {
        if let permission = AppLogicGate.requiredPermission(for: messageType), profile.allows(permission) == false {
            throw LinkGuardRuntimeError.permissionDenied(appID: device.appID, permission: permission, messageType: messageType)
        }

        return try SyncEnvelope.make(
            messageType: messageType,
            sourceAppID: device.appID,
            sourceDeviceID: device.id,
            sourceRole: sourceRole,
            priority: priority ?? AppLogicGate.defaultPriority(for: messageType),
            createdAt: createdAt,
            idempotencyKey: idempotencyKey ?? "\(device.id.rawValue)-\(messageType.rawValue)-\(createdAt.timeIntervalSince1970)",
            payload: payload
        )
    }

    public mutating func queueOutbound(_ envelope: SyncEnvelope, queuedAt: Date) {
        outboundQueue.enqueue(envelope, queuedAt: queuedAt)
    }

    @discardableResult
    public mutating func queueOffline<Payload: Encodable>(
        messageType: SyncMessageType,
        payload: Payload,
        priority: PriorityLevel? = nil,
        createdAt: Date,
        idempotencyKey: String? = nil,
        sourceRole: ICSPosition? = nil
    ) throws -> SyncEnvelope {
        let envelope = try makeEnvelope(
            messageType: messageType,
            payload: payload,
            priority: priority,
            createdAt: createdAt,
            idempotencyKey: idempotencyKey,
            sourceRole: sourceRole
        )
        queueOutbound(envelope, queuedAt: createdAt)
        return envelope
    }

    public mutating func markOutboundSending(_ messageID: LinkGuardID, at attemptTime: Date) {
        outboundQueue.markSending(messageID: messageID, at: attemptTime)
    }

    public mutating func markOutboundDelivered(_ messageID: LinkGuardID) {
        outboundQueue.markDelivered(messageID: messageID)
        outboundQueue.removeDelivered()
    }

    public mutating func markOutboundFailed(_ messageID: LinkGuardID, error: String) {
        outboundQueue.markFailed(messageID: messageID, error: error)
    }

    public var pendingOutboundCount: Int {
        outboundQueue.entries.filter { $0.state == .queued || $0.state == .failed }.count
    }

    public mutating func receive(_ envelope: SyncEnvelope) throws {
        try snapshot.apply(envelope)
        if let auditEvent = try AuditEventFactory.event(for: envelope, recipientDeviceID: device.id) {
            snapshot.record(auditEvent)
        }
        receivedEnvelopeIDs.append(envelope.id)
    }
}
