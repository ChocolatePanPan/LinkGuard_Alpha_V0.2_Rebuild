import Foundation
import LinkGuardV03Core

public enum MacSystemUIError: Error, Equatable, Sendable {
    case unsupportedApp(LinkGuardAppID)
    case unsupportedPlatform(AppPlatform)
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

public struct MacICSSectionLane: Identifiable, Hashable, Sendable {
    public var id: String { section.rawValue }
    public var section: ICSSection
    public var title: String
    public var roleInUCC: String
    public var primaryPositions: [ICSPosition]
    public var primaryPermissions: [LinkGuardPermission]
    public var authorityBoundary: String
    public var systemImageName: String

    public init(
        section: ICSSection,
        title: String,
        roleInUCC: String,
        primaryPositions: [ICSPosition],
        primaryPermissions: [LinkGuardPermission],
        authorityBoundary: String,
        systemImageName: String
    ) {
        self.section = section
        self.title = title
        self.roleInUCC = roleInUCC
        self.primaryPositions = primaryPositions
        self.primaryPermissions = primaryPermissions
        self.authorityBoundary = authorityBoundary
        self.systemImageName = systemImageName
    }
}

public struct MacICSBoundaryRule: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct MacUCCICSArchitecture: Identifiable, Hashable, Sendable {
    public var id: String { "ucc-ics-architecture" }
    public var title: String
    public var commandAuthority: CommandAuthorityLevel
    public var coordinationRole: String
    public var lanes: [MacICSSectionLane]
    public var boundaryRules: [MacICSBoundaryRule]

    public init(
        title: String,
        commandAuthority: CommandAuthorityLevel,
        coordinationRole: String,
        lanes: [MacICSSectionLane],
        boundaryRules: [MacICSBoundaryRule]
    ) {
        self.title = title
        self.commandAuthority = commandAuthority
        self.coordinationRole = coordinationRole
        self.lanes = lanes
        self.boundaryRules = boundaryRules
    }
}

public struct MacSOSAlertItem: Identifiable, Hashable, Sendable {
    public var id: LinkGuardID
    public var dangerType: SOSDangerType
    public var reporterDeviceID: LinkGuardID
    public var reporterAppID: LinkGuardAppID
    public var location: GeoCoordinate
    public var status: SOSStatus
    public var createdAt: Date
    public var note: String?

    public init(report: SOSReport) {
        self.id = report.id
        self.dangerType = report.dangerType
        self.reporterDeviceID = report.reporterDeviceID
        self.reporterAppID = report.reporterAppID
        self.location = report.location
        self.status = report.status
        self.createdAt = report.createdAt
        self.note = report.note
    }
}

public struct MacSystemUIState: Sendable {
    public var runtime: LinkGuardAppRuntime
    public var loginSession: LoginSession?
    public var settingsInfo: LinkGuardAppSettingsInfo
    public var navigationItems: [MacNavigationItem]
    public var metrics: [MacMetricTile]
    public var inheritedModules: [MacInheritedModule]
    public var quickActions: [MacQuickAction]
    public var transportRoutes: [MacTransportRouteSummary]
    public var teamCapabilityReports: [USARTeamCapabilityReport]
    public var uccICSArchitecture: MacUCCICSArchitecture?

    public init(
        runtime: LinkGuardAppRuntime,
        loginSession: LoginSession? = nil,
        settingsInfo: LinkGuardAppSettingsInfo,
        navigationItems: [MacNavigationItem],
        metrics: [MacMetricTile],
        inheritedModules: [MacInheritedModule],
        quickActions: [MacQuickAction],
        transportRoutes: [MacTransportRouteSummary],
        teamCapabilityReports: [USARTeamCapabilityReport],
        uccICSArchitecture: MacUCCICSArchitecture? = nil
    ) {
        self.runtime = runtime
        self.loginSession = loginSession
        self.settingsInfo = settingsInfo
        self.navigationItems = navigationItems
        self.metrics = metrics
        self.inheritedModules = inheritedModules
        self.quickActions = quickActions
        self.transportRoutes = transportRoutes
        self.teamCapabilityReports = teamCapabilityReports
        self.uccICSArchitecture = uccICSArchitecture
    }

