import Foundation

public enum HomeSurface: String, Codable, CaseIterable, Sendable {
    case globalCommand
    case sectorCommand
    case teamBriefing
    case taskList
    case volunteerSafety
    case medicalTriage
}

public struct AppBlueprint: Codable, Hashable, Sendable {
    public var appID: LinkGuardAppID
    public var platform: AppPlatform
    public var homeSurface: HomeSurface
    public var requiredPermissions: Set<LinkGuardPermission>
    public var primarySections: [ICSSection]

    public init(
        appID: LinkGuardAppID,
        platform: AppPlatform,
        homeSurface: HomeSurface,
        requiredPermissions: Set<LinkGuardPermission>,
        primarySections: [ICSSection]
    ) {
        self.appID = appID
        self.platform = platform
        self.homeSurface = homeSurface
        self.requiredPermissions = requiredPermissions
        self.primarySections = primarySections
    }

    public func validate(against profile: RoleProfile) -> Bool {
        profile.appID == appID && requiredPermissions.isSubset(of: profile.permissions)
    }
}

public enum AppBlueprintCatalog {
    public static let blueprints: [LinkGuardAppID: AppBlueprint] = [
        .ucc: AppBlueprint(
            appID: .ucc,
            platform: .mac,
            homeSurface: .globalCommand,
            requiredPermissions: [.issueCommand, .assignRole, .manageIncident, .exportAAR],
            primarySections: [.command, .operations, .planning, .logistics, .finance]
        ),
        .scc: AppBlueprint(
            appID: .scc,
            platform: .mac,
            homeSurface: .sectorCommand,
            requiredPermissions: [.issueCommand, .manageMap, .manageLogistics],
            primarySections: [.command, .operations, .planning, .logistics]
        ),
        .sccIPad: AppBlueprint(
            appID: .sccIPad,
            platform: .iPad,
            homeSurface: .sectorCommand,
            requiredPermissions: [.issueCommand, .manageMap, .manageLogistics],
            primarySections: [.command, .operations, .planning, .logistics]
        ),
        .teamLeader: AppBlueprint(
            appID: .teamLeader,
            platform: .iPhone,
            homeSurface: .teamBriefing,
            requiredPermissions: [.issueCommand, .updateTask, .submitReport],
            primarySections: [.operations, .planning]
        ),
        .teamLeaderIPad: AppBlueprint(
            appID: .teamLeaderIPad,
            platform: .iPad,
            homeSurface: .teamBriefing,
            requiredPermissions: [.issueCommand, .manageMap, .updateTask],
            primarySections: [.operations, .planning]
        ),
        .teamMember: AppBlueprint(
            appID: .teamMember,
            platform: .iPhone,
            homeSurface: .taskList,
            requiredPermissions: [.updateTask, .submitReport, .sendSOS],
            primarySections: [.operations]
        ),
        .volunteer: AppBlueprint(
            appID: .volunteer,
            platform: .iPhone,
            homeSurface: .volunteerSafety,
            requiredPermissions: [.submitReport, .sendSOS],
            primarySections: [.operations]
        ),
        .emt: AppBlueprint(
            appID: .emt,
            platform: .iPhone,
            homeSurface: .medicalTriage,
            requiredPermissions: [.manageMedicalPatient, .viewMedicalDetails, .submitReport],
            primarySections: [.medical]
        ),
        .emtIPad: AppBlueprint(
            appID: .emtIPad,
            platform: .iPad,
            homeSurface: .medicalTriage,
            requiredPermissions: [.manageMedicalPatient, .viewMedicalDetails, .submitReport],
            primarySections: [.medical]
        )
    ]

    public static func blueprint(for appID: LinkGuardAppID) -> AppBlueprint {
        guard let blueprint = blueprints[appID] else {
            preconditionFailure("Missing app blueprint for \(appID.rawValue)")
        }
        return blueprint
    }
}
