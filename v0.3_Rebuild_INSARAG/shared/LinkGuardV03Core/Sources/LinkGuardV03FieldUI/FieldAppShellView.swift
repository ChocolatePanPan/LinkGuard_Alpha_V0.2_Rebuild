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
                    primaryActions
                    phaseTwoActions
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
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Primary")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Status", systemImage: "person.crop.circle.badge.checkmark", enabled: controller.canSend(.personnelStatusUpsert)) {
                    try controller.queuePersonnelStatus(operationalState: .inWorksite, connectivity: .online, batteryLevel: 0.82, now: Date())
                }
                actionButton("SOS", systemImage: "sos.circle.fill", enabled: controller.canSend(.sosReportUpsert)) {
                    try controller.queueSOS(dangerType: .trapped, note: "Field SOS", now: Date())
                }
                actionButton("Voice", systemImage: "waveform.circle.fill", enabled: controller.canSend(.voiceReportAppend)) {
                    try controller.queueVoiceReport(transcript: "Need support at A1", durationSeconds: 6, now: Date())
                }
            }
        }
    }

    private var phaseTwoActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phase 2")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                actionButton("Sector", systemImage: "square.3.layers.3d", enabled: controller.canSend(.sectorUpsert) && controller.canSend(.worksiteUpsert)) {
                    try controller.queueSectorPlan(now: Date()).last
                }
                actionButton("Task", systemImage: "checklist.checked", enabled: controller.canSend(.taskUpsert)) {
                    try controller.queueTaskStatus(.inProgress, now: Date())
                }
                actionButton("Photo", systemImage: "camera.fill", enabled: controller.canSend(.photoReportUpsert)) {
                    try controller.queuePhotoReport(photoAttachmentID: LinkGuardID.generated(prefix: "ATTACH"), caption: "A1 photo", checksum: nil, now: Date())
                }
                actionButton("Zone", systemImage: "exclamationmark.triangle.fill", enabled: controller.canSend(.safetyZoneUpsert)) {
                    try controller.queueSafetyZone(now: Date())
                }
                actionButton("Check In", systemImage: "figure.walk.arrival", enabled: controller.canSend(.safetyEntryLogUpsert)) {
                    try controller.queueSafetyEntry(.checkIn, now: Date())
                }
                actionButton("Chat", systemImage: "message.fill", enabled: controller.canSend(.groupChatMessageAppend)) {
                    try controller.queueGroupChat(body: "A1 status update", now: Date())
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

    private func actionButton(_ title: String, systemImage: String, enabled: Bool, operation: @escaping () throws -> SyncEnvelope?) -> some View {
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
        .disabled(enabled == false)
    }

    private func statusChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
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