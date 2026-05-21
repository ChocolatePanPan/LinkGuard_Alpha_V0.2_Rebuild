import Foundation

// MARK: - USAR Command Chain Core Models

/// INSARAG-aligned operational phase scoped from UCC downward.
enum USAROperationalPhase: String, Codable, CaseIterable, Identifiable {
    case preparedness
    case mobilization
    case operations
    case demobilization
    case afterAction

    var id: String { rawValue }
}

/// Role scopes used by role-specific apps and permission gates.
enum UCCRole: String, Codable, CaseIterable, Identifiable {
    case uccCommander
    case uccOperations
    case uccPlanning
    case uccResources
    case uccMedical
    case uccSafety
    case sectorCommander
    case sectorSafety
    case sectorLogistics
    case worksiteManager
    case searchLead
    case rescueLead
    case medicalLead
    case logisticsLead
    case squadLeader

    var id: String { rawValue }
}

enum USARPermission: String, Codable, CaseIterable, Identifiable {
    case createIncident
    case editIncident
    case createSector
    case editSector
    case createWorksite
    case editWorksite
    case setGlobalPriority
    case suggestPriority
    case assignSquadTask
    case updateSquadStatus
    case submitASRObservation
    case submitHazardReport
    case submitResourceRequest
    case submitMedicalUpdate
    case issueStopOrEvacuation

    var id: String { rawValue }
}

enum USARFunction: String, Codable, CaseIterable, Identifiable {
    case management
    case search
    case rescue
    case medical
    case logistics
    case safety

    var id: String { rawValue }
}

enum USARCapabilityTier: String, Codable, CaseIterable, Identifiable {
    case light
    case medium
    case heavy

    var id: String { rawValue }
}

enum WorksiteStatus: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case assigned
    case assessing
    case searching
    case rescuing
    case paused
    case evacuated
    case completed

    var id: String { rawValue }
}

enum WorksitePriority: String, Codable, CaseIterable, Identifiable {
    case immediate
    case high
    case normal
    case low
    case deferred

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .immediate: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        case .deferred: return 4
        }
    }
}

enum ASRLevel: Int, Codable, CaseIterable, Identifiable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5

    var id: Int { rawValue }
}

enum ASRConfidence: String, Codable, CaseIterable, Identifiable {
    case initial
    case probable
    case confirmed
    case needsReview

    var id: String { rawValue }
}

enum StructureType: String, Codable, CaseIterable, Identifiable {
    case wood
    case unreinforcedMasonry
    case reinforcedMasonry
    case reinforcedConcrete
    case structuralSteel
    case mixed
    case unknown

    var id: String { rawValue }
}

enum TeamAvailabilityStatus: String, Codable, CaseIterable, Identifiable {
    case available
    case assigned
    case committed
    case rest
    case unavailable

    var id: String { rawValue }
}

enum SquadTaskKind: String, Codable, CaseIterable, Identifiable {
    case assess
    case search
    case rescue
    case medical
    case logistics
    case marking
    case safety
    case evacuation

    var id: String { rawValue }
}

enum SquadTaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case acknowledged
    case enRoute
    case arrived
    case inProgress
    case paused
    case completed
    case cancelled

    var id: String { rawValue }
}

enum SquadOperationalStatus: String, Codable, CaseIterable, Identifiable {
    case standby
    case enRoute
    case arrived
    case assessing
    case searching
    case rescuing
    case treating
    case requestingSupport
    case paused
    case evacuating
    case completed

    var id: String { rawValue }
}

enum USARHazardSeverity: String, Codable, CaseIterable, Identifiable {
    case monitor
    case caution
    case high
    case critical

    var id: String { rawValue }
}

enum USARHazardType: String, Codable, CaseIterable, Identifiable {
    case structuralInstability
    case fire
    case gas
    case electrical
    case flood
    case hazmat
    case accessBlocked
    case security
    case weather
    case other

    var id: String { rawValue }
}

