import Foundation

public enum VolunteerAudience: String, Codable, CaseIterable, Sendable {
    case civilianVolunteer
    case disasterAssistanceWorker
    case logisticsSupporter
}

public enum VolunteerSupportedLanguage: String, Codable, CaseIterable, Sendable {
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case vietnamese = "vi"
}

public enum DisasterReportKind: String, Codable, CaseIterable, Sendable {
    case collapse
    case fire
    case trapped
    case blockedRoute
    case infrastructureDamage
    case other
}

public struct DisasterReport: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var reporterDeviceID: LinkGuardID
    public var reporterAppID: LinkGuardAppID
    public var kind: DisasterReportKind
    public var location: GeoCoordinate
    public var severity: PriorityLevel
    public var summary: String?
    public var photoAttachmentIDs: [LinkGuardID]
    public var createdAt: Date
    public var receivedAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        reporterDeviceID: LinkGuardID,
        reporterAppID: LinkGuardAppID,
        kind: DisasterReportKind,
        location: GeoCoordinate,
        severity: PriorityLevel = .high,
        summary: String? = nil,
        photoAttachmentIDs: [LinkGuardID] = [],
        createdAt: Date,
        receivedAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.reporterDeviceID = reporterDeviceID
        self.reporterAppID = reporterAppID
        self.kind = kind
        self.location = location
        self.severity = severity
        self.summary = summary
        self.photoAttachmentIDs = photoAttachmentIDs
        self.createdAt = createdAt
        self.receivedAt = receivedAt
    }
}

public struct VolunteerCapabilityPhase: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { phaseNumber }
    public var phaseNumber: Int
    public var moduleName: String
    public var capabilitySummary: String
    public var developmentPurpose: String
    public var requiredFeatures: Set<LinkGuardFeature>
    public var requiredPermissions: Set<LinkGuardPermission>
    public var primaryMessageTypes: Set<SyncMessageType>

    public init(
        phaseNumber: Int,
        moduleName: String,
        capabilitySummary: String,
        developmentPurpose: String,
        requiredFeatures: Set<LinkGuardFeature>,
        requiredPermissions: Set<LinkGuardPermission>,
        primaryMessageTypes: Set<SyncMessageType> = []
    ) {
        self.phaseNumber = phaseNumber
        self.moduleName = moduleName
        self.capabilitySummary = capabilitySummary
        self.developmentPurpose = developmentPurpose
        self.requiredFeatures = requiredFeatures
        self.requiredPermissions = requiredPermissions
        self.primaryMessageTypes = primaryMessageTypes
    }
}

public enum LinkGuardVolunteerBlueprint {
    public static let appID: LinkGuardAppID = .volunteer
    public static let positioning = "Lowest operation complexity disaster reporting tool"
    public static let maxPrimaryActionCount = 4
    public static let audiences: [VolunteerAudience] = [.civilianVolunteer, .disasterAssistanceWorker, .logisticsSupporter]
    public static let supportedLanguages: [VolunteerSupportedLanguage] = [.traditionalChinese, .english, .japanese, .korean, .vietnamese]

    public static let phases: [VolunteerCapabilityPhase] = [
        VolunteerCapabilityPhase(
            phaseNumber: 1,
            moduleName: "Basic Account",
            capabilitySummary: "Login and identity verification",
            developmentPurpose: "Basic user management",
            requiredFeatures: [.accountIdentity],
            requiredPermissions: [.viewIncident]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 2,
            moduleName: "GPS Location",
            capabilitySummary: "Live location reporting",
            developmentPurpose: "Track volunteer position",
            requiredFeatures: [.gpsTracking],
            requiredPermissions: [.submitReport],
            primaryMessageTypes: [.personnelStatusUpsert]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 3,
            moduleName: "SOS",
            capabilitySummary: "Emergency help request",
            developmentPurpose: "Volunteer safety",
            requiredFeatures: [.sosSending],
            requiredPermissions: [.sendSOS],
            primaryMessageTypes: [.sosReportUpsert]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 4,
            moduleName: "Photo Report",
            capabilitySummary: "Upload field photos",
            developmentPurpose: "Disaster situation evidence",
            requiredFeatures: [.photoReport],
            requiredPermissions: [.submitReport],
            primaryMessageTypes: [.photoReportUpsert]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 5,
            moduleName: "Disaster Report",
            capabilitySummary: "Collapse, fire, and trapped-person reports",
            developmentPurpose: "Civilian information intake",
            requiredFeatures: [.disasterReport],
            requiredPermissions: [.submitReport],
            primaryMessageTypes: [.disasterReportUpsert]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 6,
            moduleName: "Offline Draft Queue",
            capabilitySummary: "Cache reports when the network is unavailable",
            developmentPurpose: "Post-disaster operation continuity",
            requiredFeatures: [.offlineDraftQueue],
            requiredPermissions: [.submitReport]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 7,
            moduleName: "Voice Input",
            capabilitySummary: "Speech to text reporting",
            developmentPurpose: "Fast high-pressure reporting",
            requiredFeatures: [.voiceReport],
            requiredPermissions: [.submitReport],
            primaryMessageTypes: [.voiceReportAppend]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 8,
            moduleName: "Multilingual Translation",
            capabilitySummary: "Chinese, English, Japanese, Korean, and Vietnamese support",
            developmentPurpose: "Assist non-local and foreign participants",
            requiredFeatures: [.realtimeTranslation],
            requiredPermissions: [.submitReport]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 9,
            moduleName: "Safety Warning",
            capabilitySummary: "Danger-zone reminders",
            developmentPurpose: "Prevent accidental entry into unsafe areas",
            requiredFeatures: [.hazardWarning, .alertRead],
            requiredPermissions: [.viewIncident, .acknowledgeAlert],
            primaryMessageTypes: [.alertAcknowledgementUpsert]
        ),
        VolunteerCapabilityPhase(
            phaseNumber: 10,
            moduleName: "Simplified Mode",
            capabilitySummary: "Large buttons and fewer pages",
            developmentPurpose: "Reduce misoperation",
            requiredFeatures: [.simplifiedMode],
            requiredPermissions: [.viewIncident]
        )
    ]

    public static var requiredFeatureSet: Set<LinkGuardFeature> {
        phases.reduce(into: Set<LinkGuardFeature>()) { featureSet, phase in
            featureSet.formUnion(phase.requiredFeatures)
        }
    }

    public static func phase(number: Int) -> VolunteerCapabilityPhase? {
        phases.first { $0.phaseNumber == number }
    }

    public static func isFeatureAvailableForVolunteer(_ feature: LinkGuardFeature) -> Bool {
        LinkGuardFeatureAccessMatrix.isAvailable(feature, for: appID)
    }
}