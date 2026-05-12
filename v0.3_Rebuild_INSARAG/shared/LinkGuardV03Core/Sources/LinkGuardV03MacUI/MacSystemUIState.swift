import Foundation
import LinkGuardV03Core

public enum MacSystemUIError: Error, Equatable, Sendable {
    case unsupportedApp(LinkGuardAppID)
}

public struct MacNavigationItem: Identifiable, Hashable, Sendable {
    public var id: String { section.rawValue }
    public var section: ICSSection
    public var title: String
    public var systemImageName: String

    public init(section: ICSSection, title: String, systemImageName: String) {
        self.section = section
        self.title = title
        self.systemImageName = systemImageName
    }
}

public struct MacMetricTile: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var value: String
    public var systemImageName: String
    public var accentName: String

    public init(id: String, title: String, value: String, systemImageName: String, accentName: String) {
        self.id = id
        self.title = title
        self.value = value
        self.systemImageName = systemImageName
        self.accentName = accentName
    }
}

public struct MacInheritedModule: Identifiable, Hashable, Sendable {
    public var id: String { section.rawValue }
    public var section: ICSSection
    public var title: String
    public var inheritedFrom: [String]
    public var enabledPermissions: [LinkGuardPermission]
    public var recordCount: Int
    public var systemImageName: String

    public init(
        section: ICSSection,
        title: String,
        inheritedFrom: [String],
        enabledPermissions: [LinkGuardPermission],
        recordCount: Int,
        systemImageName: String
    ) {
        self.section = section
        self.title = title
        self.inheritedFrom = inheritedFrom
        self.enabledPermissions = enabledPermissions
        self.recordCount = recordCount
        self.systemImageName = systemImageName
    }
}

public struct MacQuickAction: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var permission: LinkGuardPermission
    public var messageType: SyncMessageType?
    public var isEnabled: Bool
    public var systemImageName: String

    public init(
        id: String,
        title: String,
        permission: LinkGuardPermission,
        messageType: SyncMessageType?,
        isEnabled: Bool,
        systemImageName: String
    ) {
        self.id = id
        self.title = title
        self.permission = permission
        self.messageType = messageType
        self.isEnabled = isEnabled
        self.systemImageName = systemImageName
    }
}

public struct MacTransportRouteSummary: Identifiable, Hashable, Sendable {
    public var id: String { messageType.rawValue }
    public var messageType: SyncMessageType
    public var policy: TransportPolicy
    public var canSend: Bool
    public var receives: Bool
    public var relayApps: [LinkGuardAppID]
    public var allowedRecipientApps: Set<LinkGuardAppID>

    public init(
        messageType: SyncMessageType,
        policy: TransportPolicy,
        canSend: Bool,
        receives: Bool,
        relayApps: [LinkGuardAppID],
        allowedRecipientApps: Set<LinkGuardAppID>
    ) {
        self.messageType = messageType
        self.policy = policy
        self.canSend = canSend
        self.receives = receives
        self.relayApps = relayApps
        self.allowedRecipientApps = allowedRecipientApps
    }
}

public struct MacSystemUIState: Sendable {
    public var runtime: LinkGuardAppRuntime
    public var versionInfo: LinkGuardVersionInfo
    public var navigationItems: [MacNavigationItem]
    public var metrics: [MacMetricTile]
    public var inheritedModules: [MacInheritedModule]
    public var quickActions: [MacQuickAction]
    public var transportRoutes: [MacTransportRouteSummary]

    public init(
        runtime: LinkGuardAppRuntime,
        versionInfo: LinkGuardVersionInfo,
        navigationItems: [MacNavigationItem],
        metrics: [MacMetricTile],
        inheritedModules: [MacInheritedModule],
        quickActions: [MacQuickAction],
        transportRoutes: [MacTransportRouteSummary]
    ) {
        self.runtime = runtime
        self.versionInfo = versionInfo
        self.navigationItems = navigationItems
        self.metrics = metrics
        self.inheritedModules = inheritedModules
        self.quickActions = quickActions
        self.transportRoutes = transportRoutes
    }

    public var title: String { runtime.device.appID.rawValue }
    public var subtitle: String { "\(runtime.profile.displayName) / \(runtime.profile.commandAuthority.macDisplayName)" }
}

public enum MacSystemUIFactory {
    public static let supportedMacApps: Set<LinkGuardAppID> = [.ucc, .scc]

    public static func makeRuntime(
        appID: LinkGuardAppID,
        deviceID: LinkGuardID,
        displayName: String? = nil,
        snapshot: OperationSnapshot = OperationSnapshot()
    ) throws -> LinkGuardAppRuntime {
        guard supportedMacApps.contains(appID) else {
            throw MacSystemUIError.unsupportedApp(appID)
        }

        return LinkGuardAppRuntime(
            device: DeviceIdentity(
                id: deviceID,
                appID: appID,
                platform: .mac,
                displayName: displayName ?? appID.rawValue
            ),
            snapshot: snapshot
        )
    }

