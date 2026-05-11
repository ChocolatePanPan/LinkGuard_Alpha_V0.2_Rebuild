import Foundation

// MARK: - USAR Transport Contracts

enum USARProtocolVersion {
    static let current = 1
}

enum USARJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum USARMessageType: String, Codable, CaseIterable, Identifiable {
    case roleAssignment = "usar_role_assignment"
    case worksiteUpsert = "usar_worksite_upsert"
    case worksiteAssignment = "usar_worksite_assignment"
    case squadTask = "usar_squad_task"
    case squadStatus = "usar_squad_status"
    case asrObservation = "usar_asr_observation"
    case hazardReport = "usar_hazard_report"
    case resourceRequest = "usar_resource_request"
    case markingUpdate = "usar_marking_update"
    case medicalUpdate = "usar_medical_update"
    case operationalLog = "usar_operational_log"

    var id: String { rawValue }
}

struct USARRoleAssignmentPayload: Codable, Equatable {
    var scope: USARRoleScope
    var assignedDeviceID: String
    var instructions: String

    init(scope: USARRoleScope, assignedDeviceID: String, instructions: String = "") {
        self.scope = scope
        self.assignedDeviceID = assignedDeviceID
        self.instructions = instructions
    }
}

struct USARProtocolEnvelope<Payload: Codable>: Codable, Identifiable {
    var id: String
    var version: Int
    var messageType: USARMessageType
    var incidentID: String
    var originRole: UCCRole
    var originID: String
    var targetRole: UCCRole?
    var targetIDs: [String]
    var timestamp: Date
    var payload: Payload

    init(id: String = UUID().uuidString,
         version: Int = USARProtocolVersion.current,
         messageType: USARMessageType,
         incidentID: String,
         originRole: UCCRole,
         originID: String,
         targetRole: UCCRole? = nil,
         targetIDs: [String] = [],
         timestamp: Date = Date(),
         payload: Payload) {
        self.id = id
        self.version = version
        self.messageType = messageType
        self.incidentID = incidentID
        self.originRole = originRole
        self.originID = originID
        self.targetRole = targetRole
        self.targetIDs = targetIDs
        self.timestamp = timestamp
        self.payload = payload
    }
}

struct USARWorksiteUpsertPayload: Codable, Equatable {
    var worksite: Worksite
    var zones: [WorksiteZone]
    var currentASR: ASRAssessment?

    init(worksite: Worksite, zones: [WorksiteZone] = [], currentASR: ASRAssessment? = nil) {
        self.worksite = worksite
        self.zones = zones
        self.currentASR = currentASR
    }
}

struct USARWorksiteAssignmentPayload: Codable, Equatable {
    var sector: Sector
    var worksite: Worksite
    var assignedTeamIDs: [String]
    var instructions: String

    init(sector: Sector,
         worksite: Worksite,
         assignedTeamIDs: [String] = [],
         instructions: String = "") {
        self.sector = sector
        self.worksite = worksite
        self.assignedTeamIDs = assignedTeamIDs
        self.instructions = instructions
    }
}

struct USARSquadTaskPayload: Codable, Equatable {
    var task: SquadTask
    var worksite: Worksite?

    init(task: SquadTask, worksite: Worksite? = nil) {
        self.task = task
        self.worksite = worksite
    }
}

struct USARSquadStatusPayload: Codable, Equatable {
    var status: SquadStatus
    var relatedTask: SquadTask?

    init(status: SquadStatus, relatedTask: SquadTask? = nil) {
        self.status = status
        self.relatedTask = relatedTask
    }
}

struct USARASRObservationPayload: Codable, Equatable {
    var assessment: ASRAssessment
    var suggestedWorksiteUpdate: Worksite?

    init(assessment: ASRAssessment, suggestedWorksiteUpdate: Worksite? = nil) {
        self.assessment = assessment
        self.suggestedWorksiteUpdate = suggestedWorksiteUpdate
    }
}

struct USARHazardReportPayload: Codable, Equatable {
    var hazard: HazardFlag

    init(hazard: HazardFlag) {
        self.hazard = hazard
    }
}

struct USARResourceRequestPayload: Codable, Equatable {
    var request: ResourceRequest

    init(request: ResourceRequest) {
        self.request = request
    }
}

struct USARMarkingUpdatePayload: Codable, Equatable {
    var marking: RCMMarking

    init(marking: RCMMarking) {
        self.marking = marking
    }
}

struct USARMedicalUpdatePayload: Codable, Equatable {
    var transfer: MedicalTransfer

    init(transfer: MedicalTransfer) {
        self.transfer = transfer
    }
}

struct USAROperationalLogPayload: Codable, Equatable {
    var log: OperationalLog

    init(log: OperationalLog) {
        self.log = log
    }
}

struct USARWirePayload: Codable, Equatable {
    var version: Int
    var messageID: String
    var messageType: String
    var incidentID: String
    var originRole: String
    var originID: String
    var targetRole: String?
    var targetIDs: [String]
    var timestamp: Double
    var payloadJSON: String

    init(version: Int = USARProtocolVersion.current,
         messageID: String,
         messageType: USARMessageType,
         incidentID: String,
         originRole: UCCRole,
         originID: String,
         targetRole: UCCRole? = nil,
         targetIDs: [String] = [],
         timestamp: Date = Date(),
         payloadJSON: String) {
        self.version = version
        self.messageID = messageID
        self.messageType = messageType.rawValue
        self.incidentID = incidentID
        self.originRole = originRole.rawValue
        self.originID = originID
        self.targetRole = targetRole?.rawValue
        self.targetIDs = targetIDs
        self.timestamp = timestamp.timeIntervalSince1970
        self.payloadJSON = payloadJSON
    }
}

extension USARProtocolEnvelope {
    func wirePayload(encoder: JSONEncoder = USARJSON.makeEncoder()) throws -> USARWirePayload {
        let payloadData = try encoder.encode(payload)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw EncodingError.invalidValue(payload, EncodingError.Context(codingPath: [], debugDescription: "USAR payload is not valid UTF-8 JSON"))
        }

        return USARWirePayload(
            version: version,
            messageID: id,
            messageType: messageType,
            incidentID: incidentID,
            originRole: originRole,
            originID: originID,
            targetRole: targetRole,
            targetIDs: targetIDs,
            timestamp: timestamp,
            payloadJSON: payloadJSON
        )
    }
}
