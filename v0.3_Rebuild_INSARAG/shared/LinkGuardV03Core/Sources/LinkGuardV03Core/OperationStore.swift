import Foundation

public struct OperationSnapshot: Codable, Sendable {
    public private(set) var incidents: [LinkGuardID: Incident]
    public private(set) var sectors: [LinkGuardID: Sector]
    public private(set) var subSectors: [LinkGuardID: SubSector]
    public private(set) var worksites: [LinkGuardID: Worksite]
    public private(set) var personnelStatusReports: [LinkGuardID: PersonnelStatusReport]
    public private(set) var roleAssignments: [LinkGuardID: RoleAssignment]
    public private(set) var commands: [LinkGuardID: OperationalCommand]
    public private(set) var tasks: [LinkGuardID: FieldTask]
    public private(set) var photoReports: [LinkGuardID: PhotoReport]
    public private(set) var disasterReports: [LinkGuardID: DisasterReport]
    public private(set) var safetyZones: [LinkGuardID: SafetyZone]
    public private(set) var safetyEntryLogs: [LinkGuardID: SafetyEntryLog]
    public private(set) var groupChatMessages: [LinkGuardID: GroupChatMessage]
    public private(set) var voiceReports: [LinkGuardID: VoiceReport]
    public private(set) var alerts: [LinkGuardID: IncidentAlert]
    public private(set) var alertAcknowledgements: [LinkGuardID: AlertAcknowledgement]
    public private(set) var sosReports: [LinkGuardID: SOSReport]
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
        self.subSectors = [:]
        self.worksites = [:]
        self.personnelStatusReports = [:]
        self.roleAssignments = [:]
        self.commands = [:]
        self.tasks = [:]
        self.photoReports = [:]
        self.disasterReports = [:]
        self.safetyZones = [:]
        self.safetyEntryLogs = [:]
        self.groupChatMessages = [:]
        self.voiceReports = [:]
        self.alerts = [:]
        self.alertAcknowledgements = [:]
        self.sosReports = [:]
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
        case .subSectorUpsert:
            let subSector = try envelope.decodePayload(SubSector.self)
            subSectors[subSector.id] = subSector
        case .worksiteUpsert:
            let worksite = try envelope.decodePayload(Worksite.self)
            worksites[worksite.id] = worksite
        case .personnelStatusUpsert:
            let report = try envelope.decodePayload(PersonnelStatusReport.self)
            personnelStatusReports[report.id] = report
        case .roleAssignmentUpsert:
            let roleAssignment = try envelope.decodePayload(RoleAssignment.self)
            roleAssignments[roleAssignment.id] = roleAssignment
        case .commandUpsert:
            let command = try envelope.decodePayload(OperationalCommand.self)
            commands[command.id] = command
        case .taskUpsert:
            let task = try envelope.decodePayload(FieldTask.self)
            tasks[task.id] = task
        case .photoReportUpsert:
            let photoReport = try envelope.decodePayload(PhotoReport.self)
            photoReports[photoReport.id] = photoReport
        case .disasterReportUpsert:
            let disasterReport = try envelope.decodePayload(DisasterReport.self)
            disasterReports[disasterReport.id] = disasterReport
        case .safetyZoneUpsert:
            let safetyZone = try envelope.decodePayload(SafetyZone.self)
            safetyZones[safetyZone.id] = safetyZone
        case .safetyEntryLogUpsert:
            let entryLog = try envelope.decodePayload(SafetyEntryLog.self)
            safetyEntryLogs[entryLog.id] = entryLog
        case .groupChatMessageAppend:
            let message = try envelope.decodePayload(GroupChatMessage.self)
            groupChatMessages[message.id] = message
        case .voiceReportAppend:
            let voiceReport = try envelope.decodePayload(VoiceReport.self)
            voiceReports[voiceReport.id] = voiceReport
        case .alertUpsert:
            let alert = try envelope.decodePayload(IncidentAlert.self)
            alerts[alert.id] = alert
        case .alertAcknowledgementUpsert:
            let acknowledgement = try envelope.decodePayload(AlertAcknowledgement.self)
            alertAcknowledgements[acknowledgement.id] = acknowledgement
        case .sosReportUpsert:
            let sosReport = try envelope.decodePayload(SOSReport.self)
            sosReports[sosReport.id] = sosReport
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

    public mutating func record(_ auditEvent: AuditEvent) {
        guard auditEvents.contains(where: { $0.id == auditEvent.id }) == false else { return }
        auditEvents.append(auditEvent)
    }

    public func worksites(inSubSector subSectorID: LinkGuardID) -> [Worksite] {
        worksites.values.filter { $0.subSectorID == subSectorID }.sorted { $0.name < $1.name }
    }

    public func latestPersonnelStatuses(onlineWithin seconds: TimeInterval, now: Date) -> [PersonnelStatusReport] {
        personnelStatusReports.values
            .map { report in
                var updatedReport = report
                updatedReport.connectivity = report.isRecentlyOnline(within: seconds, now: now) ? report.connectivity : .offline
                return updatedReport
            }
            .sorted { lhs, rhs in
                if lhs.operationalState != rhs.operationalState {
                    return lhs.operationalState.sortRank < rhs.operationalState.sortRank
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}
