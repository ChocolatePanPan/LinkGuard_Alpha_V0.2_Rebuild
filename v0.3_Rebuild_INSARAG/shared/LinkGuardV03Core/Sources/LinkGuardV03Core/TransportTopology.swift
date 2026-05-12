import Foundation

public enum TransportPolicy: String, Codable, CaseIterable, Sendable {
    case commandSpine
    case fieldOperations
    case broadcast
    case medicalClinical
    case medicalOperational
    case finance
    case audit
}

public struct TransportRoute: Codable, Hashable, Sendable {
    public var messageType: SyncMessageType
    public var policy: TransportPolicy
    public var sourceAppID: LinkGuardAppID
    public var allowedRecipientApps: Set<LinkGuardAppID>
    public var relayApps: [LinkGuardAppID]

    public init(
        messageType: SyncMessageType,
        policy: TransportPolicy,
        sourceAppID: LinkGuardAppID,
        allowedRecipientApps: Set<LinkGuardAppID>,
        relayApps: [LinkGuardAppID]
    ) {
        self.messageType = messageType
        self.policy = policy
        self.sourceAppID = sourceAppID
        self.allowedRecipientApps = allowedRecipientApps
        self.relayApps = relayApps
    }
}

public enum TransportTopology {
    public static let commandApps: Set<LinkGuardAppID> = [.ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad]
    public static let fieldApps: Set<LinkGuardAppID> = [.ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad, .teamMember, .volunteer]
    public static let medicalClinicalApps: Set<LinkGuardAppID> = [.emt, .emtIPad]
    public static let medicalOperationalApps: Set<LinkGuardAppID> = [.ucc, .scc, .sccIPad, .emt, .emtIPad]
    public static let financeApps: Set<LinkGuardAppID> = [.ucc]
    public static let allApps = Set(LinkGuardAppID.allCases)

    public static func route(for envelope: SyncEnvelope) -> TransportRoute {
        let policy = transportPolicy(for: envelope.messageType)
        return TransportRoute(
            messageType: envelope.messageType,
            policy: policy,
            sourceAppID: envelope.sourceAppID,
            allowedRecipientApps: recipientApps(for: policy),
            relayApps: relayPath(from: envelope.sourceAppID, policy: policy)
        )
    }

    public static func canDeliver(_ envelope: SyncEnvelope, to appID: LinkGuardAppID) -> Bool {
        route(for: envelope).allowedRecipientApps.contains(appID)
    }

    private static func transportPolicy(for messageType: SyncMessageType) -> TransportPolicy {
        switch messageType {
        case .incidentUpsert, .sectorUpsert, .roleAssignmentUpsert, .commandUpsert, .decisionRecordUpsert:
            return .commandSpine
        case .worksiteUpsert, .taskUpsert, .mapFeatureUpsert:
            return .fieldOperations
        case .alertUpsert, .alertAcknowledgementUpsert:
            return .broadcast
        case .patientUpsert:
            return .medicalClinical
        case .evacuationRequestUpsert, .hospitalCapacityUpsert:
            return .medicalOperational
        case .purchaseRequestUpsert, .personnelHoursUpsert:
            return .finance
        case .auditEventAppend:
            return .audit
        }
    }

    private static func recipientApps(for policy: TransportPolicy) -> Set<LinkGuardAppID> {
        switch policy {
        case .commandSpine:
            return commandApps
        case .fieldOperations:
            return fieldApps
        case .broadcast:
            return allApps
        case .medicalClinical:
            return medicalClinicalApps
        case .medicalOperational:
            return medicalOperationalApps
        case .finance:
            return financeApps
        case .audit:
            return allApps
        }
    }

    private static func relayPath(from sourceAppID: LinkGuardAppID, policy: TransportPolicy) -> [LinkGuardAppID] {
        switch policy {
        case .commandSpine:
            if sourceAppID == .ucc { return [.scc, .teamLeader] }
            if sourceAppID == .scc || sourceAppID == .sccIPad { return [.ucc, .teamLeader] }
            return [.scc, .ucc]
        case .fieldOperations:
            if sourceAppID == .teamMember || sourceAppID == .volunteer { return [.teamLeader, .scc, .ucc] }
            if sourceAppID == .teamLeader || sourceAppID == .teamLeaderIPad { return [.scc, .ucc] }
            return [.scc]
        case .broadcast:
            return [.ucc, .scc, .teamLeader]
        case .medicalClinical:
            return [.emt, .emtIPad]
        case .medicalOperational:
            return [.emt, .scc, .ucc]
        case .finance:
            return [.ucc]
        case .audit:
            return [.scc, .ucc]
        }
    }
}
