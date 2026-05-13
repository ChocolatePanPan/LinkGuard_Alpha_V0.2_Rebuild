import LinkGuardV03Core
import SwiftUI

public struct FieldAppShellView: View {
    @State private var controller: FieldAppController
    @State private var statusText = "Ready"

    public init(appID: LinkGuardAppID, platform: AppPlatform, deviceID: LinkGuardID, displayName: String) {
        _controller = State(initialValue: FieldAppController(appID: appID, platform: platform, deviceID: deviceID, displayName: displayName))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    missionOverview
                    roleWorkflowActions
                    outboundQueue
                }
                .padding(16)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.runtime.device.displayName)
                        .font(.title2.weight(.bold))
                    Text(controller.context.worksiteID.rawValue)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(controller.pendingEnvelopeCount)", systemImage: "tray.full")
                    .font(.headline.monospacedDigit())
            }

            HStack(spacing: 8) {
                statusChip(title: statusText, systemImage: "checkmark.seal.fill")
                statusChip(title: controller.latestGPSFix == nil ? "No GPS" : "GPS Ready", systemImage: "location.fill")
                statusChip(title: controller.roleWorkflowTitle, systemImage: "person.text.rectangle.fill")
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var missionOverview: some View {
        let summary = controller.missionSummary
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.incidentName)
                    .font(.headline)
                Text(controller.roleWorkflowSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                metricTile("Tasks", value: "\(summary.openTaskCount)", systemImage: "checklist.checked")
                metricTile("People", value: "\(summary.onlinePersonnelCount)/\(summary.personnelCount)", systemImage: "person.3.fill")
                metricTile("Safety", value: "\(summary.safetyZoneCount)", systemImage: "shield.lefthalf.filled")
                metricTile("Reports", value: "\(summary.photoReportCount + summary.disasterReportCount + summary.sosCount)", systemImage: "tray.full")
            }
            if controller.inboxItems.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Received")
                        .font(.subheadline.weight(.semibold))
                    ForEach(controller.inboxItems) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.systemImageName)
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(priorityTitle(item.priority))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var roleWorkflowActions: some View {
        switch controller.runtime.device.appID {
        case .sccIPad:
            sccIPadActions
        case .teamLeader, .teamLeaderIPad:
            teamLeaderActions
            medicalActions
        case .teamMember, .volunteer:
            responderActions
        case .emt, .emtIPad:
            emtActions
        case .ucc, .scc:
            commandPreviewActions
        }
    }

    private var commandPreviewActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Command Preview")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Sector", systemImage: "square.3.layers.3d", feature: .sectorCreation, enabled: controller.canSend(.sectorUpsert)) {
                    try controller.queueSectorPlan(now: Date()).last
                }
                actionButton("Dispatch", systemImage: "paperplane.fill", feature: .taskAssignment, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskAssignment(now: Date())
                }
                actionButton("SOS", systemImage: "sos.circle.fill", feature: .sosDetail, enabled: controller.canSend(.sosReportUpsert)) {
                    try controller.queueSOS(dangerType: .trapped, note: "Command SOS drill", now: Date())
                }
            }
        }
    }

    private var sccIPadActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCC iPad")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Sector", systemImage: "square.3.layers.3d", feature: .sectorCreation, enabled: controller.canSeeFeature(.subSectorCreation) && controller.canSeeFeature(.worksiteMarkerSystem) && controller.canSend(.sectorUpsert) && controller.canSend(.subSectorUpsert) && controller.canSend(.worksiteUpsert)) {
                    try controller.queueSectorPlan(now: Date()).last
                }
                actionButton("Dispatch", systemImage: "paperplane.fill", feature: .taskAssignment, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskAssignment(now: Date())
                }
                actionButton("Personnel", systemImage: "person.3.fill", feature: .personnelOverview, enabled: controller.canSend(.personnelStatusUpsert)) {
                    try controller.queuePersonnelStatus(operationalState: .assigned, connectivity: .online, batteryLevel: 0.91, now: Date())
                }
                actionButton("Safety", systemImage: "shield.lefthalf.filled", feature: .safetyControlBoard, enabled: controller.canSend(.safetyZoneUpsert)) {
                    try controller.queueSafetyZone(now: Date())
                }
                actionButton("Area", systemImage: "skew", feature: .areaMarker, enabled: controller.canSend(.mapFeatureUpsert)) {
                    try controller.queueMapMarker(featureType: .collapsedAreaPolygon, geometryType: .polygon, title: "Hazard area", now: Date())
                }
                actionButton("Chat", systemImage: "message.fill", feature: .communicationChannel, enabled: controller.canSend(.groupChatMessageAppend)) {
                    try controller.queueGroupChat(body: "SCC sector update", now: Date())
                }
            }
        }
    }

    private var teamLeaderActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TL Field Loop")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Worksite", systemImage: "square.3.layers.3d", feature: .worksiteMarkerSystem, enabled: controller.canSend(.sectorUpsert) && controller.canSend(.worksiteUpsert)) {
                    try controller.queueSectorPlan(now: Date()).last
                }
                actionButton("Dispatch", systemImage: "paperplane.fill", feature: .taskAssignment, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskAssignment(now: Date())
                }
                actionButton("Task Update", systemImage: "checklist.checked", feature: .taskReport, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskStatus(.inProgress, now: Date())
                }
                actionButton("Zone", systemImage: "exclamationmark.triangle.fill", feature: .hazardZoneManagement, enabled: controller.canSend(.safetyZoneUpsert)) {
                    try controller.queueSafetyZone(now: Date())
                }
                actionButton("Check In", systemImage: "figure.walk.arrival", feature: .personnelEntryLog, enabled: controller.canSend(.safetyEntryLogUpsert)) {
                    try controller.queueSafetyEntry(.checkIn, now: Date())
                }
                actionButton("Chat", systemImage: "message.fill", feature: .communicationChannel, enabled: controller.canSend(.groupChatMessageAppend)) {
                    try controller.queueGroupChat(body: "A1 status update", now: Date())
                }
            }
        }
    }

    private var responderActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.runtime.device.appID == .volunteer ? "VO Support Loop" : "TE Task Loop")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Accept", systemImage: "checkmark.circle.fill", feature: .taskReport, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskStatus(.accepted, now: Date())
                }
                actionButton("Working", systemImage: "figure.run.circle.fill", feature: .taskReport, enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskStatus(.inProgress, now: Date())
                }
                actionButton("GPS", systemImage: "location.fill", feature: .gpsTracking, enabled: controller.canSend(.personnelStatusUpsert)) {
                    try controller.queueGPSReport(now: Date())
                }
                actionButton("Photo", systemImage: "camera.fill", feature: .photoReport, enabled: controller.canSend(.photoReportUpsert)) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "ATTACH"), caption: "Task photo", checksum: nil, now: Date())
                }
                actionButton("Disaster", systemImage: "exclamationmark.bubble.fill", feature: .disasterReport, enabled: controller.canSend(.disasterReportUpsert)) {
                    try controller.queueDisasterReport(kind: .collapse, summary: "Collapse report", now: Date())
                }
                actionButton("Point", systemImage: "mappin.circle.fill", feature: .pointMarker, enabled: controller.canSend(.mapFeatureUpsert)) {
                    try controller.queueMapMarker(featureType: .victimPoint, geometryType: .point, title: "Field point", now: Date())
                }
                actionButton("Voice", systemImage: "waveform.circle.fill", feature: .voiceReport, enabled: controller.canSend(.voiceReportAppend)) {
                    try controller.queueVoiceReport(transcript: "Field voice update", durationSeconds: 5, now: Date())
                }
                actionButton("SOS", systemImage: "sos.circle.fill", feature: .sosSending, enabled: controller.canSend(.sosReportUpsert)) {
                    try controller.queueSOS(dangerType: .trapped, note: "Field SOS", now: Date())
                }
            }
        }
    }

    private var emtActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EMT Medical Loop")
                .font(.headline)
            emtPhaseOverview
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("GPS", systemImage: "location.fill", feature: .gpsTracking, enabled: controller.canSend(.personnelStatusUpsert)) {
                    try controller.queueGPSReport(now: Date())
                }
                actionButton("Patient", systemImage: "cross.case.fill", feature: .patientCreation, enabled: controller.canSend(.patientUpsert)) {
                    try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: Date())
                }
                actionButton("START", systemImage: "waveform.path.ecg", feature: .startTriage, enabled: controller.canSend(.patientUpsert)) {
                    try controller.queueStartTriage(displayCode: "A023", category: .red, respiratoryRate: 28, pulseRate: 120, gcs: 14, injurySummary: "Leg bleed", now: Date())
                }
                actionButton("Vitals", systemImage: "heart.text.square.fill", feature: .patientStatusUpdate, enabled: controller.canSend(.patientUpsert)) {
                    try controller.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "Tourniquet applied", now: Date())
                }
                actionButton("Evac", systemImage: "arrow.triangle.2.circlepath.circle.fill", feature: .medicalEvacuation, enabled: controller.canSend(.evacuationRequestUpsert)) {
                    try controller.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: Date())
                }
                actionButton("Hospitals", systemImage: "cross.vial.fill", feature: .hospitalCapacityView, enabled: controller.canSend(.hospitalCapacityUpsert)) {
                    try controller.queueHospitalCapacityUpdate(emergencyCapacity: 8, traumaCapacity: 3, burnCapacity: 1, pediatricCapacity: 2, now: Date())
                }
                actionButton("Photo", systemImage: "camera.fill", feature: .patientPhoto, enabled: controller.canSend(.photoReportUpsert)) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "PATIENT-PHOTO"), caption: "Patient photo", checksum: nil, now: Date())
                }
                actionButton("Voice", systemImage: "waveform.circle.fill", feature: .voiceReport, enabled: controller.canSend(.voiceReportAppend)) {
                    try controller.queueVoiceReport(transcript: "EMT voice update", durationSeconds: 6, now: Date())
                }
                actionButton("SOS", systemImage: "sos.circle.fill", feature: .sosSending, enabled: controller.canSend(.sosReportUpsert)) {
                    try controller.queueSOS(dangerType: .injured, note: "Medical SOS", now: Date())
                }
            }
        }
    }

    private var emtPhaseOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(LinkGuardEMTMedicalVersion.appName) / \(LinkGuardEMTMedicalVersion.editionName)")
                        .font(.subheadline.weight(.semibold))
                    Text(LinkGuardEMTMedicalVersion.corePositioning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(controller.executableEMTMedicalPhases.count)/\(controller.emtMedicalPhases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 8)], spacing: 8) {
                ForEach(controller.emtMedicalPhases) { phase in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phase.label)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(phase.moduleName)
                            .font(.subheadline.weight(.semibold))
                        Text(phase.capability)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var medicalActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.canSeeFeature(.patientCreation) || controller.canSeeFeature(.startTriage) || controller.canSeeFeature(.patientStatusUpdate) || controller.canSeeFeature(.medicalEvacuation) {
                Text("TL Medical Support")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    actionButton("Patient", systemImage: "cross.case.fill", feature: .patientCreation, enabled: controller.canSend(.patientUpsert)) {
                        try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: Date())
                    }
                    actionButton("START", systemImage: "waveform.path.ecg", feature: .startTriage, enabled: controller.canSend(.patientUpsert)) {
                        try controller.queueStartTriage(displayCode: "A023", category: .red, respiratoryRate: 28, pulseRate: 120, gcs: 14, injurySummary: "Leg bleed", now: Date())
                    }
                    actionButton("Patient Status", systemImage: "heart.text.square.fill", feature: .patientStatusUpdate, enabled: controller.canSend(.patientUpsert)) {
                        try controller.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "Tourniquet applied", now: Date())
                    }
                    actionButton("Evac", systemImage: "arrow.triangle.2.circlepath.circle.fill", feature: .medicalEvacuation, enabled: controller.canSend(.evacuationRequestUpsert)) {
                        try controller.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: Date())
                    }
                }
            }
        }
    }

    private var outboundQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outbox")
                .font(.headline)
            if controller.queuedSummaries.isEmpty {
                Text("No queued envelopes")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(controller.queuedSummaries) { item in
                    HStack {
                        Image(systemName: iconName(for: item.messageType))
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.messageType.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Text(priorityTitle(item.priority))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, feature: LinkGuardFeature, enabled: Bool, operation: @escaping () throws -> SyncEnvelope?) -> some View {
        if controller.canSeeFeature(feature) {
            Button {
                do {
                    _ = try operation()
                    statusText = "Queued"
                } catch {
                    statusText = "Blocked"
                }
            } label: {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(enabled == false || controller.canUseFeature(feature) == false)
        }
    }

    private func statusChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
    }

    private func metricTile(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
        default:
            return "doc.text.fill"
        }
    }

    private func priorityTitle(_ priority: PriorityLevel) -> String {
        switch priority {
        case .routine:
            return "routine"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .critical:
            return "critical"
        }
    }
}