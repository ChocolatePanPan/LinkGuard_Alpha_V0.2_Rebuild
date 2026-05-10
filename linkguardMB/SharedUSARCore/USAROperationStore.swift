import Foundation
import Combine

final class USAROperationStore: ObservableObject {
    @Published private(set) var incidents: [String: USARIncident] = [:]
    @Published private(set) var sectors: [String: Sector] = [:]
    @Published private(set) var worksites: [String: Worksite] = [:]
    @Published private(set) var zones: [String: WorksiteZone] = [:]
    @Published private(set) var assessments: [String: ASRAssessment] = [:]
    @Published private(set) var teams: [String: USARTeam] = [:]
    @Published private(set) var squads: [String: Squad] = [:]
    @Published private(set) var squadTasks: [String: SquadTask] = [:]
    @Published private(set) var squadStatuses: [String: SquadStatus] = [:]
    @Published private(set) var hazards: [String: HazardFlag] = [:]
    @Published private(set) var resourceRequests: [String: ResourceRequest] = [:]
    @Published private(set) var markings: [String: RCMMarking] = [:]
    @Published private(set) var medicalTransfers: [String: MedicalTransfer] = [:]
    @Published private(set) var operationalLogs: [String: OperationalLog] = [:]

    func upsertIncident(_ incident: USARIncident) {
        incidents[incident.id] = incident
    }

    func upsertSector(_ sector: Sector) {
        sectors[sector.id] = sector
        if var incident = incidents[sector.incidentID], !incident.sectorIDs.contains(sector.id) {
            incident.sectorIDs.append(sector.id)
            incident.updatedAt = max(incident.updatedAt, sector.updatedAt)
            incidents[incident.id] = incident
        }
    }

    func upsertWorksite(_ worksite: Worksite) {
        worksites[worksite.id] = worksite
        if var sector = sectors[worksite.sectorID], !sector.worksiteIDs.contains(worksite.id) {
            sector.worksiteIDs.append(worksite.id)
            sector.updatedAt = max(sector.updatedAt, worksite.updatedAt)
            sectors[sector.id] = sector
        }
    }

    func upsertZone(_ zone: WorksiteZone) {
        zones[zone.id] = zone
        if var worksite = worksites[zone.worksiteID], !worksite.zoneIDs.contains(zone.id) {
            worksite.zoneIDs.append(zone.id)
            worksite.updatedAt = Date()
            worksites[worksite.id] = worksite
        }
    }

    func upsertAssessment(_ assessment: ASRAssessment) {
        assessments[assessment.id] = assessment
        guard var worksite = worksites[assessment.worksiteID] else { return }
        worksite.currentASRLevel = assessment.level
        worksite.priority = assessment.recommendedPriority
        worksite.updatedAt = max(worksite.updatedAt, assessment.timestamp)
        worksites[worksite.id] = worksite
    }

    func upsertTeam(_ team: USARTeam) {
        teams[team.id] = team
    }

    func upsertSquad(_ squad: Squad) {
        squads[squad.id] = squad
        if var team = teams[squad.teamID], !team.squadIDs.contains(squad.id) {
            team.squadIDs.append(squad.id)
            teams[team.id] = team
        }
    }

    func upsertTask(_ task: SquadTask) {
        squadTasks[task.id] = task
    }

    func upsertSquadStatus(_ status: SquadStatus) {
        squadStatuses[status.id] = status
        if var squad = squads[status.squadID] {
            squad.status = status.status
            squads[squad.id] = squad
        }
        if let taskID = status.taskID, var task = squadTasks[taskID] {
            task.status = taskStatus(from: status.status)
            task.updatedAt = max(task.updatedAt, status.timestamp)
            squadTasks[task.id] = task
        }
    }

    func upsertHazard(_ hazard: HazardFlag) {
        hazards[hazard.id] = hazard
        guard var worksite = worksites[hazard.worksiteID] else { return }
        if hazard.isActive, !worksite.hazardIDs.contains(hazard.id) {
            worksite.hazardIDs.append(hazard.id)
        } else if !hazard.isActive {
            worksite.hazardIDs.removeAll { $0 == hazard.id }
        }
        worksite.updatedAt = max(worksite.updatedAt, hazard.timestamp)
        worksites[worksite.id] = worksite
    }

