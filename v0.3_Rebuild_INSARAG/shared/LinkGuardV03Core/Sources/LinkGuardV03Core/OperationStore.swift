import Foundation

public struct OperationSnapshot: Codable, Sendable {
    public private(set) var incidents: [LinkGuardID: Incident]
    public private(set) var sectors: [LinkGuardID: Sector]
    public private(set) var subSectors: [LinkGuardID: SubSector]
    public private(set) var worksites: [LinkGuardID: Worksite]
    public private(set) var personnelStatusReports: [LinkGuardID: PersonnelStatusReport]
    public private(set) var teamCapabilityReports: [LinkGuardID: USARTeamCapabilityReport]
    public private(set) var roleAssignments: [LinkGuardID: RoleAssignment]
    public private(set) var commands: [LinkGuardID: OperationalCommand]
    public private(set) var tasks: [LinkGuardID: FieldTask]
    public private(set) var operationalPeriods: [LinkGuardID: OperationalPeriod]
    public private(set) var photoReports: [LinkGuardID: PhotoReport]
    public private(set) var disasterReports: [LinkGuardID: DisasterReport]
    public private(set) var agencyMessages: [LinkGuardID: AgencyMessage]
    public private(set) var ceocMissions: [LinkGuardID: CEOCMission]
    public private(set) var safetyZones: [LinkGuardID: SafetyZone]
    public private(set) var safetyEntryLogs: [LinkGuardID: SafetyEntryLog]
    public private(set) var groupChatMessages: [LinkGuardID: GroupChatMessage]
    public private(set) var voiceReports: [LinkGuardID: VoiceReport]
    public private(set) var alerts: [LinkGuardID: IncidentAlert]
    public private(set) var alertAcknowledgements: [LinkGuardID: AlertAcknowledgement]
    public private(set) var sosReports: [LinkGuardID: SOSReport]
    public private(set) var mapFeatures: [LinkGuardID: MapFeature]
    public private(set) var patients: [LinkGuardID: PatientRecord]
    public private(set) var patientOperationalSummaries: [LinkGuardID: PatientOperationalSummary]
    public private(set) var evacuationRequests: [LinkGuardID: EvacuationRequest]
    public private(set) var hospitalCapacities: [LinkGuardID: HospitalCapacity]
    public private(set) var purchaseRequests: [LinkGuardID: PurchaseRequest]
    public private(set) var personnelHours: [LinkGuardID: PersonnelHours]
    public private(set) var decisionRecords: [LinkGuardID: DecisionRecord]
    public private(set) var auditEvents: [AuditEvent]
    public private(set) var processedIdempotencyKeys: Set<String>

    private enum CodingKeys: String, CodingKey {
        case incidents
        case sectors
        case subSectors
        case worksites
        case personnelStatusReports
        case teamCapabilityReports
        case roleAssignments
        case commands
        case tasks
        case operationalPeriods
        case photoReports
        case disasterReports
        case agencyMessages
        case ceocMissions
        case safetyZones
        case safetyEntryLogs
        case groupChatMessages
        case voiceReports
        case alerts
        case alertAcknowledgements
        case sosReports
        case mapFeatures
        case patients
        case patientOperationalSummaries
        case evacuationRequests
        case hospitalCapacities
        case purchaseRequests
        case personnelHours
        case decisionRecords
        case auditEvents
        case processedIdempotencyKeys
    }

