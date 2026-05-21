import Foundation
import LinkGuardV03Core
import SwiftUI

public struct MacSOSAlertPanelView: View {
    private let items: [MacSOSAlertItem]
    private let isReceiverRunning: Bool
    private let receiverPort: UInt16
    private let receiverError: String?

    public init(
        items: [MacSOSAlertItem],
        isReceiverRunning: Bool,
        receiverPort: UInt16,
        receiverError: String? = nil
    ) {
        self.items = items
        self.isReceiverRunning = isReceiverRunning
        self.receiverPort = receiverPort
        self.receiverError = receiverError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            receiverStatusRow
            if let receiverError {
                statusRow(title: "Receiver Error", detail: receiverError, systemImage: "wifi.exclamationmark", accent: NV.warning)
            }
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(items.prefix(6)) { item in
                        alertRow(item)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NV.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(items.isEmpty ? NV.green.opacity(0.25) : NV.danger.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sos.circle.fill")
                .font(.title3)
                .foregroundStyle(items.isEmpty ? NV.green : NV.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("SCC Field SOS")
                    .font(.headline)
                Text("\(items.count) active runtime alert\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var receiverStatusRow: some View {
        statusRow(
            title: isReceiverRunning ? "Sync Receiver Online" : "Sync Receiver Offline",
            detail: "POST /sync on port \(receiverPort)",
            systemImage: isReceiverRunning ? "network" : "network.slash",
            accent: isReceiverRunning ? NV.green : NV.warning
        )
    }

    private var emptyState: some View {
        statusRow(
            title: "No SOS alerts",
            detail: "Waiting for Field Sync Now batches",
            systemImage: "checkmark.seal.fill",
            accent: NV.green
        )
    }

    private func alertRow(_ item: MacSOSAlertItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NV.danger)
                    .frame(width: 28, height: 28)
                    .background(NV.danger.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.dangerType.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text("\(item.reporterAppID.rawValue) / \(item.reporterDeviceID.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
                Text(item.status.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NV.textOnColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(NV.danger, in: Capsule())
            }
            HStack(spacing: 10) {
                Label(coordinateText(for: item), systemImage: "location.fill")
                Label(Self.timeFormatter.string(from: item.createdAt), systemImage: "clock.fill")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            if let note = item.note, note.isEmpty == false {
                Text(note)
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(10)
        .background(NV.nightVisionRaisedSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: NV.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(NV.danger.opacity(0.28), lineWidth: 1)
        )
    }

    private func statusRow(title: String, detail: String, systemImage: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(NV.nightVisionSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: NV.tagRadius + 4))
    }

    private func coordinateText(for item: MacSOSAlertItem) -> String {
        String(format: "%.5f, %.5f", item.location.latitude, item.location.longitude)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}