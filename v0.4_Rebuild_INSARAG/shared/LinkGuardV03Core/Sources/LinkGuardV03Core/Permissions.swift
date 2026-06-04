import Foundation

public enum LinkGuardPermission: String, Codable, CaseIterable, Sendable {
    case viewIncident
    case manageIncident
    case assignRole
    case issueCommand
    case coordinateAgency
    case acknowledgeAlert
    case forceAcknowledgeAlert
    case manageMap
    case updateTask
    case submitReport
    case sendSOS
    case viewMedicalSummary
    case viewMedicalDetails
    case manageMedicalPatient
    case managePatientReport
    case manageEvacuation
    case manageLogistics
    case manageFinance
    case exportAAR
    case monitorRadio
    case provisionDevice
}

public struct RoleProfile: Codable, Hashable, Sendable {
    public var appID: LinkGuardAppID
    public var displayName: String
    public var defaultSections: [ICSSection]
    public var commandAuthority: CommandAuthorityLevel
    public var medicalAccess: MedicalAccessLevel
    public var permissions: Set<LinkGuardPermission>

    public init(
        appID: LinkGuardAppID,
        displayName: String,
        defaultSections: [ICSSection],
        commandAuthority: CommandAuthorityLevel,
        medicalAccess: MedicalAccessLevel,
        permissions: Set<LinkGuardPermission>
    ) {
        self.appID = appID
        self.displayName = displayName
        self.defaultSections = defaultSections
        self.commandAuthority = commandAuthority
        self.medicalAccess = medicalAccess
        self.permissions = permissions
    }

    public func allows(_ permission: LinkGuardPermission) -> Bool {
        permissions.contains(permission)
    }
}

public enum RoleProfileCatalog {
    public static let profiles: [LinkGuardAppID: RoleProfile] = {
        let uccPermissions = Set(LinkGuardPermission.allCases)
        let sccPermissions = Set<LinkGuardPermission>([
            .viewIncident,
            .manageIncident,
            .assignRole,
            .issueCommand,
            .coordinateAgency,
            .acknowledgeAlert,
            .forceAcknowledgeAlert,
            .manageMap,
            .updateTask,
            .submitReport,
            .sendSOS,
            .viewMedicalSummary,
            .managePatientReport,
            .manageEvacuation,
            .manageLogistics,
            .exportAAR,
            .monitorRadio,
            .provisionDevice
        ])
        let teamLeaderPermissions = Set<LinkGuardPermission>([
            .viewIncident,
            .manageIncident,
            .issueCommand,
            .acknowledgeAlert,
            .manageMap,
            .updateTask,
            .submitReport,
            .sendSOS,
            .viewMedicalSummary,
            .managePatientReport,
            .monitorRadio
        ])
        let teamMemberPermissions = Set<LinkGuardPermission>([
            .viewIncident,
            .acknowledgeAlert,
            .updateTask,
            .submitReport,
            .sendSOS,
            .managePatientReport
        ])
        let volunteerPermissions = Set<LinkGuardPermission>([
            .viewIncident,
            .acknowledgeAlert,
            .submitReport,
            .sendSOS
        ])
        let emtPermissions = Set<LinkGuardPermission>([
            .viewIncident,
            .acknowledgeAlert,
            .sendSOS,
            .viewMedicalSummary,
            .viewMedicalDetails,
            .manageMedicalPatient,
            .managePatientReport,
            .manageEvacuation,
            .submitReport
        ])

        return [
            .ucc: RoleProfile(
                appID: .ucc,
                displayName: "UCC",
                defaultSections: [.command, .operations, .planning, .logistics, .finance, .afterActionReview],
                commandAuthority: .global,
                medicalAccess: .operational,
                permissions: uccPermissions.subtracting([.viewMedicalDetails, .manageMedicalPatient, .managePatientReport, .manageEvacuation])
            ),
            .scc: RoleProfile(
                appID: .scc,
                displayName: "SCC",
                defaultSections: [.command, .operations, .planning, .logistics, .afterActionReview],
                commandAuthority: .incident,
                medicalAccess: .summary,
                permissions: sccPermissions
            ),
            .sccIPad: RoleProfile(
                appID: .sccIPad,
                displayName: "SCC iPad",
                defaultSections: [.command, .operations, .planning, .logistics],
                commandAuthority: .incident,
                medicalAccess: .summary,
                permissions: sccPermissions
            ),
            .teamLeader: RoleProfile(
                appID: .teamLeader,
                displayName: "TL",
                defaultSections: [.operations, .planning],
                commandAuthority: .team,
                medicalAccess: .summary,
                permissions: teamLeaderPermissions
            ),
            .teamLeaderIPad: RoleProfile(
                appID: .teamLeaderIPad,
                displayName: "TL iPad",
                defaultSections: [.operations, .planning],
                commandAuthority: .team,
                medicalAccess: .summary,
                permissions: teamLeaderPermissions
            ),
            .teamMember: RoleProfile(
                appID: .teamMember,
                displayName: "TE",
                defaultSections: [.operations],
                commandAuthority: .selfReport,
                medicalAccess: .none,
                permissions: teamMemberPermissions
            ),
            .volunteer: RoleProfile(
                appID: .volunteer,
                displayName: "VO",
                defaultSections: [.operations],
                commandAuthority: .selfReport,
                medicalAccess: .none,
                permissions: volunteerPermissions
            ),
            .emt: RoleProfile(
                appID: .emt,
                displayName: "EMT",
                defaultSections: [.medical],
                commandAuthority: .selfReport,
                medicalAccess: .fullClinical,
                permissions: emtPermissions
            ),
            .emtIPad: RoleProfile(
                appID: .emtIPad,
                displayName: "EMT iPad",
                defaultSections: [.medical],
                commandAuthority: .selfReport,
                medicalAccess: .fullClinical,
                permissions: emtPermissions
            )
        ]
    }()

    public static func profile(for appID: LinkGuardAppID) -> RoleProfile {
        guard let profile = profiles[appID] else {
            preconditionFailure("Missing role profile for \(appID.rawValue)")
        }
        return profile
    }
}
