import Foundation

public enum FinanceRecordStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case requested
    case approved
    case rejected
    case closed
}

public struct PurchaseRequest: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var requestedBy: LinkGuardID
    public var itemName: String
    public var quantity: Double
    public var estimatedCost: Double?
    public var reason: String
    public var status: FinanceRecordStatus
    public var linkedTaskID: LinkGuardID?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        requestedBy: LinkGuardID,
        itemName: String,
        quantity: Double,
        estimatedCost: Double? = nil,
        reason: String,
        status: FinanceRecordStatus,
        linkedTaskID: LinkGuardID? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.requestedBy = requestedBy
        self.itemName = itemName
        self.quantity = quantity
        self.estimatedCost = estimatedCost
        self.reason = reason
        self.status = status
        self.linkedTaskID = linkedTaskID
    }
}

public struct PersonnelHours: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var personID: LinkGuardID
    public var incidentID: LinkGuardID
    public var role: ICSPosition
    public var startsAt: Date
    public var endsAt: Date?
    public var approvedBy: LinkGuardID?

    public init(id: LinkGuardID, personID: LinkGuardID, incidentID: LinkGuardID, role: ICSPosition, startsAt: Date, endsAt: Date? = nil, approvedBy: LinkGuardID? = nil) {
        self.id = id
        self.personID = personID
        self.incidentID = incidentID
        self.role = role
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.approvedBy = approvedBy
    }
}
