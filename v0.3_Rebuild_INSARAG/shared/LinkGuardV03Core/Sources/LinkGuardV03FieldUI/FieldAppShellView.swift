import LinkGuardV03Core
import SwiftUI

public struct FieldAppShellView: View {
    @State private var controller: FieldAppController
    @StateObject private var mapMarkup = MapMarkupViewModel()
    @StateObject private var locationService = FieldLocationService()
    @State private var selectedTab: FieldAppTab = .overview
    @State private var selectedIdentity: FieldLaunchIdentityOption? = nil
    @State private var statusText = "就緒"
    @State private var statusAccent = FieldTheme.green
    @State private var showingTeamCapabilityForm = false
    @State private var teamCapabilityDraft: USARTeamCapabilityReport?
    @State private var showingPhotoCaptureSheet = false
    @State private var photoCapturePreset: FieldPhotoCapturePreset = .scene
    @State private var syncEndpointText = "http://127.0.0.1:8080/sync"
    @State private var isSyncing = false
    @State private var didRunLaunchAutomation = false

    public init(
        appID: LinkGuardAppID,
        platform: AppPlatform,
        deviceID: LinkGuardID,
        displayName: String,
        defaultIdentityCode: String? = nil
    ) {
        let localCacheStore = FieldAppController.defaultLocalCacheStore(appID: appID, deviceID: deviceID)
        let launchEnvironment = ProcessInfo.processInfo.environment
        let launchTab = launchEnvironment["LINKGUARD_DEFAULT_TAB"].flatMap(FieldAppTab.init(rawValue:)) ?? .overview
        _controller = State(initialValue: FieldAppController(appID: appID, platform: platform, deviceID: deviceID, displayName: displayName, localCacheStore: localCacheStore))
        _selectedTab = State(initialValue: launchTab)
        _selectedIdentity = State(initialValue: defaultIdentityCode.flatMap { code in
            FieldLaunchIdentityOption.options(for: appID).first { $0.code == code }
        })
    }

