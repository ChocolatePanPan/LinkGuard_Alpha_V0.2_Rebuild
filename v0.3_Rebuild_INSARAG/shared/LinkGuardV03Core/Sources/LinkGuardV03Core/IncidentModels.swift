import Foundation

public enum IncidentStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case suspended
    case closed
    case archived
}

public enum PriorityLevel: Int, Codable, Comparable, Sendable {
    case routine = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: PriorityLevel, rhs: PriorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum VerificationStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case pending
    case verified
    case disputed
}

public enum EOCActivationLevel: String, Codable, CaseIterable, Sendable {
    case level1
    case level2
    case level3
}

public struct AgencyIdentity: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var displayName: String
    public var jurisdiction: String?
    public var contactChannel: String?

    public init(id: LinkGuardID, displayName: String, jurisdiction: String? = nil, contactChannel: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.jurisdiction = jurisdiction
        self.contactChannel = contactChannel
    }
}

public enum AgencyMessageKind: String, Codable, CaseIterable, Sendable {
    case notification
    case situationRequest
    case situationReply
    case decision
    case coordination
}

public struct AgencyMessage: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var fromAgency: AgencyIdentity
    public var toAgency: AgencyIdentity
    public var kind: AgencyMessageKind
    public var subject: String
    public var body: String
    public var verificationStatus: VerificationStatus
    public var relatedDisasterReportID: LinkGuardID?
    public var relatedMissionID: LinkGuardID?
    public var emicReferenceID: String?
    public var sentAt: Date
    public var receivedAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        fromAgency: AgencyIdentity,
        toAgency: AgencyIdentity,
        kind: AgencyMessageKind,
        subject: String,
        body: String,
        verificationStatus: VerificationStatus = .pending,
        relatedDisasterReportID: LinkGuardID? = nil,
        relatedMissionID: LinkGuardID? = nil,
        emicReferenceID: String? = nil,
        sentAt: Date,
        receivedAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.fromAgency = fromAgency
        self.toAgency = toAgency
        self.kind = kind
        self.subject = subject
        self.body = body
        self.verificationStatus = verificationStatus
        self.relatedDisasterReportID = relatedDisasterReportID
        self.relatedMissionID = relatedMissionID
        self.emicReferenceID = emicReferenceID
        self.sentAt = sentAt
        self.receivedAt = receivedAt
    }
}

public enum CEOCMissionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case dispatched
    case acknowledged
    case onScene
    case completed
    case cancelled
}

public struct CEOCMission: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var missionNumber: String
    public var issuingAgency: AgencyIdentity
    public var receivingAgency: AgencyIdentity
    public var taskDescription: String
    public var priority: PriorityLevel
    public var status: CEOCMissionStatus
    public var verificationStatus: VerificationStatus
    public var relatedDisasterReportID: LinkGuardID?
    public var emicReferenceID: String?
    public var issuedAt: Date
    public var dispatchedAt: Date?
    public var dueAt: Date?
    public var completedAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        missionNumber: String,
        issuingAgency: AgencyIdentity,
        receivingAgency: AgencyIdentity,
        taskDescription: String,
        priority: PriorityLevel,
        status: CEOCMissionStatus = .pending,
        verificationStatus: VerificationStatus = .pending,
        relatedDisasterReportID: LinkGuardID? = nil,
        emicReferenceID: String? = nil,
        issuedAt: Date,
        dispatchedAt: Date? = nil,
        dueAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.missionNumber = missionNumber
        self.issuingAgency = issuingAgency
        self.receivingAgency = receivingAgency
        self.taskDescription = taskDescription
        self.priority = priority
        self.status = status
        self.verificationStatus = verificationStatus
        self.relatedDisasterReportID = relatedDisasterReportID
        self.emicReferenceID = emicReferenceID
        self.issuedAt = issuedAt
        self.dispatchedAt = dispatchedAt
        self.dueAt = dueAt
        self.completedAt = completedAt
    }
}

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var accuracyMeters: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, accuracyMeters: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracyMeters = accuracyMeters
    }
}

public struct Incident: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var displayName: String
    public var status: IncidentStatus
    public var createdAt: Date
    public var createdBy: LinkGuardID
    public var commandPostLocation: GeoCoordinate?
    public var activeOperationalPeriodID: LinkGuardID?

    public init(
        id: LinkGuardID,
        displayName: String,
        status: IncidentStatus,
        createdAt: Date,
        createdBy: LinkGuardID,
        commandPostLocation: GeoCoordinate? = nil,
        activeOperationalPeriodID: LinkGuardID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.commandPostLocation = commandPostLocation
        self.activeOperationalPeriodID = activeOperationalPeriodID
    }
}

