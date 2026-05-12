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
        case .incidentUpsert, .sectorUpsert:
            return .manageIncident
        case .roleAssignmentUpsert:
            return .assignRole
        case .commandUpsert:
            return .issueCommand
        case .worksiteUpsert, .mapFeatureUpsert:
            return .manageMap
        case .taskUpsert:
            return .updateTask
        case .alertUpsert:
            return .issueCommand
        case .alertAcknowledgementUpsert:
            return .acknowledgeAlert
        case .patientUpsert, .evacuationRequestUpsert, .hospitalCapacityUpsert:
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
        case .alertUpsert, .patientUpsert, .evacuationRequestUpsert:
            return .critical
        case .commandUpsert, .worksiteUpsert, .mapFeatureUpsert, .hospitalCapacityUpsert:
            return .high
        case .taskUpsert, .alertAcknowledgementUpsert, .roleAssignmentUpsert:
            return .medium
        case .incidentUpsert, .sectorUpsert, .purchaseRequestUpsert, .personnelHoursUpsert, .decisionRecordUpsert:
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

    public mutating func markOutboundDelivered(_ messageID: LinkGuardID) {
        outboundQueue.markDelivered(messageID: messageID)
        outboundQueue.removeDelivered()
    }

    public mutating func receive(_ envelope: SyncEnvelope) throws {
        try snapshot.apply(envelope)
        receivedEnvelopeIDs.append(envelope.id)
    }
}
