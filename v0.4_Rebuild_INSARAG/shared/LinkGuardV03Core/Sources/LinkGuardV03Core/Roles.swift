import Foundation

public enum ICSSection: String, Codable, CaseIterable, Sendable {
    case command
    case operations
    case planning
    case logistics
    case finance
    case medical
    case afterActionReview
}

public enum ICSPosition: String, Codable, CaseIterable, Sendable {
    case incidentCommander
    case publicInformationOfficer
    case safetyOfficer
    case liaisonOfficer
    case operationsSectionChief
    case planningSectionChief
    case logisticsSectionChief
    case financeSectionChief
    case sectorCommander
    case teamLeader
    case teamMember
    case volunteer
    case emtLead
    case emt
}

public enum RoleScope: String, Codable, Sendable {
    case incident
    case sector
    case worksite
    case team
    case medicalUnit
    case logisticsUnit
}

public struct RoleAssignment: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var personID: LinkGuardID
    public var deviceID: LinkGuardID?
    public var position: ICSPosition
    public var scope: RoleScope
    public var scopeID: LinkGuardID
    public var assignedBy: LinkGuardID
    public var startsAt: Date
    public var expiresAt: Date?
    public var revokedAt: Date?

    public init(
        id: LinkGuardID,
        personID: LinkGuardID,
        deviceID: LinkGuardID? = nil,
        position: ICSPosition,
        scope: RoleScope,
        scopeID: LinkGuardID,
        assignedBy: LinkGuardID,
        startsAt: Date,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.personID = personID
        self.deviceID = deviceID
        self.position = position
        self.scope = scope
        self.scopeID = scopeID
        self.assignedBy = assignedBy
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
    }

    public var isActive: Bool { revokedAt == nil }
}

public enum CommandAuthorityLevel: Int, Codable, Comparable, Sendable {
    case none = 0
    case selfReport = 1
    case team = 2
    case sector = 3
    case incident = 4
    case global = 5

    public static func < (lhs: CommandAuthorityLevel, rhs: CommandAuthorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MedicalAccessLevel: Int, Codable, Comparable, Sendable {
    case none = 0
    case summary = 1
    case operational = 2
    case fullClinical = 3

    public static func < (lhs: MedicalAccessLevel, rhs: MedicalAccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
