import Foundation

public enum LinkGuardProductShell: String, Codable, CaseIterable, Sendable {
    case mobile
    case command
    case adminProvisioning
}

public enum ModuleActivationMode: String, Codable, CaseIterable, Sendable {
    case enabled
    case hidden
}

public enum LinkGuardModuleID: String, Codable, CaseIterable, Sendable {
    case volunteerReporting
    case teamMemberOperations
    case teamLeaderOperations
    case emtMedical
    case sccMobileCommand
    case fieldAIAssistant
    case photoEvidence
    case voicePTT
    case fieldTranslation
    case patientTriage
    case nfcPatientTagging
    case hospitalDirectory
    case personalNotifications
    case ceocDashboard
    case sccCommand
    case mapOperations
    case agencyMessaging
    case resourceCoordination
    case aarReplay
    case backupReplay
    case adminProvisioning
}

public struct LinkGuardModuleEntitlement: Codable, Hashable, Sendable, Identifiable {
    public var id: LinkGuardModuleID
    public var displayName: String
    public var shell: LinkGuardProductShell
    public var allowedAppIDs: Set<LinkGuardAppID>
    public var requiredPermissions: Set<LinkGuardPermission>
    public var sourceVersion: String?
    public var sourceFeatureNames: [String]
    public var linkedFeatures: Set<LinkGuardFeature>

    public init(
        id: LinkGuardModuleID,
        displayName: String,
        shell: LinkGuardProductShell,
        allowedAppIDs: Set<LinkGuardAppID>,
        requiredPermissions: Set<LinkGuardPermission>,
        sourceVersion: String? = nil,
        sourceFeatureNames: [String] = [],
        linkedFeatures: Set<LinkGuardFeature> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.shell = shell
        self.allowedAppIDs = allowedAppIDs
        self.requiredPermissions = requiredPermissions
        self.sourceVersion = sourceVersion
        self.sourceFeatureNames = sourceFeatureNames
        self.linkedFeatures = linkedFeatures
    }

    public func activationMode(for session: LoginSession) -> ModuleActivationMode {
        guard allowedAppIDs.contains(session.device.appID) else { return .hidden }
        guard requiredPermissions.isSubset(of: session.permissions) else { return .hidden }
        return .enabled
    }
}

public struct ModuleActivationSnapshot: Codable, Hashable, Sendable {
    public var sessionID: LinkGuardID
    public var accountID: LinkGuardID
    public var device: DeviceIdentity
    public var shell: LinkGuardProductShell
    public var enabledModules: [LinkGuardModuleEntitlement]
    public var hiddenModules: [LinkGuardModuleEntitlement]
    public var issuedAt: Date
    public var expiresAt: Date?

