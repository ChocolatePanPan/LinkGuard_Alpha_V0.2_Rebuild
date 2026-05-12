import Foundation

public struct OperationSnapshot: Codable, Sendable {
    public private(set) var incidents: [LinkGuardID: Incident]
    public private(set) var sectors: [LinkGuardID: Sector]
    public private(set) var worksites: [LinkGuardID: Worksite]
    public private(set) var roleAssignments: [LinkGuardID: RoleAssignment]
    public private(set) var commands: [LinkGuardID: OperationalCommand]
    public private(set) var tasks: [LinkGuardID: FieldTask]
    public private(set) var alerts: [LinkGuardID: IncidentAlert]
    public private(set) var alertAcknowledgements: [LinkGuardID: AlertAcknowledgement]
    public private(set) var mapFeatures: [LinkGuardID: MapFeature]
    public private(set) var patients: [LinkGuardID: PatientRecord]
    public private(set) var evacuationRequests: [LinkGuardID: EvacuationRequest]
    public private(set) var hospitalCapacities: [LinkGuardID: HospitalCapacity]
    public private(set) var purchaseRequests: [LinkGuardID: PurchaseRequest]
    public private(set) var personnelHours: [LinkGuardID: PersonnelHours]
    public private(set) var decisionRecords: [LinkGuardID: DecisionRecord]
    public private(set) var auditEvents: [AuditEvent]
    public private(set) var processedIdempotencyKeys: Set<String>

    public init() {
        self.incidents = [:]
        self.sectors = [:]
        self.worksites = [:]
        self.roleAssignments = [:]
        self.commands = [:]
        self.tasks = [:]
        self.alerts = [:]
        self.alertAcknowledgements = [:]
        self.mapFeatures = [:]
        self.patients = [:]
        self.evacuationRequests = [:]
        self.hospitalCapacities = [:]
        self.purchaseRequests = [:]
        self.personnelHours = [:]
        self.decisionRecords = [:]
        self.auditEvents = []
        self.processedIdempotencyKeys = []
    }

    public mutating func apply(_ envelope: SyncEnvelope) throws {
        guard processedIdempotencyKeys.contains(envelope.idempotencyKey) == false else { return }

        switch envelope.messageType {
        case .incidentUpsert:
            let incident = try envelope.decodePayload(Incident.self)
            incidents[incident.id] = incident
        case .sectorUpsert:
            let sector = try envelope.decodePayload(Sector.self)
            sectors[sector.id] = sector
        case .worksiteUpsert:
            let worksite = try envelope.decodePayload(Worksite.self)
            worksites[worksite.id] = worksite
        case .roleAssignmentUpsert:
            let roleAssignment = try envelope.decodePayload(RoleAssignment.self)
            roleAssignments[roleAssignment.id] = roleAssignment
        case .commandUpsert:
            let command = try envelope.decodePayload(OperationalCommand.self)
            commands[command.id] = command
        case .taskUpsert:
            let task = try envelope.decodePayload(FieldTask.self)
            tasks[task.id] = task
        case .alertUpsert:
            let alert = try envelope.decodePayload(IncidentAlert.self)
            alerts[alert.id] = alert
        case .alertAcknowledgementUpsert:
            let acknowledgement = try envelope.decodePayload(AlertAcknowledgement.self)
            alertAcknowledgements[acknowledgement.id] = acknowledgement
        case .mapFeatureUpsert:
            let mapFeature = try envelope.decodePayload(MapFeature.self)
            mapFeatures[mapFeature.id] = mapFeature
        case .patientUpsert:
            let patient = try envelope.decodePayload(PatientRecord.self)
            patients[patient.id] = patient
        case .evacuationRequestUpsert:
            let evacuationRequest = try envelope.decodePayload(EvacuationRequest.self)
            evacuationRequests[evacuationRequest.id] = evacuationRequest
        case .hospitalCapacityUpsert:
            let hospitalCapacity = try envelope.decodePayload(HospitalCapacity.self)
            hospitalCapacities[hospitalCapacity.id] = hospitalCapacity
        case .purchaseRequestUpsert:
            let purchaseRequest = try envelope.decodePayload(PurchaseRequest.self)
            purchaseRequests[purchaseRequest.id] = purchaseRequest
        case .personnelHoursUpsert:
            let personnelHoursRecord = try envelope.decodePayload(PersonnelHours.self)
            personnelHours[personnelHoursRecord.id] = personnelHoursRecord
        case .decisionRecordUpsert:
            let decisionRecord = try envelope.decodePayload(DecisionRecord.self)
            decisionRecords[decisionRecord.id] = decisionRecord
        case .auditEventAppend:
            let auditEvent = try envelope.decodePayload(AuditEvent.self)
            auditEvents.append(auditEvent)
        }

        processedIdempotencyKeys.insert(envelope.idempotencyKey)
    }
}
