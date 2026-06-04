import Foundation

public enum PersonnelOperationalState: String, Codable, CaseIterable, Sendable {
    case available
    case assigned
    case entering
    case inWorksite
    case exiting
    case resting
    case mayday
    case offline

    public var sortRank: Int {
        switch self {
        case .mayday: return 0
        case .entering, .inWorksite, .exiting: return 1
        case .assigned: return 2
        case .available: return 3
        case .resting: return 4
        case .offline: return 5
        }
    }
}

public enum DeviceConnectivityStatus: String, Codable, CaseIterable, Sendable {
    case online
    case degraded
    case offline
    case unknown
}

public struct PersonnelStatusReport: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var personID: LinkGuardID
    public var deviceID: LinkGuardID
    public var appID: LinkGuardAppID
    public var role: ICSPosition
    public var operationalState: PersonnelOperationalState
    public var connectivity: DeviceConnectivityStatus
    public var location: GeoCoordinate?
    public var currentSectorID: LinkGuardID?
    public var currentSubSectorID: LinkGuardID?
    public var currentWorksiteID: LinkGuardID?
    public var currentTaskID: LinkGuardID?
    public var batteryLevel: Double?
    public var updatedAt: Date
    public var note: String?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        personID: LinkGuardID,
        deviceID: LinkGuardID,
        appID: LinkGuardAppID,
        role: ICSPosition,
        operationalState: PersonnelOperationalState,
        connectivity: DeviceConnectivityStatus,
        location: GeoCoordinate? = nil,
        currentSectorID: LinkGuardID? = nil,
        currentSubSectorID: LinkGuardID? = nil,
        currentWorksiteID: LinkGuardID? = nil,
        currentTaskID: LinkGuardID? = nil,
        batteryLevel: Double? = nil,
        updatedAt: Date,
        note: String? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.personID = personID
        self.deviceID = deviceID
        self.appID = appID
        self.role = role
        self.operationalState = operationalState
        self.connectivity = connectivity
        self.location = location
        self.currentSectorID = currentSectorID
        self.currentSubSectorID = currentSubSectorID
        self.currentWorksiteID = currentWorksiteID
        self.currentTaskID = currentTaskID
        self.batteryLevel = batteryLevel
        self.updatedAt = updatedAt
        self.note = note
    }

    public func isRecentlyOnline(within seconds: TimeInterval, now: Date) -> Bool {
        connectivity == .online && now.timeIntervalSince(updatedAt) <= seconds
    }
}

public struct PhotoReport: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var reporterDeviceID: LinkGuardID
    public var worksiteID: LinkGuardID?
    public var taskID: LinkGuardID?
    public var photoAttachmentID: LinkGuardID
    public var location: GeoCoordinate
    public var capturedAt: Date
    public var receivedAt: Date?
    public var caption: String?
    public var checksum: String?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        reporterDeviceID: LinkGuardID,
        worksiteID: LinkGuardID? = nil,
        taskID: LinkGuardID? = nil,
        photoAttachmentID: LinkGuardID,
        location: GeoCoordinate,
        capturedAt: Date,
        receivedAt: Date? = nil,
        caption: String? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.reporterDeviceID = reporterDeviceID
        self.worksiteID = worksiteID
        self.taskID = taskID
        self.photoAttachmentID = photoAttachmentID
        self.location = location
        self.capturedAt = capturedAt
        self.receivedAt = receivedAt
        self.caption = caption
        self.checksum = checksum
    }
}

public enum SafetyZoneType: String, Codable, CaseIterable, Sendable {
    case hotZone
    case warmZone
    case coldZone
    case noEntry
    case collapseRisk
    case hazardousMaterial
}

public struct SafetyZone: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var zoneType: SafetyZoneType
    public var title: String
    public var geometry: MapGeometry
    public var severity: PriorityLevel
    public var isActive: Bool
    public var updatedBy: LinkGuardID
    public var updatedAt: Date

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        zoneType: SafetyZoneType,
        title: String,
        geometry: MapGeometry,
        severity: PriorityLevel,
        isActive: Bool = true,
        updatedBy: LinkGuardID,
        updatedAt: Date
    ) {
        self.id = id
        self.incidentID = incidentID
        self.zoneType = zoneType
        self.title = title
        self.geometry = geometry
        self.severity = severity
        self.isActive = isActive
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }
}

public enum SafetyEntryAction: String, Codable, CaseIterable, Sendable {
    case checkIn
    case checkOut
    case denied
    case emergencyExit
}

public struct SafetyEntryLog: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var zoneID: LinkGuardID
    public var personID: LinkGuardID
    public var deviceID: LinkGuardID
    public var action: SafetyEntryAction
    public var location: GeoCoordinate?
    public var recordedAt: Date
    public var recordedBy: LinkGuardID
    public var note: String?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        zoneID: LinkGuardID,
        personID: LinkGuardID,
        deviceID: LinkGuardID,
        action: SafetyEntryAction,
        location: GeoCoordinate? = nil,
        recordedAt: Date,
        recordedBy: LinkGuardID,
        note: String? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.zoneID = zoneID
        self.personID = personID
        self.deviceID = deviceID
        self.action = action
        self.location = location
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
        self.note = note
    }
}

public struct GroupChatMessage: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var groupID: LinkGuardID
    public var senderDeviceID: LinkGuardID
    public var senderRole: ICSPosition?
    public var body: String
    public var priority: PriorityLevel
    public var sentAt: Date
    public var location: GeoCoordinate?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        groupID: LinkGuardID,
        senderDeviceID: LinkGuardID,
        senderRole: ICSPosition? = nil,
        body: String,
        priority: PriorityLevel = .medium,
        sentAt: Date,
        location: GeoCoordinate? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.groupID = groupID
        self.senderDeviceID = senderDeviceID
        self.senderRole = senderRole
        self.body = body
        self.priority = priority
        self.sentAt = sentAt
        self.location = location
    }
}

public struct VoiceReport: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var groupID: LinkGuardID
    public var senderDeviceID: LinkGuardID
    public var audioAttachmentID: LinkGuardID?
    public var transcript: String?
    public var durationSeconds: Double
    public var priority: PriorityLevel
    public var recordedAt: Date
    public var location: GeoCoordinate?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        groupID: LinkGuardID,
        senderDeviceID: LinkGuardID,
        audioAttachmentID: LinkGuardID? = nil,
        transcript: String? = nil,
        durationSeconds: Double,
        priority: PriorityLevel = .high,
        recordedAt: Date,
        location: GeoCoordinate? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.groupID = groupID
        self.senderDeviceID = senderDeviceID
        self.audioAttachmentID = audioAttachmentID
        self.transcript = transcript
        self.durationSeconds = durationSeconds
        self.priority = priority
        self.recordedAt = recordedAt
        self.location = location
    }
}