    public var title: String { runtime.device.appID.rawValue }
    public var subtitle: String { "\(runtime.profile.displayName) / \(runtime.profile.commandAuthority.macDisplayName)" }
    public var versionInfo: LinkGuardVersionInfo { settingsInfo.versionInfo }
    public var settingsItems: [LinkGuardAppSettingsItem] { settingsInfo.items }
    public var sosAlertItems: [MacSOSAlertItem] {
        runtime.snapshot.sosReports.values
            .sorted { $0.createdAt > $1.createdAt }
            .map(MacSOSAlertItem.init(report:))
    }

    @discardableResult
    public mutating func receive(_ batch: SyncTransportBatch, receivedAt: Date = Date()) -> SyncTransportResponse {
        receive(batch.envelopes, receivedAt: receivedAt)
    }

    @discardableResult
    public mutating func receive(_ envelopes: [SyncEnvelope], receivedAt: Date = Date()) -> SyncTransportResponse {
        let receipts = envelopes.map { envelope in
            let route = TransportTopology.route(for: envelope)
            guard route.allowedRecipientApps.contains(runtime.device.appID) else {
                return SyncTransportReceipt(
                    envelopeID: envelope.id,
                    accepted: false,
                    receivedAt: receivedAt,
                    error: "message is not routed to \(runtime.device.appID.rawValue)"
                )
            }

            do {
                try runtime.receive(envelope)
                return SyncTransportReceipt(envelopeID: envelope.id, accepted: true, receivedAt: receivedAt)
            } catch {
                return SyncTransportReceipt(
                    envelopeID: envelope.id,
                    accepted: false,
                    receivedAt: receivedAt,
                    error: String(describing: error)
                )
            }
        }
        refreshDerivedState()
        return SyncTransportResponse(receipts: receipts)
    }