    public static func makeState(
        appID: LinkGuardAppID,
        deviceID: LinkGuardID,
        displayName: String? = nil,
        snapshot: OperationSnapshot = OperationSnapshot(),
        versionInfo: LinkGuardVersionInfo = .current
    ) throws -> MacSystemUIState {
        let runtime = try makeRuntime(appID: appID, deviceID: deviceID, displayName: displayName, snapshot: snapshot)
        return try makeState(for: runtime, versionInfo: versionInfo)
    }

    public static func makeState(
        for runtime: LinkGuardAppRuntime,
        versionInfo: LinkGuardVersionInfo = .current
    ) throws -> MacSystemUIState {
        guard supportedMacApps.contains(runtime.device.appID), runtime.device.platform == .mac else {
            throw MacSystemUIError.unsupportedApp(runtime.device.appID)
        }

        let sections = orderedSections(for: runtime)
        return MacSystemUIState(
            runtime: runtime,
            versionInfo: versionInfo,
            navigationItems: sections.map { MacNavigationItem(section: $0, title: $0.macDisplayName, systemImageName: $0.macSystemImageName) },
            metrics: metrics(for: runtime),
            inheritedModules: sections.map { module(for: $0, runtime: runtime) },
            quickActions: quickActions(for: runtime),
            transportRoutes: transportRoutes(for: runtime)
        )
    }

    private static func orderedSections(for runtime: LinkGuardAppRuntime) -> [ICSSection] {
        var seen = Set<ICSSection>()
        return (runtime.blueprint.primarySections + runtime.profile.defaultSections).filter { section in
            guard seen.contains(section) == false else { return false }
            seen.insert(section)
            return true
        }
    }

    private static func metrics(for runtime: LinkGuardAppRuntime) -> [MacMetricTile] {
        let snapshot = runtime.snapshot
        var tiles = [
            MacMetricTile(id: "incidents", title: "Incidents", value: String(snapshot.incidents.count), systemImageName: "scope", accentName: "blue"),
            MacMetricTile(id: "worksites", title: "Worksites", value: String(snapshot.worksites.count), systemImageName: "mappin.and.ellipse", accentName: "orange"),
            MacMetricTile(id: "tasks", title: "Open Tasks", value: String(openTaskCount(in: snapshot)), systemImageName: "checklist", accentName: "green"),
            MacMetricTile(id: "alerts", title: "Alerts", value: String(snapshot.alerts.count), systemImageName: "exclamationmark.triangle", accentName: "red"),
            MacMetricTile(id: "queue", title: "Outbound", value: String(runtime.outboundQueue.entries.count), systemImageName: "arrow.up.arrow.down", accentName: "purple")
        ]

        if runtime.profile.medicalAccess >= .summary {
            tiles.append(MacMetricTile(id: "medical", title: "Med Ops", value: String(snapshot.evacuationRequests.count + snapshot.hospitalCapacities.count), systemImageName: "cross.case", accentName: "teal"))
        }

        if runtime.profile.allows(.manageFinance) {
            tiles.append(MacMetricTile(id: "finance", title: "Finance", value: String(snapshot.purchaseRequests.count + snapshot.personnelHours.count), systemImageName: "creditcard", accentName: "indigo"))
        }

        tiles.append(MacMetricTile(id: "aar", title: "AAR", value: String(snapshot.auditEvents.count + snapshot.decisionRecords.count), systemImageName: "clock.arrow.circlepath", accentName: "gray"))
        return tiles
    }

    private static func module(for section: ICSSection, runtime: LinkGuardAppRuntime) -> MacInheritedModule {
        let permissions = permissionsForSection(section).filter { runtime.profile.allows($0) }
        return MacInheritedModule(
            section: section,
            title: section.macDisplayName,
            inheritedFrom: inheritedSources(for: section),
            enabledPermissions: permissions,
            recordCount: recordCount(for: section, snapshot: runtime.snapshot),
            systemImageName: section.macSystemImageName
        )
    }

    private static func quickActions(for runtime: LinkGuardAppRuntime) -> [MacQuickAction] {
        actionDefinitions.compactMap { definition in
            guard runtime.profile.allows(definition.permission) else { return nil }
            let isEnabled = definition.messageType.map { runtime.canSend($0) } ?? true
            return MacQuickAction(
                id: definition.id,
                title: definition.title,
                permission: definition.permission,
                messageType: definition.messageType,
                isEnabled: isEnabled,
                systemImageName: definition.systemImageName
            )
        }
    }

