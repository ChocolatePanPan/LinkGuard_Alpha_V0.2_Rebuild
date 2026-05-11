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

    public init(id: LinkGuardID, incidentID: LinkGuardID, startsAt: Date, endsAt: Date, objectives: [String], safetyMessage: String? = nil) {
        self.id = id
        self.incidentID = incidentID
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.objectives = objectives
        self.safetyMessage = safetyMessage
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
