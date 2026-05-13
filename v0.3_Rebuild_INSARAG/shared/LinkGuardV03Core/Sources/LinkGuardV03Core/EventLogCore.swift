import Foundation

public struct AuditTargetDescriptor: Codable, Hashable, Sendable {
    public var incidentID: LinkGuardID
    public var targetType: String
    public var targetID: LinkGuardID
    public var action: AuditAction
    public var commandChainReferenceID: LinkGuardID?

    public init(
        incidentID: LinkGuardID,
        targetType: String,
        targetID: LinkGuardID,
        action: AuditAction,
        commandChainReferenceID: LinkGuardID? = nil
    ) {
        self.incidentID = incidentID
        self.targetType = targetType
        self.targetID = targetID
        self.action = action
        self.commandChainReferenceID = commandChainReferenceID
    }
}

public enum AuditEventFactory {
    public static func event(for envelope: SyncEnvelope, recipientDeviceID: LinkGuardID) throws -> AuditEvent? {
        guard envelope.messageType != .auditEventAppend else { return nil }
        let descriptor = try targetDescriptor(for: envelope)
        return AuditEvent(
            id: LinkGuardID("AUD-\(envelope.id.rawValue)-\(recipientDeviceID.rawValue)"),
            incidentID: descriptor.incidentID,
            actorID: envelope.sourceDeviceID,
            actorRole: envelope.sourceRole,
            appID: envelope.sourceAppID,
            deviceID: envelope.sourceDeviceID,
            action: descriptor.action,
            targetType: descriptor.targetType,
            targetID: descriptor.targetID,
            commandChainReferenceID: descriptor.commandChainReferenceID,
            createdAt: envelope.createdAt
        )
    }

    public static func targetDescriptor(for envelope: SyncEnvelope) throws -> AuditTargetDescriptor {
        switch envelope.messageType {
        case .incidentUpsert:
            let item = try envelope.decodePayload(Incident.self)
            return AuditTargetDescriptor(incidentID: item.id, targetType: "incident", targetID: item.id, action: .update)
        case .sectorUpsert:
            let item = try envelope.decodePayload(Sector.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "sector", targetID: item.id, action: .update)
        case .worksiteUpsert:
            let item = try envelope.decodePayload(Worksite.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "worksite", targetID: item.id, action: .update)
        case .roleAssignmentUpsert:
            let item = try envelope.decodePayload(RoleAssignment.self)
            return AuditTargetDescriptor(incidentID: item.scopeID, targetType: "roleAssignment", targetID: item.id, action: .assignRole)
        case .commandUpsert:
            let item = try envelope.decodePayload(OperationalCommand.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "command", targetID: item.id, action: .issueCommand, commandChainReferenceID: item.relatedTaskID)
        case .taskUpsert:
            let item = try envelope.decodePayload(FieldTask.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "task", targetID: item.id, action: .update)
        case .alertUpsert:
            let item = try envelope.decodePayload(IncidentAlert.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "alert", targetID: item.id, action: .issueCommand)
        case .alertAcknowledgementUpsert:
            let item = try envelope.decodePayload(AlertAcknowledgement.self)
            return AuditTargetDescriptor(incidentID: item.alertID, targetType: "alertAcknowledgement", targetID: item.id, action: .acknowledgeAlert)
        case .sosReportUpsert:
            let item = try envelope.decodePayload(SOSReport.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "sosReport", targetID: item.id, action: .sendSOS)
        case .mapFeatureUpsert:
            let item = try envelope.decodePayload(MapFeature.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "mapFeature", targetID: item.id, action: .mapUpdate)
        case .patientUpsert:
            let item = try envelope.decodePayload(PatientRecord.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "patient", targetID: item.id, action: .submitReport)
        case .evacuationRequestUpsert:
            let item = try envelope.decodePayload(EvacuationRequest.self)
            return AuditTargetDescriptor(incidentID: item.patientID, targetType: "evacuationRequest", targetID: item.id, action: .submitReport)
        case .hospitalCapacityUpsert:
            let item = try envelope.decodePayload(HospitalCapacity.self)
            return AuditTargetDescriptor(incidentID: item.id, targetType: "hospitalCapacity", targetID: item.id, action: .submitReport)
        case .purchaseRequestUpsert:
            let item = try envelope.decodePayload(PurchaseRequest.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "purchaseRequest", targetID: item.id, action: .update)
        case .personnelHoursUpsert:
            let item = try envelope.decodePayload(PersonnelHours.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "personnelHours", targetID: item.id, action: .update)
        case .decisionRecordUpsert:
            let item = try envelope.decodePayload(DecisionRecord.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "decisionRecord", targetID: item.id, action: .issueCommand)
        case .auditEventAppend:
            let item = try envelope.decodePayload(AuditEvent.self)
            return AuditTargetDescriptor(incidentID: item.incidentID, targetType: "auditEvent", targetID: item.id, action: item.action)
        }
    }
}