    private static func transportRoutes(for runtime: LinkGuardAppRuntime) -> [MacTransportRouteSummary] {
        let relevantMessageTypes: [SyncMessageType] = [
            .commandUpsert,
            .taskUpsert,
            .alertUpsert,
            .evacuationRequestUpsert,
            .purchaseRequestUpsert,
            .decisionRecordUpsert,
            .auditEventAppend
        ]

        return relevantMessageTypes.map { messageType in
            let routeProbe = SyncEnvelope(
                id: LinkGuardID("ROUTE-\(messageType.rawValue)"),
                messageType: messageType,
                sourceAppID: runtime.device.appID,
                sourceDeviceID: runtime.device.id,
                priority: AppLogicGate.defaultPriority(for: messageType),
                createdAt: Date(timeIntervalSince1970: 0),
                idempotencyKey: "route-\(runtime.device.appID.rawValue)-\(messageType.rawValue)",
                payloadData: Data()
            )
            let route = TransportTopology.route(for: routeProbe)
            return MacTransportRouteSummary(
                messageType: messageType,
                policy: route.policy,
                canSend: runtime.canSend(messageType),
                receives: route.allowedRecipientApps.contains(runtime.device.appID),
                relayApps: route.relayApps,
                allowedRecipientApps: route.allowedRecipientApps
            )
        }
    }

    private static func openTaskCount(in snapshot: OperationSnapshot) -> Int {
        snapshot.tasks.values.filter { task in
            task.status != .completed && task.status != .cancelled
        }.count
    }

    private static func recordCount(for section: ICSSection, snapshot: OperationSnapshot) -> Int {
        switch section {
        case .command:
            return snapshot.commands.count + snapshot.alerts.count + snapshot.roleAssignments.count
        case .operations:
            return snapshot.worksites.count + snapshot.tasks.count + snapshot.mapFeatures.count
        case .planning:
            return snapshot.incidents.count + snapshot.sectors.count
        case .logistics:
            return snapshot.evacuationRequests.count + snapshot.hospitalCapacities.count
        case .finance:
            return snapshot.purchaseRequests.count + snapshot.personnelHours.count
        case .medical:
            return snapshot.evacuationRequests.count + snapshot.hospitalCapacities.count
        case .afterActionReview:
            return snapshot.auditEvents.count + snapshot.decisionRecords.count
        }
    }

    private static func permissionsForSection(_ section: ICSSection) -> [LinkGuardPermission] {
        switch section {
        case .command:
            return [.issueCommand, .assignRole, .forceAcknowledgeAlert]
        case .operations:
            return [.manageIncident, .manageMap, .updateTask]
        case .planning:
            return [.manageIncident, .submitReport]
        case .logistics:
            return [.manageLogistics, .provisionDevice]
        case .finance:
            return [.manageFinance]
        case .medical:
            return [.viewMedicalSummary, .manageMedicalPatient]
        case .afterActionReview:
            return [.exportAAR]
        }
    }

    private static func inheritedSources(for section: ICSSection) -> [String] {
        var sources = ["AppBlueprintCatalog", "RoleProfileCatalog", "OperationSnapshot"]
        if section == .command || section == .operations || section == .medical || section == .finance || section == .afterActionReview {
            sources.append("TransportTopology")
        }
        return sources
    }

    private static let actionDefinitions: [(id: String, title: String, permission: LinkGuardPermission, messageType: SyncMessageType?, systemImageName: String)] = [
        ("issue-command", "Issue Command", .issueCommand, .commandUpsert, "paperplane"),
        ("publish-alert", "Publish Alert", .issueCommand, .alertUpsert, "exclamationmark.triangle"),
        ("assign-role", "Assign Role", .assignRole, .roleAssignmentUpsert, "person.badge.plus"),
        ("update-task", "Update Task", .updateTask, .taskUpsert, "checklist"),
        ("map-feature", "Map Feature", .manageMap, .mapFeatureUpsert, "map"),
        ("finance", "Finance Record", .manageFinance, .purchaseRequestUpsert, "creditcard"),
        ("export-aar", "Export AAR", .exportAAR, .decisionRecordUpsert, "archivebox")
    ]
}

public extension ICSSection {
    var macDisplayName: String {
        switch self {
        case .command:
            return "Command"
        case .operations:
            return "Operations"
        case .planning:
            return "Planning"
        case .logistics:
            return "Logistics"
        case .finance:
            return "Finance"
        case .medical:
            return "Medical"
        case .afterActionReview:
            return "AAR"
        }
    }

    var macSystemImageName: String {
        switch self {
        case .command:
            return "person.3.sequence"
        case .operations:
            return "map"
        case .planning:
            return "calendar.badge.clock"
        case .logistics:
            return "shippingbox"
        case .finance:
            return "creditcard"
        case .medical:
            return "cross.case"
        case .afterActionReview:
            return "clock.arrow.circlepath"
        }
    }
}

private extension CommandAuthorityLevel {
    var macDisplayName: String {
        switch self {
        case .none:
            return "No command authority"
        case .selfReport:
            return "Self report"
        case .team:
            return "Team command"
        case .sector:
            return "Sector command"
        case .incident:
            return "Incident command"
        case .global:
            return "Global command"
        }
    }
}