    public var body: some View {
        shellRoot
        .tint(FieldTheme.green)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingTeamCapabilityForm) {
            if let teamCapabilityDraft {
                TeamCapabilityReportFormView(initialReport: teamCapabilityDraft) {
                    showingTeamCapabilityForm = false
                } onSubmit: { report in
                    submitTeamCapabilityReport(report)
                }
            }
        }
        .sheet(isPresented: $showingPhotoCaptureSheet) {
            FieldPhotoCaptureView(
                preset: photoCapturePreset,
                onCancel: {
                    showingPhotoCaptureSheet = false
                },
                onSubmit: { caption in
                    submitPhotoReport(caption: caption, preset: photoCapturePreset)
                }
            )
        }
        .onChange(of: locationService.lastFix) { _, fix in
            guard let fix else { return }
            controller.recordGPSFix(fix)
            statusText = "GPS 已更新"
            statusAccent = FieldTheme.green
        }
        .onChange(of: locationService.lastErrorMessage) { _, message in
            guard message != nil else { return }
            statusText = "GPS 受限"
            statusAccent = FieldTheme.warning
        }
        .task {
            runLaunchAutomationIfNeeded()
        }
    }

    private var shellRoot: some View {
        ZStack {
            navigationShell

            if selectedIdentity == nil {
                identityOverlay
            }
        }
    }

    private var navigationShell: some View {
        NavigationStack {
            fieldTabs
                .navigationTitle(controller.profile.displayName)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Text(LinkGuardVersionInfo.current.displayVersion)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var fieldTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(availableTabs) { tab in
                ScrollView {
                    VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
                        fieldHeader
                        content(for: tab)
                    }
                    .padding(FieldTheme.pagePadding)
                }
                .background(FieldTheme.pageBackground.ignoresSafeArea())
                .tag(tab)
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            }
        }
    }

    private var identityOverlay: some View {
        FieldIdentityPickerOverlay(
            options: FieldLaunchIdentityOption.options(for: controller.runtime.device.appID),
            accent: roleAccent
        ) { identity in
            selectedIdentity = identity
        }
    }

    private var availableTabs: [FieldAppTab] {
        if controller.runtime.device.platform == .iPhone {
            switch controller.runtime.device.appID {
            case .teamLeader, .emt:
                return [.overview, .operations, .mapSafety, .medical, .comms]
            default:
                return [.overview, .operations, .mapSafety, .comms, .queue]
            }
        }

        var tabs: [FieldAppTab] = [.overview, .operations, .mapSafety, .comms, .queue, .settings]
        if controller.runtime.device.appID == .emt || controller.runtime.device.appID == .emtIPad || controller.runtime.device.appID == .teamLeader || controller.runtime.device.appID == .teamLeaderIPad {
            tabs.insert(.medical, at: tabs.firstIndex(of: .comms) ?? tabs.count)
        }
        return tabs
    }

    @ViewBuilder
    private func content(for tab: FieldAppTab) -> some View {
        switch tab {
        case .overview:
            overviewTab
        case .operations:
            operationsTab
        case .mapSafety:
            mapSafetyTab
        case .medical:
            medicalTab
        case .comms:
            commsTab
        case .queue:
            queueTab
        case .settings:
            settingsTab
        }
    }

    private var fieldHeader: some View {
        FieldPanel(accent: roleAccent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    brandMark
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LinkGuard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FieldTheme.green)
                        Text(controller.runtime.device.displayName)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(controller.roleWorkflowTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(roleAccent)
                        if let selectedIdentity {
                            Text(selectedIdentity.displayLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(controller.context.worksiteID.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("待同步")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(controller.pendingEnvelopeCount)")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Button {
                            locationService.requestCurrentFix()
                        } label: {
                            Image(systemName: locationService.isRequestingFix ? "location.fill" : "location.viewfinder")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(locationService.canRequestFix ? FieldTheme.green : .secondary)
                                .frame(width: 30, height: 30)
                                .background((locationService.canRequestFix ? FieldTheme.green : Color.secondary).opacity(0.16), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(locationService.canRequestFix == false)
                        .help("更新 GPS")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FieldStatusPill(title: statusText, systemImage: "checkmark.seal.fill", accent: statusAccent)
                        if let selectedIdentity {
                            FieldStatusPill(title: selectedIdentity.code, systemImage: "person.crop.circle.fill", accent: roleAccent)
                        }
                        FieldStatusPill(title: controller.latestGPSFix == nil ? "無 GPS" : "GPS 就緒", systemImage: "location.fill", accent: controller.latestGPSFix == nil ? FieldTheme.warning : FieldTheme.green)
                        FieldStatusPill(title: LinkGuardVersionInfo.current.displayVersion, systemImage: "tag.fill", accent: FieldTheme.info)
                        FieldStatusPill(title: controller.blueprint.homeSurface.fieldDisplayName, systemImage: "rectangle.3.group.fill", accent: FieldTheme.info)
                        FieldStatusPill(title: controller.profile.commandAuthority.fieldDisplayName, systemImage: "person.badge.key.fill", accent: FieldTheme.command)
                    }
                }
            }
        }
    }

    private var brandMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("Logo", bundle: .main)
                .resizable()
                .scaledToFit()
                .padding(7)
                .frame(width: 54, height: 54)
                .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FieldTheme.green.opacity(0.34), lineWidth: 1)
                )

            Image(systemName: roleIcon)
                .font(.caption.weight(.bold))
                .foregroundStyle(roleAccent)
                .frame(width: 22, height: 22)
                .background(FieldTheme.surface, in: Circle())
                .overlay(Circle().stroke(roleAccent.opacity(0.48), lineWidth: 1))
        }
        .accessibilityLabel("LinkGuard")
    }

    private var locationAccent: Color {
        if locationService.lastErrorMessage != nil { return FieldTheme.warning }
        if locationService.isRequestingFix { return FieldTheme.info }
        if controller.latestGPSFix != nil { return FieldTheme.green }
        return FieldTheme.warning
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            missionOverview
            priorityActionPanel
            inboxPanel
            if controller.canUseFeature(.personnelOverview) {
                personnelPanel
            }
        }
    }

    private var operationsTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            roleOperationsPanel
            taskPanel
            phasePanel
        }
    }

    private var mapSafetyTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            mapStatusPanel
            safetyPanel
        }
    }

    private var medicalTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            medicalOverviewPanel
            medicalActionPanel
        }
    }

    private var commsTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            communicationPanel
            reportPanel
        }
    }

    private var queueTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            outboxPanel
            eventLogPanel
        }
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            appSettingsPanel
            roleContractPanel
            featureReadinessPanel
        }
    }

    private var appSettingsPanel: some View {
        let settingsInfo = LinkGuardAppSettingsInfo(device: controller.runtime.device)
        return FieldPanel("應用設定", systemImage: "gearshape.fill", accent: FieldTheme.command) {
            VStack(spacing: 8) {
                ForEach(settingsInfo.items) { item in
                    FieldTimelineRow(
                        title: settingsTitle(for: item),
                        detail: item.value,
                        systemImage: settingsIcon(for: item.key),
                        accent: settingsAccent(for: item.key),
                        trailing: nil
                    )
                }
                FieldTimelineRow(
                    title: "版本備註",
                    detail: settingsInfo.versionInfo.notes,
                    systemImage: "doc.text.fill",
                    accent: FieldTheme.info,
                    trailing: nil
                )
            }
        }
    }

    private var roleContractPanel: some View {
        let permissions = controller.profile.permissions.sorted { $0.rawValue < $1.rawValue }
        return FieldPanel("角色權限", systemImage: "person.badge.key.fill", accent: roleAccent) {
            VStack(alignment: .leading, spacing: 12) {
                FieldAdaptiveGrid(minimum: 142) {
                    FieldMetricTile(title: "指揮", value: controller.profile.commandAuthority.fieldDisplayName, systemImage: "person.badge.key.fill", accent: FieldTheme.command)
                    FieldMetricTile(title: "醫療", value: controller.profile.medicalAccess.fieldDisplayName, systemImage: "cross.case.fill", accent: FieldTheme.medical)
                    FieldMetricTile(title: "必要", value: "\(controller.blueprint.requiredPermissions.count)", systemImage: "checkmark.shield.fill", accent: FieldTheme.green)
                    FieldMetricTile(title: "授權", value: "\(permissions.count)", systemImage: "key.fill", accent: FieldTheme.team)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(permissions, id: \.self) { permission in
                            let isRequired = controller.blueprint.requiredPermissions.contains(permission)
                            FieldStatusPill(
                                title: permission.fieldDisplayName,
                                systemImage: isRequired ? "checkmark.shield.fill" : "key.fill",
                                accent: isRequired ? FieldTheme.green : FieldTheme.info
                            )
                        }
                    }
                }
            }
        }
    }

    private var featureReadinessPanel: some View {
        let features = LinkGuardFeatureAccessMatrix.features(for: controller.runtime.device.appID)
            .sorted { lhs, rhs in lhs.rawValue < rhs.rawValue }
            .prefix(12)
        return FieldPanel("現場就緒", systemImage: "antenna.radiowaves.left.and.right", accent: FieldTheme.green) {
            VStack(spacing: 8) {
                FieldAdaptiveGrid(minimum: 142) {
                    FieldMetricTile(title: "佇列", value: "\(controller.pendingEnvelopeCount)", systemImage: "tray.full.fill", accent: controller.pendingEnvelopeCount == 0 ? FieldTheme.green : FieldTheme.warning)
                    FieldMetricTile(title: "GPS", value: controller.latestGPSFix == nil ? "未定位" : "就緒", systemImage: "location.fill", accent: controller.latestGPSFix == nil ? FieldTheme.warning : FieldTheme.green)
                    FieldMetricTile(title: "傳輸", value: controller.runtime.pendingOutboundCount == 0 ? "清空" : "待送", systemImage: "arrow.triangle.2.circlepath", accent: controller.runtime.pendingOutboundCount == 0 ? FieldTheme.green : FieldTheme.info)
                    FieldMetricTile(title: "儲存", value: controller.localCacheStore == nil ? "記憶體" : (controller.lastPersistenceError == nil ? "已保存" : "錯誤"), systemImage: "externaldrive.fill", accent: controller.lastPersistenceError == nil ? FieldTheme.green : FieldTheme.warning)
                }
                ForEach(Array(features), id: \.self) { feature in
                    let access = controller.accessLevel(for: feature)
                    FieldTimelineRow(
                        title: feature.fieldDisplayName,
                        detail: access.fieldDisplayName,
                        systemImage: feature.fieldIconName,
                        accent: access.fieldAccentColor,
                        trailing: access.fieldShortLabel
                    )
                }
            }
        }
    }

    private var missionOverview: some View {
        let summary = controller.missionSummary
        return FieldPanel("任務概況", systemImage: "scope", accent: roleAccent) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.incidentName)
                        .font(.headline)
                    Text(controller.roleWorkflowSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                FieldAdaptiveGrid(minimum: 142) {
                    FieldMetricTile(title: "任務", value: "\(summary.openTaskCount)", systemImage: "checklist.checked", accent: FieldTheme.green)
                    if controller.canUseFeature(.personnelOverview) {
                        FieldMetricTile(title: "在線", value: "\(summary.onlinePersonnelCount)/\(summary.personnelCount)", systemImage: "person.3.fill", accent: FieldTheme.team)
                    }
                    FieldMetricTile(title: "安全", value: "\(summary.safetyZoneCount)", systemImage: "shield.lefthalf.filled", accent: FieldTheme.warning)
                    FieldMetricTile(title: "回報", value: "\(summary.photoReportCount + summary.disasterReportCount + summary.teamCapabilityReportCount)", systemImage: "camera.fill", accent: FieldTheme.info)
                    FieldMetricTile(title: "傷患", value: "\(summary.patientCount)", systemImage: "cross.case.fill", accent: FieldTheme.medical)
                    FieldMetricTile(title: "SOS", value: "\(summary.sosCount)", systemImage: "sos.circle.fill", accent: FieldTheme.danger)
                }
            }
        }
    }

    private var priorityActionPanel: some View {
        FieldPanel("快速操作", systemImage: "bolt.fill", accent: FieldTheme.danger) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("SOS", detail: "送出定位與危急狀態", systemImage: "sos.circle.fill", feature: .sosSending, messageType: .sosReportUpsert, accent: FieldTheme.danger) {
                    try controller.queueSOS(dangerType: controller.runtime.device.appID == .emt ? .injured : .trapped, note: "Field SOS", now: Date())
                }
                fieldAction("GPS", detail: "回報目前位置", systemImage: "location.fill", feature: .gpsTracking, messageType: .personnelStatusUpsert, accent: FieldTheme.green) {
                    try controller.queueGPSReport(now: Date())
                }
                fieldAction("語音", detail: "送出語音狀態", systemImage: "waveform.circle.fill", feature: .voiceReport, messageType: .voiceReportAppend, accent: FieldTheme.team) {
                    try controller.queueVoiceReport(transcript: "Field voice update", durationSeconds: 6, now: Date())
                }
            }
        }
    }

    private var roleOperationsPanel: some View {
        FieldPanel(roleOperationsTitle, systemImage: "rectangle.3.group.fill", accent: roleAccent) {
            FieldAdaptiveGrid(minimum: 158) {
                ForEach(roleActionDefinitions) { definition in
                    fieldAction(definition.title, detail: definition.detail, systemImage: definition.systemImage, feature: definition.feature, messageType: definition.messageType, accent: definition.accent) {
                        try perform(definition.action)
                    }
                }
            }
        }
    }

    private var taskPanel: some View {
        let tasks = controller.runtime.snapshot.tasks.values.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
        return FieldPanel("任務列表", systemImage: "checklist.checked", accent: FieldTheme.green) {
            VStack(spacing: 8) {
                if tasks.isEmpty {
                    emptyRow("尚無指派任務", systemImage: "checklist.unchecked")
                } else {
                    ForEach(Array(tasks.prefix(5)), id: \.id) { task in
                        FieldTimelineRow(
                            title: task.summary,
                            detail: "\(task.type.rawValue) / \(task.status.rawValue) / \(task.worksiteID?.rawValue ?? controller.context.worksiteID.rawValue)",
                            systemImage: "checklist.checked",
                            accent: task.priority.fieldAccentColor,
                            trailing: task.priority.fieldLabel
                        )
                    }
                }
            }
        }
    }

    private var phasePanel: some View {
        FieldPanel("作業流程", systemImage: "point.topleft.down.curvedto.point.bottomright.up", accent: FieldTheme.info) {
            VStack(alignment: .leading, spacing: 10) {
                if controller.runtime.device.appID == .emt || controller.runtime.device.appID == .emtIPad {
                    ForEach(controller.emtMedicalPhases) { phase in
                        FieldTimelineRow(title: phase.moduleName, detail: phase.capability, systemImage: "cross.case.fill", accent: FieldTheme.medical, trailing: phase.label)
                    }
                } else {
                    ForEach(controller.teamMemberPhases) { phase in
                        FieldTimelineRow(title: phase.moduleName, detail: phase.capability, systemImage: "figure.walk.motion", accent: FieldTheme.team, trailing: phase.label)
                    }
                }
            }
        }
    }

    private var inboxPanel: some View {
        FieldPanel("接收項目", systemImage: "tray.full", accent: FieldTheme.info) {
            VStack(spacing: 8) {
                if controller.inboxItems.isEmpty {
                    emptyRow("尚無接收項目", systemImage: "tray")
                } else {
                    ForEach(controller.inboxItems) { item in
                        FieldTimelineRow(title: item.title, detail: item.detail, systemImage: item.systemImageName, accent: item.priority.fieldAccentColor, trailing: item.priority.fieldLabel)
                    }
                }
            }
        }
    }

    private var personnelPanel: some View {
        let statuses = controller.runtime.snapshot.latestPersonnelStatuses(onlineWithin: 300, now: Date())
        return FieldPanel("人員狀態", systemImage: "person.3.fill", accent: FieldTheme.team) {
            VStack(spacing: 8) {
                if statuses.isEmpty {
                    emptyRow("尚無人員心跳", systemImage: "person.crop.circle.badge.questionmark")
                } else {
                    ForEach(Array(statuses.prefix(6)), id: \.id) { status in
                        FieldTimelineRow(
                            title: status.deviceID.rawValue,
                            detail: "\(status.role.rawValue) / \(status.operationalState.rawValue) / \(status.currentWorksiteID?.rawValue ?? "no worksite")",
                            systemImage: status.connectivity == .online ? "dot.radiowaves.left.and.right" : "wifi.slash",
                            accent: status.connectivity == .online ? FieldTheme.green : FieldTheme.warning,
                            trailing: batteryLabel(status.batteryLevel)
                        )
                    }
                }
            }
        }
    }

    private var mapStatusPanel: some View {
        FieldPanel("現場地圖", systemImage: "map.fill", accent: FieldTheme.green) {
            VStack(alignment: .leading, spacing: 12) {
                if let fix = controller.latestGPSFix {
                    FieldTimelineRow(
                        title: "目前 GPS 定位",
                        detail: "\(fix.coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(fix.coordinate.longitude.formatted(.number.precision(.fractionLength(4)))) / \(fix.source.rawValue)",
                        systemImage: "location.fill",
                        accent: FieldTheme.green,
                        trailing: fix.coordinate.accuracyMeters.map { "±\(Int($0))m" }
                    )
                } else {
                    emptyRow("尚無 GPS 定位", systemImage: "location.slash")
                }
                locationServiceRow
                mapMarkupCanvas
                mapMarkupControls
                FieldAdaptiveGrid(minimum: 158) {
                    fieldAction("點位", detail: "標記傷患或危險點", systemImage: "mappin.circle.fill", feature: .pointMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.green) {
                        try controller.queueMapMarker(featureType: .victimPoint, geometryType: .point, title: "Field point", now: Date())
                    }
                    fieldAction("路線", detail: "標記搜索或後送路線", systemImage: "point.topleft.down.curvedto.point.bottomright.up", feature: .lineMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.info) {
                        try controller.queueMapMarker(featureType: .evacuationRoute, geometryType: .polyline, title: "Evacuation route", now: Date())
                    }
                    fieldAction("區域", detail: "標記搜索區或危險區", systemImage: "skew", feature: .areaMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.warning) {
                        try controller.queueMapMarker(featureType: .collapsedAreaPolygon, geometryType: .polygon, title: "Hazard area", now: Date())
                    }
                }
                mapMarkupList
            }
        }
    }

    private var locationServiceRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: locationService.isRequestingFix ? "location.fill" : "location.viewfinder")
                .foregroundStyle(locationAccent)
                .frame(width: 28, height: 28)
                .background(locationAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(locationService.statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(locationService.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                locationService.requestCurrentFix()
            } label: {
                Label(locationService.isRequestingFix ? "定位中" : "更新", systemImage: "location.fill.viewfinder")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(locationService.canRequestFix ? FieldTheme.green : .secondary)
                    .background((locationService.canRequestFix ? FieldTheme.green : Color.secondary).opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke((locationService.canRequestFix ? FieldTheme.green : Color.secondary).opacity(0.34), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(locationService.canRequestFix == false)
        }
        .padding(12)
        .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
    }

    private var mapMarkupCanvas: some View {
        FieldMapCanvasView(features: mapMarkup.visibleFeatures, draftGeometry: mapMarkup.draftGeometry) { coordinate in
            handleMapTap(coordinate)
        }
        .frame(height: controller.runtime.device.platform == .iPad ? 360 : 260)
    }

    private var mapMarkupControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $mapMarkup.drawingMode) {
                ForEach(MapDrawingMode.allCases) { mode in
                    Label(mode.fieldTitle, systemImage: mode.fieldIconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([MapDrawingMode.point, .polyline, .polygon]) { mode in
                        mapControlButton(
                            mode.fieldTitle,
                            systemImage: mode.fieldIconName,
                            accent: mapMarkup.visibleLayers.contains(mode) ? mode.fieldAccent : .secondary,
                            isEnabled: true
                        ) {
                            mapMarkup.toggleLayer(mode)
                        }
                    }
                    mapControlButton("復原", systemImage: "arrow.uturn.backward.circle.fill", accent: FieldTheme.info, isEnabled: mapMarkup.canUndo) {
                        mapMarkup.undo()
                    }
                    mapControlButton("重做", systemImage: "arrow.uturn.forward.circle.fill", accent: FieldTheme.info, isEnabled: mapMarkup.canRedo) {
                        mapMarkup.redo()
                    }
                    mapControlButton("取消", systemImage: "xmark.circle.fill", accent: FieldTheme.warning, isEnabled: mapMarkup.draftGeometry != nil) {
                        mapMarkup.cancelDraft()
                    }
                    mapControlButton("送出", systemImage: "checkmark.circle.fill", accent: FieldTheme.green, isEnabled: mapMarkup.draftGeometry != nil) {
                        commitMapDraft()
                    }
                }
            }
        }
    }

    private var mapMarkupList: some View {
        VStack(spacing: 8) {
            if mapMarkup.features.isEmpty {
                emptyRow("尚無本機地圖標註", systemImage: "map")
            } else {
                ForEach(Array(mapMarkup.features.suffix(5).reversed()), id: \.id) { feature in
                    FieldTimelineRow(
                        title: feature.title,
                        detail: "\(mapGeometryLabel(feature.geometry)) / \(feature.sectionID.displayName) / \(feature.searchState.displayName)",
                        systemImage: mapIconName(feature.geometry),
                        accent: mapAccent(feature.geometry),
                        trailing: shortTime(feature.updatedAt)
                    )
                }
            }
        }
    }

    private var safetyPanel: some View {
        FieldPanel("安全管制", systemImage: "shield.lefthalf.filled", accent: FieldTheme.warning) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("危險區", detail: "發布現場危險區", systemImage: "exclamationmark.triangle.fill", feature: .hazardZoneManagement, messageType: .safetyZoneUpsert, accent: FieldTheme.warning) {
                    try controller.queueSafetyZone(now: Date())
                }
                fieldAction("進場", detail: "登錄進入管制區", systemImage: "figure.walk.arrival", feature: .personnelEntryLog, messageType: .safetyEntryLogUpsert, accent: FieldTheme.green) {
                    try controller.queueSafetyEntry(.checkIn, now: Date())
                }
                fieldAction("離場", detail: "登錄離開管制區", systemImage: "figure.walk.departure", feature: .personnelEntryLog, messageType: .safetyEntryLogUpsert, accent: FieldTheme.info) {
                    try controller.queueSafetyEntry(.checkOut, now: Date())
                }
            }
        }
    }

    private var communicationPanel: some View {
        FieldPanel("通訊回報", systemImage: "message.fill", accent: FieldTheme.team) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("訊息", detail: "送出小隊群組訊息", systemImage: "message.fill", feature: .communicationChannel, messageType: .groupChatMessageAppend, accent: FieldTheme.team) {
                    try controller.queueGroupChat(body: chatMessageForRole, now: Date())
                }
                fieldAction("語音", detail: "送出語音與逐字稿", systemImage: "waveform.circle.fill", feature: .voiceReport, messageType: .voiceReportAppend, accent: FieldTheme.green) {
                    try controller.queueVoiceReport(transcript: voiceMessageForRole, durationSeconds: 6, now: Date())
                }
                fieldAction("照片", detail: "送出照片與 GPS 證據", systemImage: "camera.fill", feature: .photoReport, messageType: .photoReportUpsert, accent: FieldTheme.info) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "ATTACH"), caption: photoCaptionForRole, checksum: nil, now: Date())
                }
            }
        }
    }

    private var reportPanel: some View {
        FieldPanel("現場回報", systemImage: "doc.text.image.fill", accent: FieldTheme.info) {
            FieldAdaptiveGrid(minimum: 158) {
                FieldActionCard(title: "拍照", detail: "拍攝並送出現場照片", systemImage: "camera.fill", accent: FieldTheme.info, isEnabled: controller.canUseFeature(.photoReport) && controller.canSend(.photoReportUpsert)) {
                    openPhotoCapture(.scene)
                }
                fieldAction("倒塌", detail: "回報結構倒塌狀況", systemImage: "exclamationmark.bubble.fill", feature: .disasterReport, messageType: .disasterReportUpsert, accent: FieldTheme.warning) {
                    try controller.queueDisasterReport(kind: .collapse, summary: "結構倒塌回報", now: Date())
                }
                fieldAction("火災", detail: "回報現場火勢", systemImage: "flame.fill", feature: .disasterReport, messageType: .disasterReportUpsert, accent: FieldTheme.danger) {
                    try controller.queueDisasterReport(kind: .fire, severity: .critical, summary: "現場火勢回報", now: Date())
                }
                teamCapabilityProfileAction
            }
        }
    }

    private var teamCapabilityProfileAction: some View {
        let feature = LinkGuardFeature.teamCapabilityOverview
        let messageType = SyncMessageType.teamCapabilityReportUpsert
        let visible = controller.canSeeFeature(feature)
        let enabled = visible && controller.canUseFeature(feature) && controller.canSend(messageType)
        return Group {
            if visible {
                FieldActionCard(
                    title: "USAR 能量",
                    detail: "填寫 A/B/C/D 小隊能量",
                    systemImage: "person.3.sequence.fill",
                    accent: FieldTheme.green,
                    isEnabled: enabled
                ) {
                    openTeamCapabilityForm()
                }
            }
        }
    }

    private var medicalOverviewPanel: some View {
        FieldPanel("醫療流程", systemImage: "cross.case.fill", accent: FieldTheme.medical) {
            VStack(spacing: 8) {
                ForEach(controller.emtMedicalPhases) { phase in
                    FieldTimelineRow(title: phase.moduleName, detail: phase.capability, systemImage: "cross.case.fill", accent: FieldTheme.medical, trailing: phase.label)
                }
            }
        }
    }

    private var medicalActionPanel: some View {
        FieldPanel("傷患作業", systemImage: "heart.text.square.fill", accent: FieldTheme.medical) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("傷患", detail: "建立現場傷患紀錄", systemImage: "cross.case.fill", feature: .patientCreation, messageType: .patientUpsert, accent: FieldTheme.medical) {
                    try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "腿部出血", now: Date())
                }
                fieldAction("START", detail: "登錄 START 檢傷", systemImage: "waveform.path.ecg", feature: .startTriage, messageType: .patientUpsert, accent: FieldTheme.danger) {
                    try controller.queueStartTriage(displayCode: "A023", category: .red, respiratoryRate: 28, pulseRate: 120, gcs: 14, injurySummary: "腿部出血", now: Date())
                }
                fieldAction("生命徵象", detail: "更新檢傷與生命徵象", systemImage: "heart.text.square.fill", feature: .patientStatusUpdate, messageType: .patientUpsert, accent: FieldTheme.warning) {
                    try controller.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "已使用止血帶", now: Date())
                }
                fieldAction("後送", detail: "提出傷患後送需求", systemImage: "arrow.triangle.2.circlepath.circle.fill", feature: .medicalEvacuation, messageType: .evacuationRequestUpsert, accent: FieldTheme.info) {
                    try controller.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: Date())
                }
                fieldAction("醫院", detail: "發布醫療量能更新", systemImage: "cross.vial.fill", feature: .hospitalCapacityView, messageType: .hospitalCapacityUpsert, accent: FieldTheme.green) {
                    try controller.queueHospitalCapacityUpdate(emergencyCapacity: 8, traumaCapacity: 3, burnCapacity: 1, pediatricCapacity: 2, now: Date())
                }
                fieldAction("傷患照片", detail: "附加傷患影像紀錄", systemImage: "camera.fill", feature: .patientPhoto, messageType: .photoReportUpsert, accent: FieldTheme.info) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "PATIENT-PHOTO"), caption: "傷患照片", checksum: nil, now: Date())
                }
            }
        }
    }

    private var outboxPanel: some View {
        FieldPanel("離線佇列", systemImage: "tray.full", accent: FieldTheme.green) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("同步端點", text: $syncEndpointText)
                        .font(.caption.monospaced())
                        .textFieldStyle(.roundedBorder)
                    Button {
                        runSyncNow()
                    } label: {
                        Label(isSyncing ? "同步中" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncing || controller.pendingEnvelopeCount == 0)
                }
                if let syncResult = controller.lastSyncResult {
                    FieldTimelineRow(
                        title: syncResult.attempted ? "上次同步" : "尚未同步",
                        detail: "已送達 \(syncResult.deliveredEnvelopeIDs.count) / 失敗 \(syncResult.failedEnvelopeIDs.count) / 剩餘 \(syncResult.remainingPendingCount)",
                        systemImage: syncResult.failedEnvelopeIDs.isEmpty ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill",
                        accent: syncResult.failedEnvelopeIDs.isEmpty ? FieldTheme.green : FieldTheme.warning,
                        trailing: syncResult.attempted ? "同步" : "待命"
                    )
                }
                if let syncError = controller.lastSyncError {
                    FieldTimelineRow(
                        title: "同步錯誤",
                        detail: syncError,
                        systemImage: "wifi.exclamationmark",
                        accent: FieldTheme.warning,
                        trailing: "失敗"
                    )
                }
                if let persistenceError = controller.lastPersistenceError {
                    FieldTimelineRow(
                        title: "佇列儲存",
                        detail: persistenceError,
                        systemImage: "externaldrive.badge.exclamationmark",
                        accent: FieldTheme.warning,
                        trailing: "錯誤"
                    )
                }
                if controller.queuedSummaries.isEmpty {
                    emptyRow("尚無待同步封包", systemImage: "tray")
                } else {
                    ForEach(controller.queuedSummaries) { item in
                        FieldTimelineRow(
                            title: item.messageType.fieldDisplayName,
                            detail: "等待同步 / \(item.id.rawValue)",
                            systemImage: iconName(for: item.messageType),
                            accent: item.priority.fieldAccentColor,
                            trailing: item.priority.fieldLabel
                        )
                    }
                }
            }
        }
    }

    private var eventLogPanel: some View {
        FieldPanel("事件紀錄", systemImage: "clock.arrow.circlepath", accent: FieldTheme.info) {
            VStack(spacing: 8) {
                let events = controller.runtime.snapshot.auditEvents.suffix(8).reversed()
                if events.isEmpty {
                    emptyRow("尚無本機稽核事件", systemImage: "clock")
                } else {
                    ForEach(Array(events), id: \.id) { event in
                        FieldTimelineRow(
                            title: event.action.rawValue,
                            detail: "\(event.targetType) / \(event.targetID.rawValue)",
                            systemImage: "clock.arrow.circlepath",
                            accent: FieldTheme.info,
                            trailing: shortTime(event.createdAt)
                        )
                    }
                }
            }
        }
    }

    private func fieldAction(
        _ title: String,
        detail: String,
        systemImage: String,
        feature: LinkGuardFeature,
        messageType: SyncMessageType,
        accent: Color,
        action: @escaping () throws -> SyncEnvelope
    ) -> some View {
        let visible = controller.canSeeFeature(feature)
        let enabled = visible && controller.canUseFeature(feature) && controller.canSend(messageType)
        return Group {
            if visible {
                FieldActionCard(title: title, detail: detail, systemImage: systemImage, accent: accent, isEnabled: enabled) {
                    runAction(title, action)
                }
            }
        }
    }

    private func runAction(_ title: String, _ action: () throws -> SyncEnvelope) {
        do {
            _ = try action()
            statusText = "已排入 \(title)"
            statusAccent = FieldTheme.green
        } catch {
            statusText = "受限 \(title)"
            statusAccent = FieldTheme.warning
        }
    }

    private func openTeamCapabilityForm() {
        guard controller.canUseFeature(.teamCapabilityOverview), controller.canSend(.teamCapabilityReportUpsert) else {
            statusText = "受限 USAR 能量"
            statusAccent = FieldTheme.warning
            return
        }
        teamCapabilityDraft = controller.makeTeamCapabilityDraft(now: Date())
        showingTeamCapabilityForm = true
    }

    private func submitTeamCapabilityReport(_ report: USARTeamCapabilityReport) {
        do {
            _ = try controller.queueTeamCapabilityReport(report, now: report.createdAt)
            statusText = "已排入 USAR 能量"
            statusAccent = FieldTheme.green
            showingTeamCapabilityForm = false
            teamCapabilityDraft = nil
        } catch {
            statusText = "受限 USAR 能量"
            statusAccent = FieldTheme.warning
        }
    }

    private func openPhotoCapture(_ preset: FieldPhotoCapturePreset) {
        guard controller.canUseFeature(.photoReport), controller.canSend(.photoReportUpsert) else {
            statusText = "受限 拍照"
            statusAccent = FieldTheme.warning
            return
        }
        photoCapturePreset = preset
        showingPhotoCaptureSheet = true
    }

    private func submitPhotoReport(caption: String, preset: FieldPhotoCapturePreset) {
        var updatingController = controller
        do {
            _ = try updatingController.queuePhotoReport(
                photoAttachmentID: LinkGuardID.generated(prefix: preset.attachmentPrefix),
                caption: caption.isEmpty ? preset.defaultCaption : caption,
                checksum: nil,
                now: Date()
            )
            controller = updatingController
            statusText = "已排入 拍照"
            statusAccent = FieldTheme.green
            showingPhotoCaptureSheet = false
        } catch {
            controller = updatingController
            statusText = "受限 拍照"
            statusAccent = FieldTheme.warning
        }
    }

    private func runSyncNow() {
        guard isSyncing == false else { return }
        guard
            let endpointURL = URL(string: syncEndpointText),
            let scheme = endpointURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            statusText = "端點錯誤"
            statusAccent = FieldTheme.warning
            return
        }

        isSyncing = true
        statusText = "同步中"
        statusAccent = FieldTheme.info
        Task { @MainActor in
            defer { isSyncing = false }
            var syncingController = controller
            do {
                let result = try await syncingController.syncQueuedEnvelopes(endpointURL: endpointURL, now: Date())
                controller = syncingController
                statusText = result.attempted ? "已同步 \(result.deliveredEnvelopeIDs.count)" : "尚未同步"
                statusAccent = result.failedEnvelopeIDs.isEmpty ? FieldTheme.green : FieldTheme.warning
            } catch {
                controller = syncingController
                statusText = "同步失敗"
                statusAccent = FieldTheme.warning
            }
        }
    }

    private func perform(_ action: FieldRoleActionKind) throws -> SyncEnvelope {
        switch action {
        case .sectorPlan:
            guard let envelope = try controller.queueSectorPlan(now: Date()).last else { throw FieldAppError.missingGPSFix }
            return envelope
        case .taskAssignment:
            return try controller.queueTaskAssignment(now: Date())
        case .taskAccepted:
            return try controller.queueTaskStatus(.accepted, now: Date())
        case .taskInProgress:
            return try controller.queueTaskStatus(.inProgress, now: Date())
        case .personnelOnline:
            return try controller.queuePersonnelStatus(operationalState: .assigned, connectivity: .online, batteryLevel: 0.91, now: Date())
        case .gps:
            return try controller.queueGPSReport(now: Date())
        case .photo:
            return try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "ATTACH"), caption: photoCaptionForRole, checksum: nil, now: Date())
        case .safetyZone:
            return try controller.queueSafetyZone(now: Date())
        case .safetyCheckIn:
            return try controller.queueSafetyEntry(.checkIn, now: Date())
        case .chat:
            return try controller.queueGroupChat(body: chatMessageForRole, now: Date())
        }
    }

    private func runLaunchAutomationIfNeeded() {
        guard didRunLaunchAutomation == false else { return }
        didRunLaunchAutomation = true

        let rawActions = ProcessInfo.processInfo.environment["LINKGUARD_AUTORUN_ACTIONS"] ?? ""
        let actions = rawActions
            .split(separator: ",")
            .compactMap { FieldRoleActionKind(launchToken: String($0)) }
        guard actions.isEmpty == false else { return }

        var latestStatus = "自動操作完成"
        var latestAccent = FieldTheme.green
        for action in actions {
            do {
                _ = try perform(action)
            } catch {
                latestStatus = "自動操作受限"
                latestAccent = FieldTheme.warning
            }
        }
        statusText = latestStatus
        statusAccent = latestAccent
    }

    private func handleMapTap(_ coordinate: MapCoordinate) {
        switch mapMarkup.drawingMode {
        case .select:
            mapMarkup.selectFeature(nil)
        case .point:
            mapMarkup.beginDraft(at: coordinate)
        case .polyline, .polygon:
            if mapMarkup.draftGeometry?.mode == mapMarkup.drawingMode {
                mapMarkup.appendDraftPoint(coordinate)
            } else {
                mapMarkup.beginDraft(at: coordinate)
            }
        }
    }

    private func commitMapDraft() {
        let mode = mapMarkup.draftGeometry?.mode ?? mapMarkup.drawingMode
        guard let feature = mapMarkup.commitDraft(
            incidentID: controller.context.incidentID,
            sectionID: .sectionA,
            searchState: defaultSearchState(for: mode),
            title: mapTitle(for: mode),
            createdBy: controller.runtime.device.id,
            pointType: mapPointTypeForRole,
            lineType: mapLineTypeForRole,
            polygonType: mapPolygonTypeForRole,
            now: Date()
        ) else {
            statusText = "地圖草稿未完成"
            statusAccent = FieldTheme.warning
            return
        }

        do {
            _ = try controller.queueMapMarkupFeature(
                feature,
                featureType: mapFeatureType(for: feature.geometry),
                now: Date()
            )
            statusText = "已排入 地圖"
            statusAccent = FieldTheme.green
        } catch {
            statusText = "已暫存 地圖"
            statusAccent = FieldTheme.warning
        }
    }

    private func mapControlButton(
        _ title: String,
        systemImage: String,
        accent: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(isEnabled ? accent : .secondary)
                .background((isEnabled ? accent : Color.secondary).opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke((isEnabled ? accent : Color.secondary).opacity(0.34), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }

    private func mapTitle(for mode: MapDrawingMode) -> String {
        switch mode {
        case .select:
            return "Field marker"
        case .point:
            return mapPointTypeForRole.displayName
        case .polyline:
            return mapLineTypeForRole.displayName
        case .polygon:
            return mapPolygonTypeForRole.displayName
        }
    }

    private var mapPointTypeForRole: MapPointType {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return .victim
        case .scc, .sccIPad, .ucc:
            return .commandPost
        case .teamLeader, .teamLeaderIPad:
            return .hazardPoint
        case .teamMember:
            return .rescueTeamMember
        case .volunteer:
            return .assemblyPoint
        }
    }

    private var mapLineTypeForRole: MapLineType {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return .evacuationRoute
        case .volunteer:
            return .passageway
        default:
            return .searchPath
        }
    }

    private var mapPolygonTypeForRole: MapPolygonType {
        switch controller.runtime.device.appID {
        case .scc, .sccIPad, .ucc:
            return .subzone
        case .teamLeader, .teamLeaderIPad, .teamMember:
            return .searchArea
        case .emt, .emtIPad:
            return .searchArea
        case .volunteer:
            return .cleanedArea
        }
    }

    private func defaultSearchState(for mode: MapDrawingMode) -> SearchState {
        switch mode {
        case .select:
            return .unconfirmed
        case .point, .polyline:
            return .searching
        case .polygon:
            return mapPolygonTypeForRole == .cleanedArea ? .cleared : .highRisk
        }
    }

    private func geometryType(for geometry: MapMarkupFeature.MarkupGeometry) -> GeometryType {
        switch geometry {
        case .point:
            return .point
        case .line:
            return .polyline
        case .polygon:
            return .polygon
        }
    }

    private func mapFeatureType(for geometry: MapMarkupFeature.MarkupGeometry) -> MapFeatureType {
        switch geometry {
        case .point(let type, _, _):
            switch type {
            case .sos, .victim, .survivor:
                return .victimPoint
            case .medicalStation:
                return .medicalStation
            case .assemblyPoint:
                return .assemblyPoint
            case .hazardPoint:
                return .restrictedZone
            case .rescueTeamMember, .commandPost:
                return .worksiteBoundary
            }
        case .line(let type, _):
            switch type {
            case .evacuationRoute:
                return .evacuationRoute
            case .hazardousRoute, .cordonLine:
                return .roadBlockLine
            case .searchPath, .supplyRoute, .passageway:
                return .evacuationRoute
            }
        case .polygon(let type, _):
            switch type {
            case .collapsedArea:
                return .collapsedAreaPolygon
            case .hazardousZone, .fireZone, .chemicalHazard:
                return .hazardPolygon
            case .searchArea, .subzone:
                return .worksiteBoundary
            case .cleanedArea:
                return .safetyZone
            }
        }
    }

    private func mapGeometryLabel(_ geometry: MapMarkupFeature.MarkupGeometry) -> String {
        switch geometry {
        case .point(let type, _, _):
            return type.displayName
        case .line(let type, _):
            return type.displayName
        case .polygon(let type, _):
            return type.displayName
        }
    }

    private func mapIconName(_ geometry: MapMarkupFeature.MarkupGeometry) -> String {
        switch geometry {
        case .point:
            return "mappin.circle.fill"
        case .line:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .polygon:
            return "skew"
        }
    }

    private func mapAccent(_ geometry: MapMarkupFeature.MarkupGeometry) -> Color {
        switch geometry {
        case .point(let type, _, _):
            return type == .sos || type == .hazardPoint ? FieldTheme.danger : FieldTheme.green
        case .line(let type, _):
            return type == .hazardousRoute || type == .cordonLine ? FieldTheme.warning : FieldTheme.info
        case .polygon(let type, _):
            return type == .hazardousZone || type == .collapsedArea || type == .fireZone ? FieldTheme.warning : FieldTheme.green
        }
    }

    private func emptyRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
    }

    private var roleOperationsTitle: String {
        switch controller.runtime.device.appID {
        case .sccIPad:
            return "SCC iPad 分區管制"
        case .teamLeader:
            return "TL 小隊指揮"
        case .teamLeaderIPad:
            return "TL iPad 工區指揮"
        case .teamMember:
            return "TE 任務執行"
        case .volunteer:
            return "VO 支援回報"
        case .emt, .emtIPad:
            return "EMT 現場醫療"
        case .ucc, .scc:
            return "指揮預覽"
        }
    }

    private var roleActionDefinitions: [FieldRoleActionDefinition] {
        switch controller.runtime.device.appID {
        case .sccIPad:
            return [
                .init("分區", "建立分區/子分區/工區", "square.3.layers.3d", .sectorCreation, .sectorUpsert, FieldTheme.command, .sectorPlan),
                .init("派任務", "指派任務給小隊", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("人員", "發布線上人員狀態", "person.3.fill", .personnelOverview, .personnelStatusUpsert, FieldTheme.team, .personnelOnline),
                .init("安全", "發布危險區", "shield.lefthalf.filled", .safetyControlBoard, .safetyZoneUpsert, FieldTheme.warning, .safetyZone),
                .init("進場", "登錄管制區進入", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.info, .safetyCheckIn),
                .init("通訊", "送出分區訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .teamLeader, .teamLeaderIPad:
            return [
                .init("工區", "建立 A1 工區計畫", "square.3.layers.3d", .worksiteMarkerSystem, .worksiteUpsert, FieldTheme.command, .sectorPlan),
                .init("派任務", "指派小隊任務", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("執行中", "更新任務狀態", "figure.run.circle.fill", .taskReport, .taskUpsert, FieldTheme.team, .taskInProgress),
                .init("安全區", "發布危險區", "exclamationmark.triangle.fill", .hazardZoneManagement, .safetyZoneUpsert, FieldTheme.warning, .safetyZone),
                .init("進場", "進入管制區", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.info, .safetyCheckIn),
                .init("通訊", "送出小隊訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .teamMember:
            return [
                .init("接收", "接受指派任務", "checkmark.circle.fill", .taskReport, .taskUpsert, FieldTheme.green, .taskAccepted),
                .init("執行中", "標記正在作業", "figure.run.circle.fill", .taskReport, .taskUpsert, FieldTheme.team, .taskInProgress),
                .init("GPS", "送出定位心跳", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("照片", "回報現場照片", "camera.fill", .photoReport, .photoReportUpsert, FieldTheme.info, .photo),
                .init("進場", "進入管制區", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.warning, .safetyCheckIn),
                .init("通訊", "送出小隊訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .volunteer:
            return [
                .init("接收", "確認支援任務", "checkmark.circle.fill", .taskReport, .taskUpsert, FieldTheme.green, .taskAccepted),
                .init("GPS", "送出支援位置", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("照片", "回報現場照片", "camera.fill", .photoReport, .photoReportUpsert, FieldTheme.info, .photo),
                .init("通訊", "送出支援訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .emt, .emtIPad:
            return [
                .init("GPS", "送出 EMT 位置", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("照片", "附加傷患照片", "camera.fill", .patientPhoto, .photoReportUpsert, FieldTheme.info, .photo),
                .init("通訊", "送出醫療訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .ucc, .scc:
            return [
                .init("分區", "預覽分區計畫", "square.3.layers.3d", .sectorCreation, .sectorUpsert, FieldTheme.command, .sectorPlan),
                .init("派任務", "預覽任務派遣", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("通訊", "預覽訊息", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        }
    }

    private var roleAccent: Color {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return FieldTheme.medical
        case .scc, .sccIPad, .ucc:
            return FieldTheme.command
        case .teamLeader, .teamLeaderIPad:
            return FieldTheme.green
        case .teamMember:
            return FieldTheme.team
        case .volunteer:
            return FieldTheme.info
        }
    }

    private var roleIcon: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "cross.case.fill"
        case .scc, .sccIPad, .ucc:
            return "person.3.sequence.fill"
        case .teamLeader, .teamLeaderIPad:
            return "flag.checkered.2.crossed"
        case .teamMember:
            return "figure.run.circle.fill"
        case .volunteer:
            return "hand.raised.fill"
        }
    }

    private var chatMessageForRole: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "EMT 傷患狀態更新"
        case .sccIPad:
            return "SCC 分區狀態更新"
        case .teamLeader, .teamLeaderIPad:
            return "A1 任務狀態更新"
        case .teamMember:
            return "TE 任務進度更新"
        case .volunteer:
            return "VO 支援狀態更新"
        case .ucc, .scc:
            return "指揮預覽訊息"
        }
    }

    private var voiceMessageForRole: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "EMT 語音更新"
        case .teamMember, .volunteer:
            return "現場語音更新"
        default:
            return "指揮語音更新"
        }
    }

    private var photoCaptionForRole: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "傷患照片"
        case .teamLeader, .teamLeaderIPad:
            return "工區概況"
        default:
            return "任務照片"
        }
    }

    private func iconName(for messageType: SyncMessageType) -> String {
        switch messageType {
        case .sectorUpsert, .subSectorUpsert, .worksiteUpsert:
            return "square.3.layers.3d"
        case .personnelStatusUpsert:
            return "person.crop.circle.badge.checkmark"
        case .teamCapabilityReportUpsert:
            return "person.3.sequence.fill"
        case .taskUpsert:
            return "checklist.checked"
        case .photoReportUpsert:
            return "camera.fill"
        case .disasterReportUpsert:
            return "exclamationmark.bubble.fill"
        case .safetyZoneUpsert, .safetyEntryLogUpsert:
            return "exclamationmark.triangle.fill"
        case .groupChatMessageAppend:
            return "message.fill"
        case .voiceReportAppend:
            return "waveform.circle.fill"
        case .sosReportUpsert:
            return "sos.circle.fill"
        case .patientUpsert:
            return "cross.case.fill"
        case .evacuationRequestUpsert:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .hospitalCapacityUpsert:
            return "cross.vial.fill"
        default:
            return "doc.text.fill"
        }
    }

    private func settingsIcon(for key: String) -> String {
        switch key {
        case "app":
            return "app.badge.fill"
        case "device":
            return "iphone.gen3"
        case "version":
            return "number.circle.fill"
        case "build":
            return "hammer.fill"
        case "channel":
            return "dot.radiowaves.left.and.right"
        case "gitTag":
            return "tag.fill"
        case "series":
            return "shippingbox.fill"
        default:
            return "info.circle.fill"
        }
    }

    private func settingsTitle(for item: LinkGuardAppSettingsItem) -> String {
        switch item.key {
        case "app":
            return "應用"
        case "device":
            return "裝置"
        case "version":
            return "版本"
        case "build":
            return "建置"
        case "channel":
            return "通道"
        case "gitTag":
            return "Git 標籤"
        case "series":
            return "系列"
        default:
            return item.title
        }
    }

    private func settingsAccent(for key: String) -> Color {
        switch key {
        case "version", "build", "gitTag":
            return FieldTheme.green
        case "channel", "series":
            return FieldTheme.info
        default:
            return roleAccent
        }
    }

    private func batteryLabel(_ level: Double?) -> String? {
        guard let level else { return nil }
        return "\(Int(level * 100))%"
    }

    private func shortTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum FieldAppTab: String, Identifiable, Hashable {
    case overview
    case operations
    case mapSafety
    case medical
    case comms
    case queue
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "總覽"
        case .operations:
            return "作業"
        case .mapSafety:
            return "地圖"
        case .medical:
            return "醫療"
        case .comms:
            return "通訊"
        case .queue:
            return "離線"
        case .settings:
            return "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2.fill"
        case .operations:
            return "checklist.checked"
        case .mapSafety:
            return "map.fill"
        case .medical:
            return "cross.case.fill"
        case .comms:
            return "message.fill"
        case .queue:
            return "tray.full.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct FieldLaunchIdentityOption: Identifiable, Equatable {
    let code: String
    let title: String
    let detail: String

    var id: String { code }
    var displayLabel: String { "\(code) / \(title)" }

    static func options(for appID: LinkGuardAppID) -> [FieldLaunchIdentityOption] {
        switch appID {
        case .sccIPad:
            return [
                FieldLaunchIdentityOption(code: "SCC-01", title: "現場指揮", detail: "Sector Command"),
                FieldLaunchIdentityOption(code: "SCC-OPS", title: "作業協調", detail: "Operations Coordination"),
                FieldLaunchIdentityOption(code: "SCC-SAFE", title: "安全監控", detail: "Safety Watch")
            ]
        case .teamLeader, .teamMember:
            return [
                FieldLaunchIdentityOption(code: "TL-01", title: "分隊長", detail: "小隊指揮"),
                FieldLaunchIdentityOption(code: "TL-02", title: "副分隊長", detail: "協助指揮"),
                FieldLaunchIdentityOption(code: "TE-01", title: "搜救員", detail: "任務執行")
            ]
        case .teamLeaderIPad:
            return [
                FieldLaunchIdentityOption(code: "TL-01", title: "分隊長", detail: "Team Leader"),
                FieldLaunchIdentityOption(code: "TL-02", title: "副分隊長", detail: "Deputy Team Leader")
            ]
        case .emt, .emtIPad:
            return [
                FieldLaunchIdentityOption(code: "EMT-01", title: "救護組長", detail: "Medical Lead"),
                FieldLaunchIdentityOption(code: "EMT-02", title: "救護員", detail: "Emergency Medical Technician")
            ]
        case .volunteer:
            return [
                FieldLaunchIdentityOption(code: "VO-01", title: "志工", detail: "Volunteer Support"),
                FieldLaunchIdentityOption(code: "VO-02", title: "後勤志工", detail: "Logistics Support")
            ]
        case .ucc, .scc:
            return [
                FieldLaunchIdentityOption(code: "CMD-01", title: "指揮席", detail: "Command Console"),
                FieldLaunchIdentityOption(code: "OPS-01", title: "作業席", detail: "Operations Console")
            ]
        }
    }
}

private struct FieldIdentityPickerOverlay: View {
    let options: [FieldLaunchIdentityOption]
    let accent: Color
    let onSelect: (FieldLaunchIdentityOption) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("選擇啟動身分")
                            .font(.headline)
                        Text("TL/TE 小隊作業身分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option)
                        } label: {
                            HStack(spacing: 12) {
                                Text(option.code)
                                    .font(.caption.monospaced().weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 88, alignment: .center)
                                    .padding(.vertical, 7)
                                    .background(accent, in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(accent)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FieldTheme.raisedSurface, in: RoundedRectangle(cornerRadius: FieldTheme.compactRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 460, alignment: .leading)
            .background(FieldTheme.surface, in: RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
            .padding(FieldTheme.pagePadding)
        }
    }
}

private struct FieldRoleActionDefinition: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let feature: LinkGuardFeature
    let messageType: SyncMessageType
    let accent: Color
    let action: FieldRoleActionKind

    init(_ title: String, _ detail: String, _ systemImage: String, _ feature: LinkGuardFeature, _ messageType: SyncMessageType, _ accent: Color, _ action: FieldRoleActionKind) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.feature = feature
        self.messageType = messageType
        self.accent = accent
        self.action = action
    }
}

private enum FieldRoleActionKind {
    case sectorPlan
    case taskAssignment
    case taskAccepted
    case taskInProgress
    case personnelOnline
    case gps
    case photo
    case safetyZone
    case safetyCheckIn
    case chat
}

private extension FieldRoleActionKind {
    init?(launchToken: String) {
        switch launchToken.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "sectorPlan":
            self = .sectorPlan
        case "taskAssignment":
            self = .taskAssignment
        case "taskAccepted":
            self = .taskAccepted
        case "taskInProgress":
            self = .taskInProgress
        case "personnelOnline":
            self = .personnelOnline
        case "gps":
            self = .gps
        case "photo":
            self = .photo
        case "safetyZone":
            self = .safetyZone
        case "safetyCheckIn":
            self = .safetyCheckIn
        case "chat":
            self = .chat
        default:
            return nil
        }
    }
}

private extension MapDrawingMode {
    var fieldTitle: String {
        switch self {
        case .select:
            return "選取"
        case .point:
            return "點位"
        case .polyline:
            return "路線"
        case .polygon:
            return "區域"
        }
    }

    var fieldIconName: String {
        switch self {
        case .select:
            return "cursorarrow.click.2"
        case .point:
            return "mappin.circle.fill"
        case .polyline:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .polygon:
            return "skew"
        }
    }

    var fieldAccent: Color {
        switch self {
        case .select:
            return FieldTheme.command
        case .point:
            return FieldTheme.green
        case .polyline:
            return FieldTheme.info
        case .polygon:
            return FieldTheme.warning
        }
    }
}

private extension HomeSurface {
    var fieldDisplayName: String {
        switch self {
        case .globalCommand:
            return "全域指揮"
        case .sectorCommand:
            return "分區指揮"
        case .teamBriefing:
            return "小隊簡報"
        case .taskList:
            return "任務列表"
        case .volunteerSafety:
            return "志工安全"
        case .medicalTriage:
            return "醫療檢傷"
        }
    }
}

private extension CommandAuthorityLevel {
    var fieldDisplayName: String {
        switch self {
        case .none:
            return "無指揮權"
        case .selfReport:
            return "自我回報"
        case .team:
            return "小隊指揮"
        case .sector:
            return "分區指揮"
        case .incident:
            return "事故指揮"
        case .global:
            return "全域指揮"
        }
    }
}

private extension MedicalAccessLevel {
    var fieldDisplayName: String {
        switch self {
        case .none:
            return "無"
        case .summary:
            return "摘要"
        case .operational:
            return "作業"
        case .fullClinical:
            return "臨床"
        }
    }
}

private extension LinkGuardPermission {
    var fieldDisplayName: String { rawValue.fieldTitle }
}

private extension SyncMessageType {
    var fieldDisplayName: String {
        switch self {
        case .incidentUpsert:
            return "事故資料"
        case .sectorUpsert:
            return "分區資料"
        case .subSectorUpsert:
            return "子分區資料"
        case .worksiteUpsert:
            return "工區資料"
        case .personnelStatusUpsert:
            return "人員狀態"
        case .teamCapabilityReportUpsert:
            return "小隊能量"
        case .roleAssignmentUpsert:
            return "角色派任"
        case .commandUpsert:
            return "指揮命令"
        case .taskUpsert:
            return "任務更新"
        case .operationalPeriodUpsert:
            return "作業期程"
        case .photoReportUpsert:
            return "照片回報"
        case .disasterReportUpsert:
            return "災情回報"
        case .agencyMessageUpsert:
            return "機關訊息"
        case .ceocMissionUpsert:
            return "CEOC 任務"
        case .safetyZoneUpsert:
            return "安全區"
        case .safetyEntryLogUpsert:
            return "進出紀錄"
        case .groupChatMessageAppend:
            return "群組訊息"
        case .voiceReportAppend:
            return "語音回報"
        case .alertUpsert:
            return "警示"
        case .alertAcknowledgementUpsert:
            return "警示確認"
        case .sosReportUpsert:
            return "SOS 回報"
        case .mapFeatureUpsert:
            return "地圖標註"
        case .patientUpsert:
            return "傷患資料"
        case .patientOperationalSummaryUpsert:
            return "傷患作業摘要"
        case .evacuationRequestUpsert:
            return "後送需求"
        case .hospitalCapacityUpsert:
            return "醫院量能"
        case .purchaseRequestUpsert:
            return "採購需求"
        case .personnelHoursUpsert:
            return "人員工時"
        case .decisionRecordUpsert:
            return "決策紀錄"
        case .auditEventAppend:
            return "稽核事件"
        }
    }
}

private extension LinkGuardFeature {
    var fieldDisplayName: String { rawValue.fieldTitle }

    var fieldIconName: String {
        switch self {
        case .gpsTracking, .teamMemberRealtimeLocation, .teamLeaderRealtimeLocation, .emtLocationManagement, .lastLocationTracking:
            return "location.fill"
        case .photoReport, .multiPointPhotoReport, .photoWall, .liveFieldPhoto, .patientPhoto:
            return "camera.fill"
        case .patientCreation, .startTriage, .patientLocation, .patientStatusUpdate, .medicalEvacuation, .hospitalCapacityView, .patientHistory, .aiPatientWarning, .medicalCapacityAnalysis:
            return "cross.case.fill"
        case .communicationChannel, .radioMonitoring, .speechTranscription, .voiceReport, .realtimeTranslation, .voiceTranslation, .aiChat:
            return "message.fill"
        case .hazardWarning, .hazardZoneManagement, .safetyControlBoard, .sosSending, .sosDetail, .fieldSafetyRealtimeManagement, .structuralHazardMonitoring, .secondaryCollapseWarning:
            return "exclamationmark.triangle.fill"
        case .pointMarker, .lineMarker, .areaMarker, .globalMapOverview, .offlineMap, .searchAreaManagement, .clearedAreaMarking, .searchRouteManagement, .evacuationRouteManagement:
            return "map.fill"
        case .taskAssignment, .taskReport, .commandDispatch, .quickCommand:
            return "checklist.checked"
        default:
            return "checkmark.seal.fill"
        }
    }
}

private extension FeatureAccessLevel {
    var fieldDisplayName: String {
        switch self {
        case .none:
            return "不可用"
        case .limited:
            return "受限"
        case .primary:
            return "主要"
        }
    }

    var fieldShortLabel: String {
        switch self {
        case .none:
            return "無"
        case .limited:
            return "受限"
        case .primary:
            return "主要"
        }
    }

    var fieldAccentColor: Color {
        switch self {
        case .none:
            return FieldTheme.warning
        case .limited:
            return FieldTheme.info
        case .primary:
            return FieldTheme.green
        }
    }
}

private extension String {
    var fieldTitle: String {
        var output = ""
        for character in self {
            if character.isUppercase && output.isEmpty == false {
                output.append(" ")
            }
            output.append(character)
        }
        guard let first = output.first else { return output }
        return first.uppercased() + String(output.dropFirst())
    }
}