    public init() {
        self.incidents = [:]
        self.sectors = [:]
        self.subSectors = [:]
        self.worksites = [:]
        self.personnelStatusReports = [:]
        self.teamCapabilityReports = [:]
        self.roleAssignments = [:]
        self.commands = [:]
        self.tasks = [:]
        self.operationalPeriods = [:]
        self.photoReports = [:]
        self.disasterReports = [:]
        self.agencyMessages = [:]
        self.ceocMissions = [:]
        self.safetyZones = [:]
        self.safetyEntryLogs = [:]
        self.groupChatMessages = [:]
        self.voiceReports = [:]
        self.alerts = [:]
        self.alertAcknowledgements = [:]
        self.sosReports = [:]
        self.mapFeatures = [:]
        self.patients = [:]
        self.patientOperationalSummaries = [:]
        self.evacuationRequests = [:]
        self.hospitalCapacities = [:]
        self.purchaseRequests = [:]
        self.personnelHours = [:]
        self.decisionRecords = [:]
        self.auditEvents = []
        self.processedIdempotencyKeys = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.incidents = try container.decodeIfPresent([LinkGuardID: Incident].self, forKey: .incidents) ?? [:]
        self.sectors = try container.decodeIfPresent([LinkGuardID: Sector].self, forKey: .sectors) ?? [:]
        self.subSectors = try container.decodeIfPresent([LinkGuardID: SubSector].self, forKey: .subSectors) ?? [:]
        self.worksites = try container.decodeIfPresent([LinkGuardID: Worksite].self, forKey: .worksites) ?? [:]
        self.personnelStatusReports = try container.decodeIfPresent([LinkGuardID: PersonnelStatusReport].self, forKey: .personnelStatusReports) ?? [:]
        self.teamCapabilityReports = try container.decodeIfPresent([LinkGuardID: USARTeamCapabilityReport].self, forKey: .teamCapabilityReports) ?? [:]
        self.roleAssignments = try container.decodeIfPresent([LinkGuardID: RoleAssignment].self, forKey: .roleAssignments) ?? [:]
        self.commands = try container.decodeIfPresent([LinkGuardID: OperationalCommand].self, forKey: .commands) ?? [:]
        self.tasks = try container.decodeIfPresent([LinkGuardID: FieldTask].self, forKey: .tasks) ?? [:]
        self.operationalPeriods = try container.decodeIfPresent([LinkGuardID: OperationalPeriod].self, forKey: .operationalPeriods) ?? [:]
        self.photoReports = try container.decodeIfPresent([LinkGuardID: PhotoReport].self, forKey: .photoReports) ?? [:]
        self.disasterReports = try container.decodeIfPresent([LinkGuardID: DisasterReport].self, forKey: .disasterReports) ?? [:]
        self.agencyMessages = try container.decodeIfPresent([LinkGuardID: AgencyMessage].self, forKey: .agencyMessages) ?? [:]
        self.ceocMissions = try container.decodeIfPresent([LinkGuardID: CEOCMission].self, forKey: .ceocMissions) ?? [:]
        self.safetyZones = try container.decodeIfPresent([LinkGuardID: SafetyZone].self, forKey: .safetyZones) ?? [:]
        self.safetyEntryLogs = try container.decodeIfPresent([LinkGuardID: SafetyEntryLog].self, forKey: .safetyEntryLogs) ?? [:]
        self.groupChatMessages = try container.decodeIfPresent([LinkGuardID: GroupChatMessage].self, forKey: .groupChatMessages) ?? [:]
        self.voiceReports = try container.decodeIfPresent([LinkGuardID: VoiceReport].self, forKey: .voiceReports) ?? [:]
        self.alerts = try container.decodeIfPresent([LinkGuardID: IncidentAlert].self, forKey: .alerts) ?? [:]
        self.alertAcknowledgements = try container.decodeIfPresent([LinkGuardID: AlertAcknowledgement].self, forKey: .alertAcknowledgements) ?? [:]
        self.sosReports = try container.decodeIfPresent([LinkGuardID: SOSReport].self, forKey: .sosReports) ?? [:]
        self.mapFeatures = try container.decodeIfPresent([LinkGuardID: MapFeature].self, forKey: .mapFeatures) ?? [:]
        self.patients = try container.decodeIfPresent([LinkGuardID: PatientRecord].self, forKey: .patients) ?? [:]
        self.patientOperationalSummaries = try container.decodeIfPresent([LinkGuardID: PatientOperationalSummary].self, forKey: .patientOperationalSummaries) ?? [:]
        self.evacuationRequests = try container.decodeIfPresent([LinkGuardID: EvacuationRequest].self, forKey: .evacuationRequests) ?? [:]
        self.hospitalCapacities = try container.decodeIfPresent([LinkGuardID: HospitalCapacity].self, forKey: .hospitalCapacities) ?? [:]
        self.purchaseRequests = try container.decodeIfPresent([LinkGuardID: PurchaseRequest].self, forKey: .purchaseRequests) ?? [:]
        self.personnelHours = try container.decodeIfPresent([LinkGuardID: PersonnelHours].self, forKey: .personnelHours) ?? [:]
        self.decisionRecords = try container.decodeIfPresent([LinkGuardID: DecisionRecord].self, forKey: .decisionRecords) ?? [:]
        self.auditEvents = try container.decodeIfPresent([AuditEvent].self, forKey: .auditEvents) ?? []
        self.processedIdempotencyKeys = try container.decodeIfPresent(Set<String>.self, forKey: .processedIdempotencyKeys) ?? []
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
        case .teamCapabilityReportUpsert:
            let report = try envelope.decodePayload(USARTeamCapabilityReport.self)
            teamCapabilityReports[report.id] = report
        case .roleAssignmentUpsert:
            let roleAssignment = try envelope.decodePayload(RoleAssignment.self)
            roleAssignments[roleAssignment.id] = roleAssignment
        case .commandUpsert:
            let command = try envelope.decodePayload(OperationalCommand.self)
            commands[command.id] = command
        case .taskUpsert:
            let task = try envelope.decodePayload(FieldTask.self)
            tasks[task.id] = task
        case .operationalPeriodUpsert:
            let operationalPeriod = try envelope.decodePayload(OperationalPeriod.self)
            operationalPeriods[operationalPeriod.id] = operationalPeriod
        case .photoReportUpsert:
            let photoReport = try envelope.decodePayload(PhotoReport.self)
            photoReports[photoReport.id] = photoReport
        case .disasterReportUpsert:
            let disasterReport = try envelope.decodePayload(DisasterReport.self)
            disasterReports[disasterReport.id] = disasterReport
        case .agencyMessageUpsert:
            let agencyMessage = try envelope.decodePayload(AgencyMessage.self)
            agencyMessages[agencyMessage.id] = agencyMessage
        case .ceocMissionUpsert:
            let mission = try envelope.decodePayload(CEOCMission.self)
            ceocMissions[mission.id] = mission
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
        case .patientOperationalSummaryUpsert:
            let summary = try envelope.decodePayload(PatientOperationalSummary.self)
            patientOperationalSummaries[summary.id] = summary
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