    func upsertResourceRequest(_ request: ResourceRequest) {
        resourceRequests[request.id] = request
    }

    func upsertMarking(_ marking: RCMMarking) {
        markings[marking.id] = marking
    }

    func upsertMedicalTransfer(_ transfer: MedicalTransfer) {
        medicalTransfers[transfer.id] = transfer
    }

    func appendOperationalLog(_ log: OperationalLog) {
        operationalLogs[log.id] = log
    }

    func apply(_ payload: USARWirePayload) {
        guard let messageType = USARMessageType(rawValue: payload.messageType),
              let payloadData = payload.payloadJSON.data(using: .utf8) else { return }

        let decoder = USARJSON.makeDecoder()
        switch messageType {
        case .worksiteUpsert:
            guard let decoded = try? decoder.decode(USARWorksiteUpsertPayload.self, from: payloadData) else { return }
            upsertWorksite(decoded.worksite)
            decoded.zones.forEach(upsertZone)
            if let currentASR = decoded.currentASR { upsertAssessment(currentASR) }
        case .worksiteAssignment:
            guard let decoded = try? decoder.decode(USARWorksiteAssignmentPayload.self, from: payloadData) else { return }
            upsertSector(decoded.sector)
            upsertWorksite(decoded.worksite)
        case .squadTask:
            guard let decoded = try? decoder.decode(USARSquadTaskPayload.self, from: payloadData) else { return }
            if let worksite = decoded.worksite { upsertWorksite(worksite) }
            upsertTask(decoded.task)
        case .squadStatus:
            guard let decoded = try? decoder.decode(USARSquadStatusPayload.self, from: payloadData) else { return }
            if let relatedTask = decoded.relatedTask { upsertTask(relatedTask) }
            upsertSquadStatus(decoded.status)
        case .asrObservation:
            guard let decoded = try? decoder.decode(USARASRObservationPayload.self, from: payloadData) else { return }
            if let worksite = decoded.suggestedWorksiteUpdate { upsertWorksite(worksite) }
            upsertAssessment(decoded.assessment)
        case .hazardReport:
            guard let decoded = try? decoder.decode(USARHazardReportPayload.self, from: payloadData) else { return }
            upsertHazard(decoded.hazard)
        case .resourceRequest:
            guard let decoded = try? decoder.decode(USARResourceRequestPayload.self, from: payloadData) else { return }
            upsertResourceRequest(decoded.request)
        case .markingUpdate:
            guard let decoded = try? decoder.decode(USARMarkingUpdatePayload.self, from: payloadData) else { return }
            upsertMarking(decoded.marking)
        case .medicalUpdate:
            guard let decoded = try? decoder.decode(USARMedicalUpdatePayload.self, from: payloadData) else { return }
            upsertMedicalTransfer(decoded.transfer)
        case .operationalLog:
            guard let decoded = try? decoder.decode(USAROperationalLogPayload.self, from: payloadData) else { return }
            appendOperationalLog(decoded.log)
        }
    }

    func worksites(in sectorID: String) -> [Worksite] {
        worksites.values
            .filter { $0.sectorID == sectorID }
            .sorted { lhs, rhs in
                if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
                return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
            }
    }

    func activeTasks(for squadID: String) -> [SquadTask] {
        squadTasks.values
            .filter { $0.squadID == squadID && ![.completed, .cancelled].contains($0.status) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func taskStatus(from squadStatus: SquadOperationalStatus) -> SquadTaskStatus {
        switch squadStatus {
        case .standby:
            return .acknowledged
        case .enRoute:
            return .enRoute
        case .arrived:
            return .arrived
        case .assessing, .searching, .rescuing, .treating, .requestingSupport:
            return .inProgress
        case .paused:
            return .paused
        case .evacuating:
            return .paused
        case .completed:
            return .completed
        }
    }
}
