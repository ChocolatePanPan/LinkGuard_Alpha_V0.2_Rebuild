import Foundation

public enum TriageCategory: String, Codable, CaseIterable, Sendable {
    case red
    case yellow
    case green
    case black
}

public enum EvacuationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case assigned
    case departing
    case arrived
    case handedOff
    case cancelled
}

public struct VitalSigns: Codable, Hashable, Sendable {
    public var heartRate: Int?
    public var respiratoryRate: Int?
    public var spo2: Int?
    public var systolicBloodPressure: Int?
    public var diastolicBloodPressure: Int?
    public var gcs: Int?
    public var recordedAt: Date

    public init(
        heartRate: Int? = nil,
        respiratoryRate: Int? = nil,
        spo2: Int? = nil,
        systolicBloodPressure: Int? = nil,
        diastolicBloodPressure: Int? = nil,
        gcs: Int? = nil,
        recordedAt: Date
    ) {
        self.heartRate = heartRate
        self.respiratoryRate = respiratoryRate
        self.spo2 = spo2
        self.systolicBloodPressure = systolicBloodPressure
        self.diastolicBloodPressure = diastolicBloodPressure
        self.gcs = gcs
        self.recordedAt = recordedAt
    }
}

public struct PatientRecord: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var displayCode: String
    public var triageCategory: TriageCategory
    public var injurySummary: String
    public var location: GeoCoordinate?
    public var careLocationID: LinkGuardID?
    public var latestVitals: VitalSigns?
    public var photoAttachmentIDs: [LinkGuardID]
    public var updatedAt: Date

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        displayCode: String,
        triageCategory: TriageCategory,
        injurySummary: String,
        location: GeoCoordinate? = nil,
        careLocationID: LinkGuardID? = nil,
        latestVitals: VitalSigns? = nil,
        photoAttachmentIDs: [LinkGuardID] = [],
        updatedAt: Date
    ) {
        self.id = id
        self.incidentID = incidentID
        self.displayCode = displayCode
        self.triageCategory = triageCategory
        self.injurySummary = injurySummary
        self.location = location
        self.careLocationID = careLocationID
        self.latestVitals = latestVitals
        self.photoAttachmentIDs = photoAttachmentIDs
        self.updatedAt = updatedAt
    }
}

public struct PatientOperationalSummary: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var patientID: LinkGuardID
    public var displayCode: String
    public var triageCategory: TriageCategory
    public var location: GeoCoordinate?
    public var careLocationID: LinkGuardID?
    public var evacuationStatus: EvacuationStatus?
    public var destinationHospitalID: LinkGuardID?
    public var updatedAt: Date

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        patientID: LinkGuardID,
        displayCode: String,
        triageCategory: TriageCategory,
        location: GeoCoordinate? = nil,
        careLocationID: LinkGuardID? = nil,
        evacuationStatus: EvacuationStatus? = nil,
        destinationHospitalID: LinkGuardID? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.incidentID = incidentID
        self.patientID = patientID
        self.displayCode = displayCode
        self.triageCategory = triageCategory
        self.location = location
        self.careLocationID = careLocationID
        self.evacuationStatus = evacuationStatus
        self.destinationHospitalID = destinationHospitalID
        self.updatedAt = updatedAt
    }
}

public struct EvacuationRequest: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var patientID: LinkGuardID
    public var priority: PriorityLevel
    public var destinationHospitalID: LinkGuardID?
    public var assignedVehicleID: LinkGuardID?
    public var status: EvacuationStatus
    public var requestedAt: Date
    public var completedAt: Date?

    public init(
        id: LinkGuardID,
        patientID: LinkGuardID,
        priority: PriorityLevel,
        destinationHospitalID: LinkGuardID? = nil,
        assignedVehicleID: LinkGuardID? = nil,
        status: EvacuationStatus,
        requestedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.patientID = patientID
        self.priority = priority
        self.destinationHospitalID = destinationHospitalID
        self.assignedVehicleID = assignedVehicleID
        self.status = status
        self.requestedAt = requestedAt
        self.completedAt = completedAt
    }
}

public struct HospitalCapacity: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var name: String
    public var emergencyCapacity: Int
    public var traumaCapacity: Int
    public var burnCapacity: Int
    public var pediatricCapacity: Int
    public var updatedAt: Date

    public init(id: LinkGuardID, name: String, emergencyCapacity: Int, traumaCapacity: Int, burnCapacity: Int, pediatricCapacity: Int, updatedAt: Date) {
        self.id = id
        self.name = name
        self.emergencyCapacity = emergencyCapacity
        self.traumaCapacity = traumaCapacity
        self.burnCapacity = burnCapacity
        self.pediatricCapacity = pediatricCapacity
        self.updatedAt = updatedAt
    }
}