enum ResourceRequestStatus: String, Codable, CaseIterable, Identifiable {
    case requested
    case approved
    case dispatched
    case fulfilled
    case denied
    case cancelled

    var id: String { rawValue }
}

enum RCMMarkingType: String, Codable, CaseIterable, Identifiable {
    case worksiteClassification
    case victimLocation
    case rapidClearance
    case hazard
    case route

    var id: String { rawValue }
}

enum MedicalTransferStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case packaged
    case moving
    case handedOff
    case completed
    case cancelled

    var id: String { rawValue }
}

enum OperationalLogType: String, Codable, CaseIterable, Identifiable {
    case command
    case assignment
    case status
    case asr
    case hazard
    case resource
    case marking
    case medical
    case system

    var id: String { rawValue }
}

struct USARRoleScope: Codable, Identifiable, Equatable {
    var id: String
    var role: UCCRole
    var incidentID: String
    var sectorID: String?
    var worksiteID: String?
    var squadID: String?
    var displayName: String

    init(id: String = UUID().uuidString,
         role: UCCRole,
         incidentID: String,
         sectorID: String? = nil,
         worksiteID: String? = nil,
         squadID: String? = nil,
         displayName: String) {
        self.id = id
        self.role = role
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.worksiteID = worksiteID
        self.squadID = squadID
        self.displayName = displayName
    }

    var permissions: Set<USARPermission> {
        switch role {
        case .uccCommander:
            return Set(USARPermission.allCases)
        case .uccOperations:
            return [.editIncident, .createSector, .editSector, .createWorksite, .editWorksite, .setGlobalPriority, .assignSquadTask, .issueStopOrEvacuation]
        case .uccPlanning:
            return [.editIncident, .createSector, .editSector, .createWorksite, .editWorksite, .suggestPriority]
        case .uccResources:
            return [.editIncident, .submitResourceRequest, .assignSquadTask]
        case .uccMedical:
            return [.submitMedicalUpdate, .submitResourceRequest]
        case .uccSafety:
            return [.submitHazardReport, .suggestPriority, .issueStopOrEvacuation]
        case .sectorCommander:
            return [.editSector, .editWorksite, .assignSquadTask, .submitResourceRequest, .suggestPriority]
        case .sectorSafety:
            return [.submitHazardReport, .suggestPriority]
        case .sectorLogistics:
            return [.submitResourceRequest, .assignSquadTask]
        case .worksiteManager:
            return [.editWorksite, .assignSquadTask, .submitASRObservation, .submitHazardReport, .submitResourceRequest, .suggestPriority]
        case .searchLead, .rescueLead, .medicalLead, .logisticsLead:
            return [.assignSquadTask, .submitASRObservation, .submitHazardReport, .submitResourceRequest, .submitMedicalUpdate]
        case .squadLeader:
            return [.updateSquadStatus, .submitASRObservation, .submitHazardReport, .submitResourceRequest, .submitMedicalUpdate]
        }
    }
}

struct USARIncident: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var operationalPhase: USAROperationalPhase
    var uccName: String
    var lemaName: String?
    var createdAt: Date
    var updatedAt: Date
    var sectorIDs: [String]

    init(id: String = UUID().uuidString,
         name: String,
         operationalPhase: USAROperationalPhase = .operations,
         uccName: String,
         lemaName: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sectorIDs: [String] = []) {
        self.id = id
        self.name = name
        self.operationalPhase = operationalPhase
        self.uccName = uccName
        self.lemaName = lemaName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sectorIDs = sectorIDs
    }
}

struct Sector: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var code: String
    var name: String
    var commanderName: String
    var boundaryDescription: String
    var worksiteIDs: [String]
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         incidentID: String,
         code: String,
         name: String,
         commanderName: String = "",
         boundaryDescription: String = "",
         worksiteIDs: [String] = [],
         updatedAt: Date = Date()) {
        self.id = id
        self.incidentID = incidentID
        self.code = code
        self.name = name
        self.commanderName = commanderName
        self.boundaryDescription = boundaryDescription
        self.worksiteIDs = worksiteIDs
        self.updatedAt = updatedAt
    }
}

