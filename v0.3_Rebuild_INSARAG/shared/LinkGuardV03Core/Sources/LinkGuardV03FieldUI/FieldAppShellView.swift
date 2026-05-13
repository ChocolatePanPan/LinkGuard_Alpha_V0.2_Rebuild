import LinkGuardV03Core
import SwiftUI

public struct FieldAppShellView: View {
    @State private var controller: FieldAppController
    @State private var selectedTab: FieldAppTab = .overview
    @State private var statusText = "Ready"
    @State private var statusAccent = FieldTheme.green

    public init(appID: LinkGuardAppID, platform: AppPlatform, deviceID: LinkGuardID, displayName: String) {
        _controller = State(initialValue: FieldAppController(appID: appID, platform: platform, deviceID: deviceID, displayName: displayName))
    }

    public var body: some View {
        NavigationStack {
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
            .navigationTitle(controller.profile.displayName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Text(LinkGuardVersionInfo.current.displayVersion)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(FieldTheme.green)
        .preferredColorScheme(.dark)
    }

    private var availableTabs: [FieldAppTab] {
        var tabs: [FieldAppTab] = [.overview, .operations, .mapSafety, .comms, .queue]
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
        }
    }

    private var fieldHeader: some View {
        FieldPanel(accent: roleAccent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: roleIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(roleAccent)
                        .frame(width: 42, height: 42)
                        .background(roleAccent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.runtime.device.displayName)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(controller.roleWorkflowTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(roleAccent)
                        Text(controller.context.worksiteID.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("OUTBOX")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(controller.pendingEnvelopeCount)")
                            .font(.title3.weight(.bold).monospacedDigit())
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FieldStatusPill(title: statusText, systemImage: "checkmark.seal.fill", accent: statusAccent)
                        FieldStatusPill(title: controller.latestGPSFix == nil ? "No GPS" : "GPS Ready", systemImage: "location.fill", accent: controller.latestGPSFix == nil ? FieldTheme.warning : FieldTheme.green)
                        FieldStatusPill(title: controller.blueprint.homeSurface.fieldDisplayName, systemImage: "rectangle.3.group.fill", accent: FieldTheme.info)
                        FieldStatusPill(title: controller.profile.commandAuthority.fieldDisplayName, systemImage: "person.badge.key.fill", accent: FieldTheme.command)
                    }
                }
            }
        }
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: FieldTheme.panelSpacing) {
            missionOverview
            priorityActionPanel
            inboxPanel
            personnelPanel
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

    private var missionOverview: some View {
        let summary = controller.missionSummary
        return FieldPanel("Mission", systemImage: "scope", accent: roleAccent) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.incidentName)
                        .font(.headline)
                    Text(controller.roleWorkflowSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                FieldAdaptiveGrid(minimum: 142) {
                    FieldMetricTile(title: "Open Tasks", value: "\(summary.openTaskCount)", systemImage: "checklist.checked", accent: FieldTheme.green)
                    FieldMetricTile(title: "Online", value: "\(summary.onlinePersonnelCount)/\(summary.personnelCount)", systemImage: "person.3.fill", accent: FieldTheme.team)
                    FieldMetricTile(title: "Safety", value: "\(summary.safetyZoneCount)", systemImage: "shield.lefthalf.filled", accent: FieldTheme.warning)
                    FieldMetricTile(title: "Reports", value: "\(summary.photoReportCount + summary.disasterReportCount)", systemImage: "camera.fill", accent: FieldTheme.info)
                    FieldMetricTile(title: "Patients", value: "\(summary.patientCount)", systemImage: "cross.case.fill", accent: FieldTheme.medical)
                    FieldMetricTile(title: "SOS", value: "\(summary.sosCount)", systemImage: "sos.circle.fill", accent: FieldTheme.danger)
                }
            }
        }
    }

    private var priorityActionPanel: some View {
        FieldPanel("Priority Actions", systemImage: "bolt.fill", accent: FieldTheme.danger) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("SOS", detail: "Queue location + danger report", systemImage: "sos.circle.fill", feature: .sosSending, messageType: .sosReportUpsert, accent: FieldTheme.danger) {
                    try controller.queueSOS(dangerType: controller.runtime.device.appID == .emt ? .injured : .trapped, note: "Field SOS", now: Date())
                }
                fieldAction("GPS", detail: "Send current field position", systemImage: "location.fill", feature: .gpsTracking, messageType: .personnelStatusUpsert, accent: FieldTheme.green) {
                    try controller.queueGPSReport(now: Date())
                }
                fieldAction("Voice", detail: "Push a voice status report", systemImage: "waveform.circle.fill", feature: .voiceReport, messageType: .voiceReportAppend, accent: FieldTheme.team) {
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
        return FieldPanel("Tasks", systemImage: "checklist.checked", accent: FieldTheme.green) {
            VStack(spacing: 8) {
                if tasks.isEmpty {
                    emptyRow("No task assigned", systemImage: "checklist.unchecked")
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
        FieldPanel("Workflow", systemImage: "point.topleft.down.curvedto.point.bottomright.up", accent: FieldTheme.info) {
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
        FieldPanel("Received", systemImage: "tray.full", accent: FieldTheme.info) {
            VStack(spacing: 8) {
                if controller.inboxItems.isEmpty {
                    emptyRow("No incoming items", systemImage: "tray")
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
        return FieldPanel("Personnel", systemImage: "person.3.fill", accent: FieldTheme.team) {
            VStack(spacing: 8) {
                if statuses.isEmpty {
                    emptyRow("No personnel heartbeat", systemImage: "person.crop.circle.badge.questionmark")
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
        FieldPanel("Map", systemImage: "map.fill", accent: FieldTheme.green) {
            VStack(alignment: .leading, spacing: 12) {
                if let fix = controller.latestGPSFix {
                    FieldTimelineRow(
                        title: "Current GPS fix",
                        detail: "\(fix.coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(fix.coordinate.longitude.formatted(.number.precision(.fractionLength(4)))) / \(fix.source.rawValue)",
                        systemImage: "location.fill",
                        accent: FieldTheme.green,
                        trailing: fix.coordinate.accuracyMeters.map { "±\(Int($0))m" }
                    )
                } else {
                    emptyRow("No GPS fix available", systemImage: "location.slash")
                }
                FieldAdaptiveGrid(minimum: 158) {
                    fieldAction("Point", detail: "Victim or marker point", systemImage: "mappin.circle.fill", feature: .pointMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.green) {
                        try controller.queueMapMarker(featureType: .victimPoint, geometryType: .point, title: "Field point", now: Date())
                    }
                    fieldAction("Route", detail: "Polyline route marker", systemImage: "point.topleft.down.curvedto.point.bottomright.up", feature: .lineMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.info) {
                        try controller.queueMapMarker(featureType: .evacuationRoute, geometryType: .polyline, title: "Evacuation route", now: Date())
                    }
                    fieldAction("Area", detail: "Polygon hazard marker", systemImage: "skew", feature: .areaMarker, messageType: .mapFeatureUpsert, accent: FieldTheme.warning) {
                        try controller.queueMapMarker(featureType: .collapsedAreaPolygon, geometryType: .polygon, title: "Hazard area", now: Date())
                    }
                }
            }
        }
    }

    private var safetyPanel: some View {
        FieldPanel("Safety Control", systemImage: "shield.lefthalf.filled", accent: FieldTheme.warning) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("Hot Zone", detail: "Publish active danger zone", systemImage: "exclamationmark.triangle.fill", feature: .hazardZoneManagement, messageType: .safetyZoneUpsert, accent: FieldTheme.warning) {
                    try controller.queueSafetyZone(now: Date())
                }
                fieldAction("Check In", detail: "Record entering controlled zone", systemImage: "figure.walk.arrival", feature: .personnelEntryLog, messageType: .safetyEntryLogUpsert, accent: FieldTheme.green) {
                    try controller.queueSafetyEntry(.checkIn, now: Date())
                }
                fieldAction("Check Out", detail: "Record leaving controlled zone", systemImage: "figure.walk.departure", feature: .personnelEntryLog, messageType: .safetyEntryLogUpsert, accent: FieldTheme.info) {
                    try controller.queueSafetyEntry(.checkOut, now: Date())
                }
            }
        }
    }

    private var communicationPanel: some View {
        FieldPanel("Comms", systemImage: "message.fill", accent: FieldTheme.team) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("Chat", detail: "Queue group message", systemImage: "message.fill", feature: .communicationChannel, messageType: .groupChatMessageAppend, accent: FieldTheme.team) {
                    try controller.queueGroupChat(body: chatMessageForRole, now: Date())
                }
                fieldAction("Voice", detail: "Queue audio/transcript report", systemImage: "waveform.circle.fill", feature: .voiceReport, messageType: .voiceReportAppend, accent: FieldTheme.green) {
                    try controller.queueVoiceReport(transcript: voiceMessageForRole, durationSeconds: 6, now: Date())
                }
                fieldAction("Photo", detail: "Queue photo + GPS evidence", systemImage: "camera.fill", feature: .photoReport, messageType: .photoReportUpsert, accent: FieldTheme.info) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "ATTACH"), caption: photoCaptionForRole, checksum: nil, now: Date())
                }
            }
        }
    }

    private var reportPanel: some View {
        FieldPanel("Field Reports", systemImage: "doc.text.image.fill", accent: FieldTheme.info) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("Collapse", detail: "Report structural collapse", systemImage: "exclamationmark.bubble.fill", feature: .disasterReport, messageType: .disasterReportUpsert, accent: FieldTheme.warning) {
                    try controller.queueDisasterReport(kind: .collapse, summary: "Collapse report", now: Date())
                }
                fieldAction("Fire", detail: "Report active fire", systemImage: "flame.fill", feature: .disasterReport, messageType: .disasterReportUpsert, accent: FieldTheme.danger) {
                    try controller.queueDisasterReport(kind: .fire, severity: .critical, summary: "Active fire observed", now: Date())
                }
            }
        }
    }

    private var medicalOverviewPanel: some View {
        FieldPanel("Medical Flow", systemImage: "cross.case.fill", accent: FieldTheme.medical) {
            VStack(spacing: 8) {
                ForEach(controller.emtMedicalPhases) { phase in
                    FieldTimelineRow(title: phase.moduleName, detail: phase.capability, systemImage: "cross.case.fill", accent: FieldTheme.medical, trailing: phase.label)
                }
            }
        }
    }

    private var medicalActionPanel: some View {
        FieldPanel("Patient Actions", systemImage: "heart.text.square.fill", accent: FieldTheme.medical) {
            FieldAdaptiveGrid(minimum: 158) {
                fieldAction("Patient", detail: "Create field patient record", systemImage: "cross.case.fill", feature: .patientCreation, messageType: .patientUpsert, accent: FieldTheme.medical) {
                    try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: Date())
                }
                fieldAction("START", detail: "Record START triage", systemImage: "waveform.path.ecg", feature: .startTriage, messageType: .patientUpsert, accent: FieldTheme.danger) {
                    try controller.queueStartTriage(displayCode: "A023", category: .red, respiratoryRate: 28, pulseRate: 120, gcs: 14, injurySummary: "Leg bleed", now: Date())
                }
                fieldAction("Vitals", detail: "Update triage and vitals", systemImage: "heart.text.square.fill", feature: .patientStatusUpdate, messageType: .patientUpsert, accent: FieldTheme.warning) {
                    try controller.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "Tourniquet applied", now: Date())
                }
                fieldAction("Evac", detail: "Request patient evacuation", systemImage: "arrow.triangle.2.circlepath.circle.fill", feature: .medicalEvacuation, messageType: .evacuationRequestUpsert, accent: FieldTheme.info) {
                    try controller.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: Date())
                }
                fieldAction("Hospital", detail: "Publish capacity update", systemImage: "cross.vial.fill", feature: .hospitalCapacityView, messageType: .hospitalCapacityUpsert, accent: FieldTheme.green) {
                    try controller.queueHospitalCapacityUpdate(emergencyCapacity: 8, traumaCapacity: 3, burnCapacity: 1, pediatricCapacity: 2, now: Date())
                }
                fieldAction("Patient Photo", detail: "Attach patient evidence", systemImage: "camera.fill", feature: .patientPhoto, messageType: .photoReportUpsert, accent: FieldTheme.info) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "PATIENT-PHOTO"), caption: "Patient photo", checksum: nil, now: Date())
                }
            }
        }
    }

    private var outboxPanel: some View {
        FieldPanel("Offline Queue", systemImage: "tray.full", accent: FieldTheme.green) {
            VStack(spacing: 8) {
                if controller.queuedSummaries.isEmpty {
                    emptyRow("No queued envelopes", systemImage: "tray")
                } else {
                    ForEach(controller.queuedSummaries) { item in
                        FieldTimelineRow(
                            title: item.messageType.rawValue,
                            detail: "Queued for sync / \(item.id.rawValue)",
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
        FieldPanel("Event Log", systemImage: "clock.arrow.circlepath", accent: FieldTheme.info) {
            VStack(spacing: 8) {
                let events = controller.runtime.snapshot.auditEvents.suffix(8).reversed()
                if events.isEmpty {
                    emptyRow("No local audit events yet", systemImage: "clock")
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
            statusText = "Queued \(title)"
            statusAccent = FieldTheme.green
        } catch {
            statusText = "Blocked \(title)"
            statusAccent = FieldTheme.warning
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
            return "SCC iPad Sector Control"
        case .teamLeader, .teamLeaderIPad:
            return "TL Worksite Command"
        case .teamMember:
            return "TE Task Execution"
        case .volunteer:
            return "VO Support Loop"
        case .emt, .emtIPad:
            return "EMT Field Support"
        case .ucc, .scc:
            return "Command Preview"
        }
    }

    private var roleActionDefinitions: [FieldRoleActionDefinition] {
        switch controller.runtime.device.appID {
        case .sccIPad:
            return [
                .init("Sector", "Create sector/sub-sector/worksite", "square.3.layers.3d", .sectorCreation, .sectorUpsert, FieldTheme.command, .sectorPlan),
                .init("Dispatch", "Assign task to team", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("Personnel", "Publish online personnel status", "person.3.fill", .personnelOverview, .personnelStatusUpsert, FieldTheme.team, .personnelOnline),
                .init("Safety", "Publish hot zone", "shield.lefthalf.filled", .safetyControlBoard, .safetyZoneUpsert, FieldTheme.warning, .safetyZone),
                .init("Check In", "Record entry control", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.info, .safetyCheckIn),
                .init("Chat", "Send sector message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .teamLeader, .teamLeaderIPad:
            return [
                .init("Worksite", "Create A1 worksite plan", "square.3.layers.3d", .worksiteMarkerSystem, .worksiteUpsert, FieldTheme.command, .sectorPlan),
                .init("Dispatch", "Assign team task", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("In Progress", "Update task status", "figure.run.circle.fill", .taskReport, .taskUpsert, FieldTheme.team, .taskInProgress),
                .init("Safety", "Publish hazard zone", "exclamationmark.triangle.fill", .hazardZoneManagement, .safetyZoneUpsert, FieldTheme.warning, .safetyZone),
                .init("Entry", "Check into hot zone", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.info, .safetyCheckIn),
                .init("Chat", "Send team message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .teamMember:
            return [
                .init("Accept", "Accept assigned task", "checkmark.circle.fill", .taskReport, .taskUpsert, FieldTheme.green, .taskAccepted),
                .init("Working", "Mark task in progress", "figure.run.circle.fill", .taskReport, .taskUpsert, FieldTheme.team, .taskInProgress),
                .init("GPS", "Send location heartbeat", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("Photo", "Report photo evidence", "camera.fill", .photoReport, .photoReportUpsert, FieldTheme.info, .photo),
                .init("Entry", "Check into zone", "figure.walk.arrival", .personnelEntryLog, .safetyEntryLogUpsert, FieldTheme.warning, .safetyCheckIn),
                .init("Chat", "Send team message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .volunteer:
            return [
                .init("Accept", "Confirm support task", "checkmark.circle.fill", .taskReport, .taskUpsert, FieldTheme.green, .taskAccepted),
                .init("GPS", "Send support location", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("Photo", "Report scene photo", "camera.fill", .photoReport, .photoReportUpsert, FieldTheme.info, .photo),
                .init("Chat", "Send support message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .emt, .emtIPad:
            return [
                .init("GPS", "Send EMT location", "location.fill", .gpsTracking, .personnelStatusUpsert, FieldTheme.green, .gps),
                .init("Photo", "Attach patient photo", "camera.fill", .patientPhoto, .photoReportUpsert, FieldTheme.info, .photo),
                .init("Chat", "Send medical message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
            ]
        case .ucc, .scc:
            return [
                .init("Sector", "Preview sector plan", "square.3.layers.3d", .sectorCreation, .sectorUpsert, FieldTheme.command, .sectorPlan),
                .init("Dispatch", "Preview task dispatch", "paperplane.fill", .taskAssignment, .taskUpsert, FieldTheme.green, .taskAssignment),
                .init("Chat", "Preview message", "message.fill", .communicationChannel, .groupChatMessageAppend, FieldTheme.team, .chat)
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
            return "EMT patient status update"
        case .sccIPad:
            return "SCC sector update"
        case .teamLeader, .teamLeaderIPad:
            return "A1 task status update"
        case .teamMember:
            return "TE task progress update"
        case .volunteer:
            return "VO support update"
        case .ucc, .scc:
            return "Command preview message"
        }
    }

    private var voiceMessageForRole: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "EMT voice update"
        case .teamMember, .volunteer:
            return "Field voice update"
        default:
            return "Command voice update"
        }
    }

    private var photoCaptionForRole: String {
        switch controller.runtime.device.appID {
        case .emt, .emtIPad:
            return "Patient photo"
        case .teamLeader, .teamLeaderIPad:
            return "Worksite overview"
        default:
            return "Task photo"
        }
    }

    private func iconName(for messageType: SyncMessageType) -> String {
        switch messageType {
        case .sectorUpsert, .subSectorUpsert, .worksiteUpsert:
            return "square.3.layers.3d"
        case .personnelStatusUpsert:
            return "person.crop.circle.badge.checkmark"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .operations:
            return "Ops"
        case .mapSafety:
            return "Map"
        case .medical:
            return "Medical"
        case .comms:
            return "Comms"
        case .queue:
            return "Queue"
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

private extension HomeSurface {
    var fieldDisplayName: String {
        switch self {
        case .globalCommand:
            return "Global Command"
        case .sectorCommand:
            return "Sector Command"
        case .teamBriefing:
            return "Team Briefing"
        case .taskList:
            return "Task List"
        case .volunteerSafety:
            return "Volunteer Safety"
        case .medicalTriage:
            return "Medical Triage"
        }
    }
}

private extension CommandAuthorityLevel {
    var fieldDisplayName: String {
        switch self {
        case .none:
            return "No command"
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