public struct Sector: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var name: String
    public var commanderID: LinkGuardID?
    public var boundaryFeatureID: LinkGuardID?

    public init(id: LinkGuardID, incidentID: LinkGuardID, name: String, commanderID: LinkGuardID? = nil, boundaryFeatureID: LinkGuardID? = nil) {
        self.id = id
        self.incidentID = incidentID
        self.name = name
        self.commanderID = commanderID
        self.boundaryFeatureID = boundaryFeatureID
    }
}

public struct SubSector: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var sectorID: LinkGuardID
    public var name: String
    public var commanderID: LinkGuardID?
    public var boundaryFeatureID: LinkGuardID?
    public var worksiteIDs: [LinkGuardID]

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        sectorID: LinkGuardID,
        name: String,
        commanderID: LinkGuardID? = nil,
        boundaryFeatureID: LinkGuardID? = nil,
        worksiteIDs: [LinkGuardID] = []
    ) {
        self.id = id
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.name = name
        self.commanderID = commanderID
        self.boundaryFeatureID = boundaryFeatureID
        self.worksiteIDs = worksiteIDs
    }
}

public enum ASRLevel: String, Codable, CaseIterable, Sendable {
    case asr1
    case asr2
    case asr3
    case asr4
    case asr5
}

public enum WorksiteStatus: String, Codable, CaseIterable, Sendable {
    case proposed
    case assigned
    case inProgress
    case blocked
    case completed
    case abandoned
}

public struct Worksite: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var sectorID: LinkGuardID
    public var subSectorID: LinkGuardID?
    public var name: String
    public var location: GeoCoordinate?
    public var asrLevel: ASRLevel
    public var status: WorksiteStatus
    public var assignedTeamIDs: [LinkGuardID]
    public var hazardSummary: String?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        sectorID: LinkGuardID,
        subSectorID: LinkGuardID? = nil,
        name: String,
        location: GeoCoordinate? = nil,
        asrLevel: ASRLevel,
        status: WorksiteStatus,
        assignedTeamIDs: [LinkGuardID] = [],
        hazardSummary: String? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.subSectorID = subSectorID
        self.name = name
        self.location = location
        self.asrLevel = asrLevel
        self.status = status
        self.assignedTeamIDs = assignedTeamIDs
        self.hazardSummary = hazardSummary
    }
}

public struct OperationalPeriod: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var startsAt: Date
    public var endsAt: Date
    public var objectives: [String]
    public var safetyMessage: String?
    public var weatherForecast: String?
    public var communicationsPlanSummary: String?
    public var medicalPlanSummary: String?
    public var resourceSummary: String?
    public var eocActivationLevel: EOCActivationLevel?
    public var meetingRecordIDs: [LinkGuardID]

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        startsAt: Date,
        endsAt: Date,
        objectives: [String],
        safetyMessage: String? = nil,
        weatherForecast: String? = nil,
        communicationsPlanSummary: String? = nil,
        medicalPlanSummary: String? = nil,
        resourceSummary: String? = nil,
        eocActivationLevel: EOCActivationLevel? = nil,
        meetingRecordIDs: [LinkGuardID] = []
    ) {
        self.id = id
        self.incidentID = incidentID
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.objectives = objectives
        self.safetyMessage = safetyMessage
        self.weatherForecast = weatherForecast
        self.communicationsPlanSummary = communicationsPlanSummary
        self.medicalPlanSummary = medicalPlanSummary
        self.resourceSummary = resourceSummary
        self.eocActivationLevel = eocActivationLevel
        self.meetingRecordIDs = meetingRecordIDs
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case assigned
    case accepted
    case inProgress
    case blocked
    case completed
    case cancelled
}

public enum TaskType: String, Codable, CaseIterable, Sendable {
    case search
    case rescue
    case recon
    case safetyCheck
    case supplyDelivery
    case medicalSupport
    case evacuationSupport
}

public struct FieldTask: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var worksiteID: LinkGuardID?
    public var assignedTeamID: LinkGuardID?
    public var type: TaskType
    public var status: TaskStatus
    public var priority: PriorityLevel
    public var summary: String
    public var createdAt: Date
    public var dueAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        worksiteID: LinkGuardID? = nil,
        assignedTeamID: LinkGuardID? = nil,
        type: TaskType,
        status: TaskStatus,
        priority: PriorityLevel,
        summary: String,
        createdAt: Date,
        dueAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.worksiteID = worksiteID
        self.assignedTeamID = assignedTeamID
        self.type = type
        self.status = status
        self.priority = priority
        self.summary = summary
        self.createdAt = createdAt
        self.dueAt = dueAt
    }
}