struct Worksite: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var sectorID: String
    var code: String
    var name: String
    var address: String
    var locationDescription: String
    var priority: WorksitePriority
    var status: WorksiteStatus
    var currentASRLevel: ASRLevel?
    var assignedTeamIDs: [String]
    var zoneIDs: [String]
    var hazardIDs: [String]
    var victimCount: Int
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         incidentID: String,
         sectorID: String,
         code: String,
         name: String,
         address: String = "",
         locationDescription: String = "",
         priority: WorksitePriority = .normal,
         status: WorksiteStatus = .unassigned,
         currentASRLevel: ASRLevel? = nil,
         assignedTeamIDs: [String] = [],
         zoneIDs: [String] = [],
         hazardIDs: [String] = [],
         victimCount: Int = 0,
         updatedAt: Date = Date()) {
        self.id = id
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.code = code
        self.name = name
        self.address = address
        self.locationDescription = locationDescription
        self.priority = priority
        self.status = status
        self.currentASRLevel = currentASRLevel
        self.assignedTeamIDs = assignedTeamIDs
        self.zoneIDs = zoneIDs
        self.hazardIDs = hazardIDs
        self.victimCount = victimCount
        self.updatedAt = updatedAt
    }
}

struct WorksiteZone: Codable, Identifiable, Equatable {
    var id: String
    var worksiteID: String
    var code: String
    var name: String
    var description: String
    var status: WorksiteStatus

    init(id: String = UUID().uuidString,
         worksiteID: String,
         code: String,
         name: String,
         description: String = "",
         status: WorksiteStatus = .unassigned) {
        self.id = id
        self.worksiteID = worksiteID
        self.code = code
        self.name = name
        self.description = description
        self.status = status
    }
}

struct ASRAssessment: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var worksiteID: String
    var zoneID: String?
    var level: ASRLevel
    var structureType: StructureType
    var collapsePattern: String
    var trappedSigns: String
    var voidPotential: String
    var accessRoutes: String
    var recommendedPriority: WorksitePriority
    var confidence: ASRConfidence
    var assessorRole: UCCRole
    var assessorID: String
    var timestamp: Date
    var notes: String

    init(id: String = UUID().uuidString,
         incidentID: String,
         worksiteID: String,
         zoneID: String? = nil,
         level: ASRLevel,
         structureType: StructureType = .unknown,
         collapsePattern: String = "",
         trappedSigns: String = "",
         voidPotential: String = "",
         accessRoutes: String = "",
         recommendedPriority: WorksitePriority = .normal,
         confidence: ASRConfidence = .initial,
         assessorRole: UCCRole,
         assessorID: String,
         timestamp: Date = Date(),
         notes: String = "") {
        self.id = id
        self.incidentID = incidentID
        self.worksiteID = worksiteID
        self.zoneID = zoneID
        self.level = level
        self.structureType = structureType
        self.collapsePattern = collapsePattern
        self.trappedSigns = trappedSigns
        self.voidPotential = voidPotential
        self.accessRoutes = accessRoutes
        self.recommendedPriority = recommendedPriority
        self.confidence = confidence
        self.assessorRole = assessorRole
        self.assessorID = assessorID
        self.timestamp = timestamp
        self.notes = notes
    }
}

struct USARTeam: Codable, Identifiable, Equatable {
    var id: String
    var code: String
    var name: String
    var capabilityTier: USARCapabilityTier
    var functions: [USARFunction]
    var squadIDs: [String]
    var leaderDeviceID: String?
    var selfSufficientDays: Int
    var status: TeamAvailabilityStatus