    public init(
        sessionID: LinkGuardID,
        accountID: LinkGuardID,
        device: DeviceIdentity,
        shell: LinkGuardProductShell,
        enabledModules: [LinkGuardModuleEntitlement],
        hiddenModules: [LinkGuardModuleEntitlement],
        issuedAt: Date,
        expiresAt: Date?
    ) {
        self.sessionID = sessionID
        self.accountID = accountID
        self.device = device
        self.shell = shell
        self.enabledModules = enabledModules
        self.hiddenModules = hiddenModules
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public func enables(_ moduleID: LinkGuardModuleID) -> Bool {
        enabledModules.contains { $0.id == moduleID }
    }
}

public enum ModuleActivationCatalog {
    public static let entitlements: [LinkGuardModuleEntitlement] = [
        LinkGuardModuleEntitlement(
            id: .volunteerReporting,
            displayName: "VO 災情通報",
            shell: .mobile,
            allowedAppIDs: [.volunteer],
            requiredPermissions: [.viewIncident, .submitReport, .sendSOS]
        ),
        LinkGuardModuleEntitlement(
            id: .teamMemberOperations,
            displayName: "TE 任務執行",
            shell: .mobile,
            allowedAppIDs: [.teamMember],
            requiredPermissions: [.viewIncident, .updateTask, .submitReport, .sendSOS]
        ),
        LinkGuardModuleEntitlement(
            id: .teamLeaderOperations,
            displayName: "TL 分隊管理",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad],
            requiredPermissions: [.viewIncident, .issueCommand, .updateTask, .submitReport]
        ),
        LinkGuardModuleEntitlement(
            id: .emtMedical,
            displayName: "EMT 醫療作業",
            shell: .mobile,
            allowedAppIDs: [.emt, .emtIPad],
            requiredPermissions: [.viewIncident, .viewMedicalSummary, .viewMedicalDetails, .manageMedicalPatient]
        ),
        LinkGuardModuleEntitlement(
            id: .sccMobileCommand,
            displayName: "SCC Mobile 現場指揮",
            shell: .mobile,
            allowedAppIDs: [.sccIPad],
            requiredPermissions: [.viewIncident, .issueCommand, .manageMap, .updateTask]
        ),
        LinkGuardModuleEntitlement(
            id: .fieldAIAssistant,
            displayName: "V0.25 前線 AI 回報",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .sccIPad],
            requiredPermissions: [.viewIncident, .submitReport, .useFieldAI],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["FieldAIReportView", "FieldAIChatManager", "雙 AI 共識上報"],
            linkedFeatures: [.aiFieldRiskAnalysis, .aiChat, .aiDecisionAnalysis, .disasterReport]
        ),
        LinkGuardModuleEntitlement(
            id: .photoEvidence,
            displayName: "V0.25 照片/影像證據",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .volunteer, .emt, .emtIPad, .sccIPad],
            requiredPermissions: [.viewIncident, .submitReport],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["PhotoReportView", "photo_server.py", "縮圖/原圖/USB 備份"],
            linkedFeatures: [.photoReport, .liveFieldPhoto, .multiPointPhotoReport, .photoWall, .patientPhoto]
        ),
        LinkGuardModuleEntitlement(
            id: .voicePTT,
            displayName: "V0.25 PTT/語音轉錄",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .volunteer, .sccIPad],
            requiredPermissions: [.viewIncident, .submitReport],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["RadioView", "VoiceInputManager", "whisper_server.py", "LGAP UDP audio"],
            linkedFeatures: [.voiceReport, .speechTranscription, .radioMonitoring, .voiceOperationMode]
        ),
        LinkGuardModuleEntitlement(
            id: .fieldTranslation,
            displayName: "V0.25 現場翻譯",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .volunteer, .emt, .emtIPad, .sccIPad],
            requiredPermissions: [.viewIncident, .useTranslation],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["TranslatorView", "voiceTranslation", "offline fallback"],
            linkedFeatures: [.realtimeTranslation, .voiceTranslation]
        ),
        LinkGuardModuleEntitlement(
            id: .patientTriage,
            displayName: "V0.25 START 檢傷",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .emt, .emtIPad],
            requiredPermissions: [.viewIncident, .managePatientReport],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["PatientFormView", "start_triage.py", "triage.py"],
            linkedFeatures: [.patientCreation, .startTriage, .patientStatusUpdate, .patientLocation, .medicalEvacuation]
        ),
        LinkGuardModuleEntitlement(
            id: .nfcPatientTagging,
            displayName: "V0.25 NFC 傷患標籤",
            shell: .mobile,
            allowedAppIDs: [.emt, .emtIPad],
            requiredPermissions: [.viewIncident, .manageMedicalPatient, .writeNFCTag],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["NFCReaderView", "PatientIDConfig", "NFCTagWriteRecord"],
            linkedFeatures: [.patientCreation, .patientHistory, .patientStatusUpdate]
        ),
        LinkGuardModuleEntitlement(
            id: .hospitalDirectory,
            displayName: "V0.25 醫院/收容查詢",
            shell: .mobile,
            allowedAppIDs: [.emt, .emtIPad, .sccIPad],
            requiredPermissions: [.viewIncident, .viewMedicalDirectory],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["FieldHospitalView", "FieldHospitalData", "HospitalCapacityRow"],
            linkedFeatures: [.hospitalCapacityView, .medicalOperationalSummary, .medicalCapacityAnalysis]
        ),
        LinkGuardModuleEntitlement(
            id: .personalNotifications,
            displayName: "V0.25 個人通知",
            shell: .mobile,
            allowedAppIDs: [.teamLeader, .teamLeaderIPad, .teamMember, .volunteer, .emt, .emtIPad, .sccIPad],
            requiredPermissions: [.viewIncident, .acknowledgeAlert],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["FieldNotificationView", "PersonalNotification", "message_ack"],
            linkedFeatures: [.alertPush, .alertRead, .sosDetail]
        ),
        LinkGuardModuleEntitlement(
            id: .ceocDashboard,
            displayName: "CEOC/UCC 跨區儀表板",
            shell: .command,
            allowedAppIDs: [.ucc],
            requiredPermissions: [.viewIncident, .coordinateAgency, .manageIncident]
        ),
        LinkGuardModuleEntitlement(
            id: .sccCommand,
            displayName: "SCC 指揮台",
            shell: .command,
            allowedAppIDs: [.scc, .sccIPad],
            requiredPermissions: [.viewIncident, .issueCommand, .manageMap]
        ),
        LinkGuardModuleEntitlement(
            id: .mapOperations,
            displayName: "作戰地圖",
            shell: .command,
            allowedAppIDs: [.ucc, .scc, .sccIPad],
            requiredPermissions: [.viewIncident, .manageMap]
        ),
        LinkGuardModuleEntitlement(
            id: .agencyMessaging,
            displayName: "跨機關通報",
            shell: .command,
            allowedAppIDs: [.ucc, .scc, .sccIPad],
            requiredPermissions: [.viewIncident, .coordinateAgency]
        ),
        LinkGuardModuleEntitlement(
            id: .resourceCoordination,
            displayName: "資源協調",
            shell: .command,
            allowedAppIDs: [.ucc, .scc, .sccIPad],
            requiredPermissions: [.viewIncident, .manageLogistics]
        ),
        LinkGuardModuleEntitlement(
            id: .aarReplay,
            displayName: "AAR 回放",
            shell: .command,
            allowedAppIDs: [.ucc, .scc],
            requiredPermissions: [.viewIncident, .exportAAR]
        ),
        LinkGuardModuleEntitlement(
            id: .backupReplay,
            displayName: "V0.25 USB 備份/回放",
            shell: .command,
            allowedAppIDs: [.ucc, .scc],
            requiredPermissions: [.viewIncident, .exportAAR, .manageBackupReplay],
            sourceVersion: "V0.25/V0.2",
            sourceFeatureNames: ["usb_backup.py", "replay/server.py", "report_generator.py"],
            linkedFeatures: [.aarReplay, .eventLog, .commandCenterRedundancy]
        ),
        LinkGuardModuleEntitlement(
            id: .adminProvisioning,
            displayName: "帳號與裝置 Provisioning",
            shell: .adminProvisioning,
            allowedAppIDs: Set(LinkGuardAppID.allCases),
            requiredPermissions: [.provisionDevice]
        )
    ]

    public static func shell(for device: DeviceIdentity) -> LinkGuardProductShell {
        switch device.appID {
        case .ucc, .scc:
            return .command
        case .sccIPad:
            return .mobile
        case .teamLeader, .teamLeaderIPad, .teamMember, .volunteer, .emt, .emtIPad:
            return .mobile
        }
    }

    public static func snapshot(for session: LoginSession) -> ModuleActivationSnapshot {
        let primaryShell = shell(for: session.device)
        var enabled: [LinkGuardModuleEntitlement] = []
        var hidden: [LinkGuardModuleEntitlement] = []

        for entitlement in entitlements {
            let belongsToPrimaryShell = entitlement.shell == primaryShell
            let isAdminModule = entitlement.shell == .adminProvisioning
            guard belongsToPrimaryShell || isAdminModule else { continue }

            switch entitlement.activationMode(for: session) {
            case .enabled:
                enabled.append(entitlement)
            case .hidden:
                hidden.append(entitlement)
            }
        }

        return ModuleActivationSnapshot(
            sessionID: session.id,
            accountID: session.accountID,
            device: session.device,
            shell: primaryShell,
            enabledModules: enabled.sorted { $0.id.rawValue < $1.id.rawValue },
            hiddenModules: hidden.sorted { $0.id.rawValue < $1.id.rawValue },
            issuedAt: session.issuedAt,
            expiresAt: session.expiresAt
        )
    }
}

public extension LoginSession {
    var moduleActivationSnapshot: ModuleActivationSnapshot {
        ModuleActivationCatalog.snapshot(for: self)
    }
}