    private mutating func refreshDerivedState() {
        let selectedSession = loginSession
        guard var refreshed = try? MacSystemUIFactory.makeState(for: runtime, versionInfo: versionInfo) else { return }
        refreshed.loginSession = selectedSession
        self = refreshed
    }
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
            settingsInfo: LinkGuardAppSettingsInfo(device: runtime.device, versionInfo: versionInfo),
            navigationItems: sections.map { MacNavigationItem(section: $0, title: $0.macDisplayName, systemImageName: $0.macSystemImageName) },
            metrics: metrics(for: runtime),
            inheritedModules: sections.map { module(for: $0, runtime: runtime) },
            quickActions: quickActions(for: runtime),
            transportRoutes: transportRoutes(for: runtime),
            teamCapabilityReports: teamCapabilityReports(for: runtime.snapshot),
            uccICSArchitecture: uccICSArchitecture(for: runtime, sections: sections)
        )
    }

    public static func makeAuthenticatedState(
        session: LoginSession,
        snapshot: OperationSnapshot = OperationSnapshot(),
        versionInfo: LinkGuardVersionInfo = .current
    ) throws -> MacSystemUIState {
        guard supportedMacApps.contains(session.device.appID) else {
            throw MacSystemUIError.unsupportedApp(session.device.appID)
        }
        guard session.device.platform == .mac else {
            throw MacSystemUIError.unsupportedPlatform(session.device.platform)
        }

        let runtime = LinkGuardAppRuntime(device: session.device, snapshot: snapshot)
        let baseState = try makeState(for: runtime, versionInfo: versionInfo)
        return applySessionConstraints(baseState, session: session)
    }

    public static func selectIdentityAndMakeState(
        directory: AccountDirectory,
        identifier: String,
        appID: LinkGuardAppID,
        deviceID: LinkGuardID,
        displayName: String? = nil,
        selectedAt: Date,
        sessionID: LinkGuardID = .generated(prefix: "IDENTITY"),
        snapshot: OperationSnapshot = OperationSnapshot(),
        versionInfo: LinkGuardVersionInfo = .current
    ) throws -> (session: LoginSession, state: MacSystemUIState) {
        guard supportedMacApps.contains(appID) else {
            throw MacSystemUIError.unsupportedApp(appID)
        }

        let account = try directory.account(for: identifier)
        guard account.status == .active else {
            throw AccountAccessError.inactiveAccount(account.id)
        }
        guard account.canUse(appID: appID) else {
            throw AccountAccessError.appNotAllowed(accountID: account.id, appID: appID)
        }

        let device = DeviceIdentity(
            id: deviceID,
            appID: appID,
            platform: .mac,
            displayName: displayName ?? appID.rawValue
        )
        let profile = RoleProfileCatalog.profile(for: appID)
        let session = LoginSession(
            id: sessionID,
            accountID: account.id,
            personID: account.personID,
            displayName: account.displayName,
            device: device,
            position: account.defaultPosition,
            profile: profile,
            issuedAt: selectedAt,
            permissions: profile.permissions
        )
        var state = try makeState(appID: appID, deviceID: deviceID, displayName: displayName, snapshot: snapshot, versionInfo: versionInfo)
        state.loginSession = session
        return (session: session, state: state)
    }

    public static func loginAndMakeState(
        directory: inout AccountDirectory,
        identifier: String,
        credentialDigest: String,
        appID: LinkGuardAppID,
        deviceID: LinkGuardID,
        displayName: String? = nil,
        issuedAt: Date,
        expiresAt: Date? = nil,
        sessionID: LinkGuardID = .generated(prefix: "SESSION"),
        snapshot: OperationSnapshot = OperationSnapshot(),
        versionInfo: LinkGuardVersionInfo = .current
    ) throws -> (session: LoginSession, state: MacSystemUIState) {
        guard supportedMacApps.contains(appID) else {
            throw MacSystemUIError.unsupportedApp(appID)
        }

        let device = DeviceIdentity(
            id: deviceID,
            appID: appID,
            platform: .mac,
            displayName: displayName ?? appID.rawValue
        )

        let session = try directory.login(
            identifier: identifier,
            credentialDigest: credentialDigest,
            device: device,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            sessionID: sessionID
        )

        let state = try makeAuthenticatedState(session: session, snapshot: snapshot, versionInfo: versionInfo)
        return (session: session, state: state)
    }

    private static func applySessionConstraints(_ state: MacSystemUIState, session: LoginSession) -> MacSystemUIState {
        var constrained = state
        constrained.loginSession = session

        constrained.inheritedModules = constrained.inheritedModules.map { module in
            var copy = module
            copy.enabledPermissions = module.enabledPermissions.filter { session.permissions.contains($0) }
            return copy
        }

        constrained.quickActions = constrained.quickActions.map { action in
            var copy = action
            let hasActionPermission = session.permissions.contains(action.permission)
            let hasMessagePermission: Bool
            if let messageType = action.messageType, let required = AppLogicGate.requiredPermission(for: messageType) {
                hasMessagePermission = session.permissions.contains(required)
            } else {
                hasMessagePermission = true
            }
            copy.isEnabled = copy.isEnabled && hasActionPermission && hasMessagePermission
            return copy
        }

        constrained.transportRoutes = constrained.transportRoutes.map { route in
            var copy = route
            if let required = AppLogicGate.requiredPermission(for: route.messageType), session.permissions.contains(required) == false {
                copy.canSend = false
            }
            return copy
        }

        return constrained
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
            MacMetricTile(id: "incidents", title: "災害事件", value: String(snapshot.incidents.count), systemImageName: "building.2", accentName: "blue"),
            MacMetricTile(id: "worksites", title: "分區工址", value: String(snapshot.worksites.count), systemImageName: "map.fill", accentName: "orange"),
            MacMetricTile(id: "tasks", title: "進行任務", value: String(openTaskCount(in: snapshot)), systemImageName: "checklist", accentName: "green"),
            MacMetricTile(id: "team-capability", title: "隊伍概況", value: String(snapshot.teamCapabilityReports.count), systemImageName: "person.3.sequence.fill", accentName: "teal"),
            MacMetricTile(id: "alerts", title: "緊急警報", value: String(snapshot.alerts.count + snapshot.sosReports.count), systemImageName: "exclamationmark.triangle.fill", accentName: "red"),
            MacMetricTile(id: "queue", title: "同步佇列", value: String(runtime.outboundQueue.entries.count), systemImageName: "arrow.up.arrow.down", accentName: "purple")
        ]

        if runtime.profile.medicalAccess >= .summary {
            tiles.append(MacMetricTile(id: "medical", title: "傷患預警", value: String(snapshot.evacuationRequests.count + snapshot.hospitalCapacities.count), systemImageName: "heart.text.square", accentName: "teal"))
        }

        if runtime.profile.allows(.manageFinance) {
            tiles.append(MacMetricTile(id: "finance", title: "統計儀表板", value: String(snapshot.purchaseRequests.count + snapshot.personnelHours.count), systemImageName: "chart.bar.xaxis", accentName: "indigo"))
        }

        tiles.append(MacMetricTile(id: "aar", title: "事件日誌", value: String(snapshot.auditEvents.count + snapshot.decisionRecords.count), systemImageName: "clock.arrow.circlepath", accentName: "gray"))
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
            .personnelStatusUpsert,
            .teamCapabilityReportUpsert,
            .photoReportUpsert,
            .disasterReportUpsert,
            .safetyZoneUpsert,
            .groupChatMessageAppend,
            .voiceReportAppend,
            .alertUpsert,
            .sosReportUpsert,
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

    private static func uccICSArchitecture(for runtime: LinkGuardAppRuntime, sections: [ICSSection]) -> MacUCCICSArchitecture? {
        guard runtime.device.appID == .ucc else { return nil }
        let lanes = sections.map { section in
            MacICSSectionLane(
                section: section,
                title: section.macDisplayName,
                roleInUCC: uccRoleDescription(for: section),
                primaryPositions: uccPositions(for: section),
                primaryPermissions: permissionsForSection(section).filter { runtime.profile.allows($0) },
                authorityBoundary: uccAuthorityBoundary(for: section),
                systemImageName: section.macSystemImageName
            )
        }

        return MacUCCICSArchitecture(
            title: "UCC ICS 架構",
            commandAuthority: runtime.profile.commandAuthority,
            coordinationRole: "跨災區協調、外部資源整合、資訊管理與 SCC 狀態監控",
            lanes: lanes,
            boundaryRules: [
                MacICSBoundaryRule(
                    id: "scc-tactical-authority",
                    title: "SCC 保留現場戰術權",
                    detail: "UCC 監控跨區目標與資源缺口；分區、worksite、入退場與現場安全由 SCC 主責。"
                ),
                MacICSBoundaryRule(
                    id: "medical-operational-summary",
                    title: "醫療只上收營運摘要",
                    detail: "UCC 讀取後送、醫院容量與醫療量能；完整臨床病歷留在 EMT 授權邊界。"
                ),
                MacICSBoundaryRule(
                    id: "audit-source-of-truth",
                    title: "AAR 全端留痕",
                    detail: "每個命令、回報、同步收據與決策都進入 audit trail，UCC 負責跨區彙整。"
                )
            ]
        )
    }

    private static func openTaskCount(in snapshot: OperationSnapshot) -> Int {
        snapshot.tasks.values.filter { task in
            task.status != .completed && task.status != .cancelled
        }.count
    }

    private static func teamCapabilityReports(for snapshot: OperationSnapshot) -> [USARTeamCapabilityReport] {
        snapshot.teamCapabilityReports.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func recordCount(for section: ICSSection, snapshot: OperationSnapshot) -> Int {
        switch section {
        case .command:
            return snapshot.commands.count + snapshot.alerts.count + snapshot.sosReports.count + snapshot.roleAssignments.count
        case .operations:
            return snapshot.subSectors.count + snapshot.worksites.count + snapshot.tasks.count + snapshot.mapFeatures.count + snapshot.personnelStatusReports.count + snapshot.teamCapabilityReports.count + snapshot.photoReports.count + snapshot.disasterReports.count + snapshot.safetyZones.count + snapshot.safetyEntryLogs.count
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
            return [.viewMedicalSummary, .managePatientReport, .manageEvacuation, .manageMedicalPatient]
        case .afterActionReview:
            return [.exportAAR]
        }
    }

    private static func uccRoleDescription(for section: ICSSection) -> String {
        switch section {
        case .command:
            return "全局目標、跨中心指揮權限、對外協調與警報發布"
        case .operations:
            return "跨區資源調度、SCC 戰情監控、重大任務與 SOS 升級"
        case .planning:
            return "IAP 週期、情資彙整、災情統計與作戰節奏"
        case .logistics:
            return "通訊、裝備、電力、交通、LoRa/中繼與補給支援"
        case .finance:
            return "工時、採購、成本、行政文件與災後請款資料"
        case .medical:
            return "後送、醫院容量、醫療量能與跨區 EMT 支援摘要"
        case .afterActionReview:
            return "事件時間線、決策紀錄、證據包與復盤匯出"
        }
    }

    private static func uccPositions(for section: ICSSection) -> [ICSPosition] {
        switch section {
        case .command:
            return [.incidentCommander, .liaisonOfficer, .publicInformationOfficer, .safetyOfficer]
        case .operations:
            return [.operationsSectionChief, .sectorCommander, .teamLeader]
        case .planning:
            return [.planningSectionChief]
        case .logistics:
            return [.logisticsSectionChief]
        case .finance:
            return [.financeSectionChief]
        case .medical:
            return [.emtLead, .emt]
        case .afterActionReview:
            return [.incidentCommander, .planningSectionChief]
        }
    }

    private static func uccAuthorityBoundary(for section: ICSSection) -> String {
        switch section {
        case .command:
            return "UCC 主責跨區與外部協調；SCC 主責現場命令落地。"
        case .operations:
            return "UCC 看全區與跨區缺口；SCC/TL 主責現場任務派遣。"
        case .planning:
            return "UCC 匯整 IAP 與情資；SCC 維護現場 operational period 細節。"
        case .logistics:
            return "UCC 協調跨區資源；SCC 管現場補給、通訊與中繼。"
        case .finance:
            return "UCC 主責彙整；現場端只提供必要工時與成本事件。"
        case .medical:
            return "UCC 只看營運摘要；EMT 保留完整 clinical data。"
        case .afterActionReview:
            return "UCC 彙整跨區復盤；各端都必須保留原始 audit event。"
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
        ("issue-command", "指揮決策", .issueCommand, .commandUpsert, "brain.head.profile"),
        ("publish-alert", "PWS 警報", .issueCommand, .alertUpsert, "exclamationmark.triangle.fill"),
        ("send-sos", "SOS", .sendSOS, .sosReportUpsert, "location.fill.viewfinder"),
        ("assign-role", "人員配置", .assignRole, .roleAssignmentUpsert, "person.badge.plus"),
        ("update-task", "任務更新", .updateTask, .taskUpsert, "checklist"),
        ("map-feature", "分區地圖", .manageMap, .mapFeatureUpsert, "map.fill"),
        ("safety-zone", "安全管制", .manageMap, .safetyZoneUpsert, "shield.lefthalf.filled"),
        ("voice-report", "語音回報", .monitorRadio, .voiceReportAppend, "waveform"),
        ("finance", "統計儀表板", .manageFinance, .purchaseRequestUpsert, "chart.bar.xaxis"),
        ("export-aar", "事件日誌", .exportAAR, .decisionRecordUpsert, "clock.arrow.circlepath")
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

public extension CommandAuthorityLevel {
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