    init(id: String = UUID().uuidString,
         code: String,
         name: String,
         capabilityTier: USARCapabilityTier,
         functions: [USARFunction],
         squadIDs: [String] = [],
         leaderDeviceID: String? = nil,
         selfSufficientDays: Int = 7,
         status: TeamAvailabilityStatus = .available) {
        self.id = id
        self.code = code
        self.name = name
        self.capabilityTier = capabilityTier
        self.functions = functions
        self.squadIDs = squadIDs
        self.leaderDeviceID = leaderDeviceID
        self.selfSufficientDays = selfSufficientDays
        self.status = status
    }
}

struct Squad: Codable, Identifiable, Equatable {
    var id: String
    var teamID: String
    var code: String
    var name: String
    var function: USARFunction
    var leaderID: String
    var leaderName: String
    var deviceID: String?
    var memberCount: Int
    var status: SquadOperationalStatus

    init(id: String = UUID().uuidString,
         teamID: String,
         code: String,
         name: String,
         function: USARFunction,
         leaderID: String,
         leaderName: String,
         deviceID: String? = nil,
         memberCount: Int = 0,
         status: SquadOperationalStatus = .standby) {
        self.id = id
        self.teamID = teamID
        self.code = code
        self.name = name
        self.function = function
        self.leaderID = leaderID
        self.leaderName = leaderName
        self.deviceID = deviceID
        self.memberCount = memberCount
        self.status = status
    }
}

struct SquadTask: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var sectorID: String
    var worksiteID: String
    var squadID: String
    var kind: SquadTaskKind
    var title: String
    var instructions: String
    var priority: WorksitePriority
    var status: SquadTaskStatus
    var assignedByRole: UCCRole
    var assignedByID: String
    var createdAt: Date
    var updatedAt: Date
    var dueAt: Date?

    init(id: String = UUID().uuidString,
         incidentID: String,
         sectorID: String,
         worksiteID: String,
         squadID: String,
         kind: SquadTaskKind,
         title: String,
         instructions: String = "",
         priority: WorksitePriority = .normal,
         status: SquadTaskStatus = .pending,
         assignedByRole: UCCRole,
         assignedByID: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         dueAt: Date? = nil) {
        self.id = id
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.worksiteID = worksiteID
        self.squadID = squadID
        self.kind = kind
        self.title = title
        self.instructions = instructions
        self.priority = priority
        self.status = status
        self.assignedByRole = assignedByRole
        self.assignedByID = assignedByID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
    }
}

struct SquadStatus: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var squadID: String
    var taskID: String?
    var worksiteID: String?
    var status: SquadOperationalStatus
    var personnelAvailable: Int
    var personnelInHazardArea: Int
    var batteryPercent: Int?
    var locationDescription: String
    var note: String
    var timestamp: Date

    init(id: String = UUID().uuidString,
         incidentID: String,
         squadID: String,
         taskID: String? = nil,
         worksiteID: String? = nil,
         status: SquadOperationalStatus,
         personnelAvailable: Int,
         personnelInHazardArea: Int = 0,
         batteryPercent: Int? = nil,
         locationDescription: String = "",
         note: String = "",
         timestamp: Date = Date()) {
        self.id = id
        self.incidentID = incidentID
        self.squadID = squadID
        self.taskID = taskID
        self.worksiteID = worksiteID
        self.status = status
        self.personnelAvailable = personnelAvailable
        self.personnelInHazardArea = personnelInHazardArea
        self.batteryPercent = batteryPercent
        self.locationDescription = locationDescription
        self.note = note
        self.timestamp = timestamp
    }
}

struct HazardFlag: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var worksiteID: String
    var zoneID: String?
    var hazardType: USARHazardType
    var severity: USARHazardSeverity
    var description: String
    var mitigation: String
    var reportedByRole: UCCRole
    var reportedByID: String
    var timestamp: Date
    var isActive: Bool

    init(id: String = UUID().uuidString,
         incidentID: String,
         worksiteID: String,
         zoneID: String? = nil,
         hazardType: USARHazardType,
         severity: USARHazardSeverity,
         description: String,
         mitigation: String = "",
         reportedByRole: UCCRole,
         reportedByID: String,
         timestamp: Date = Date(),
         isActive: Bool = true) {
        self.id = id
        self.incidentID = incidentID
        self.worksiteID = worksiteID
        self.zoneID = zoneID
        self.hazardType = hazardType
        self.severity = severity
        self.description = description
        self.mitigation = mitigation
        self.reportedByRole = reportedByRole
        self.reportedByID = reportedByID
        self.timestamp = timestamp
        self.isActive = isActive
    }
}

struct ResourceRequest: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var requesterRole: UCCRole
    var requesterID: String
    var worksiteID: String?
    var squadID: String?
    var resourceType: String
    var quantity: Int
    var priority: WorksitePriority
    var status: ResourceRequestStatus
    var reason: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         incidentID: String,
         requesterRole: UCCRole,
         requesterID: String,
         worksiteID: String? = nil,
         squadID: String? = nil,
         resourceType: String,
         quantity: Int = 1,
         priority: WorksitePriority = .normal,
         status: ResourceRequestStatus = .requested,
         reason: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.incidentID = incidentID
        self.requesterRole = requesterRole
        self.requesterID = requesterID
        self.worksiteID = worksiteID
        self.squadID = squadID
        self.resourceType = resourceType
        self.quantity = quantity
        self.priority = priority
        self.status = status
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct RCMMarking: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var worksiteID: String
    var zoneID: String?
    var markingType: RCMMarkingType
    var code: String
    var meaning: String
    var locationDescription: String
    var placedByRole: UCCRole
    var placedByID: String
    var timestamp: Date

    init(id: String = UUID().uuidString,
         incidentID: String,
         worksiteID: String,
         zoneID: String? = nil,
         markingType: RCMMarkingType,
         code: String,
         meaning: String = "",
         locationDescription: String = "",
         placedByRole: UCCRole,
         placedByID: String,
         timestamp: Date = Date()) {
        self.id = id
        self.incidentID = incidentID
        self.worksiteID = worksiteID
        self.zoneID = zoneID
        self.markingType = markingType
        self.code = code
        self.meaning = meaning
        self.locationDescription = locationDescription
        self.placedByRole = placedByRole
        self.placedByID = placedByID
        self.timestamp = timestamp
    }
}

struct MedicalTransfer: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var victimID: String
    var fromWorksiteID: String
    var toFacilityName: String
    var triageCode: String
    var status: MedicalTransferStatus
    var requestedByID: String
    var timestamp: Date
    var notes: String

    init(id: String = UUID().uuidString,
         incidentID: String,
         victimID: String,
         fromWorksiteID: String,
         toFacilityName: String,
         triageCode: String,
         status: MedicalTransferStatus = .pending,
         requestedByID: String,
         timestamp: Date = Date(),
         notes: String = "") {
        self.id = id
        self.incidentID = incidentID
        self.victimID = victimID
        self.fromWorksiteID = fromWorksiteID
        self.toFacilityName = toFacilityName
        self.triageCode = triageCode
        self.status = status
        self.requestedByID = requestedByID
        self.timestamp = timestamp
        self.notes = notes
    }
}

struct OperationalLog: Codable, Identifiable, Equatable {
    var id: String
    var incidentID: String
    var sourceRole: UCCRole
    var sourceID: String
    var eventType: OperationalLogType
    var title: String
    var detail: String
    var timestamp: Date
    var relatedWorksiteID: String?
    var relatedTaskID: String?

    init(id: String = UUID().uuidString,
         incidentID: String,
         sourceRole: UCCRole,
         sourceID: String,
         eventType: OperationalLogType,
         title: String,
         detail: String = "",
         timestamp: Date = Date(),
         relatedWorksiteID: String? = nil,
         relatedTaskID: String? = nil) {
        self.id = id
        self.incidentID = incidentID
        self.sourceRole = sourceRole
        self.sourceID = sourceID
        self.eventType = eventType
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.relatedWorksiteID = relatedWorksiteID
        self.relatedTaskID = relatedTaskID
    }
}
