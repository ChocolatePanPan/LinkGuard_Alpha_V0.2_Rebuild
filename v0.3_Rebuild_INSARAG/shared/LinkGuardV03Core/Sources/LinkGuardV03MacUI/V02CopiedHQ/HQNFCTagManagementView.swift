import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - HQ NFC 標籤管理

struct HQNFCTagManagementView: View {
    @ObservedObject var vm: HQViewModel

    @State private var searchText = ""
    @State private var formatFilter: NFCFormatFilter = .all
    @State private var selectedRecordID: String?

    private var filteredRecords: [NFCTagWriteRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return vm.nfcTagWrites.filter { record in
            guard formatFilter.matches(record.format) else { return false }
            guard !query.isEmpty else { return true }
            return [
                record.patientId,
                record.compactPatientId,
                record.format,
                record.senderName,
                record.deviceID,
                record.payload
            ]
            .contains { $0.lowercased().contains(query) }
        }
    }

    private var selectedRecord: NFCTagWriteRecord? {
        if let selectedRecordID,
           let record = filteredRecords.first(where: { $0.id == selectedRecordID }) {
            return record
        }
        return filteredRecords.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HQSectionHeader(L("NFC 標籤管理"), icon: "tag.fill", accent: NV.info) {
                statsBar
            }

            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L("搜尋傷患 ID / 裝置 / Payload…"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .hqThemedSurfaceBackground()
                .cornerRadius(8)
                .frame(maxWidth: 320)

                Picker(L("格式"), selection: $formatFilter) {
                    ForEach(NFCFormatFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Button {
                    selectedRecordID = nil
                    vm.clearNFCTagWrites()
                } label: {
                    Label(L("清除紀錄"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(vm.nfcTagWrites.isEmpty || vm.hqRole == .peer)
                .help(vm.hqRole == .peer ? L("Peer 模式僅顯示主 HQ 同步紀錄") : L("清除本機 HQ 的 NFC 寫卡紀錄"))
            }
            .padding(.horizontal, NV.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 14)
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            NFCTagStatBadge(label: L("總筆數"), value: "\(vm.nfcTagWrites.count)", color: NV.info)
            NFCTagStatBadge(label: "LG1", value: "\(count(formatPrefix: "LG1"))", color: NV.warning)
            NFCTagStatBadge(label: "LG2", value: "\(count(formatPrefix: "LG2"))", color: NV.green)
            NFCTagStatBadge(label: L("最近寫入"), value: vm.nfcTagWrites.first?.timeText ?? "--:--:--", color: NV.command)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.nfcTagWrites.isEmpty {
            HQPage(maxWidth: NV.readablePageMaxWidth) {
                HQEmptyStateView(
                    icon: "tag",
                    title: L("尚無 NFC 寫卡紀錄"),
                    subtitle: L("前線裝置完成寫卡並連上 HQ 後，紀錄會出現在此")
                )
                .hqPanelChrome(accent: NV.info)
            }
        } else if filteredRecords.isEmpty {
            HQPage(maxWidth: NV.readablePageMaxWidth) {
                HQEmptyStateView(
                    icon: "magnifyingglass",
                    title: L("找不到符合條件的 NFC 紀錄"),
                    subtitle: L("請調整搜尋文字或格式篩選")
                )
                .hqPanelChrome(accent: NV.info)
            }
        } else {
            HStack(spacing: 0) {
                recordsList
                    .frame(minWidth: 420)
                Divider()
                detailPanel
                    .frame(minWidth: 360, idealWidth: 440)
            }
        }
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(filteredRecords) { record in
                    NFCTagRecordRow(
                        record: record,
                        displayPatientID: displayPatientID(for: record),
                        isSelected: record.id == selectedRecord?.id
                    ) {
                        selectedRecordID = record.id
                    }
                }
            }
            .padding(NV.pagePadding)
        }
        .background(NV.bg.opacity(0.35))
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NFCTagDetailHeader(record: record, displayPatientID: displayPatientID(for: record))

                    detailGrid(for: record)

                    payloadSection(for: record)

                    decodedFieldsSection(for: record)
                }
                .padding(NV.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HQEmptyStateView(icon: "tag", title: L("選取一筆 NFC 紀錄"), minHeight: 360)
                .padding(NV.pagePadding)
        }
    }

    private func detailGrid(for record: NFCTagWriteRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NFCTagDetailRow(label: L("傷患編號"), value: displayPatientID(for: record))
            NFCTagDetailRow(label: L("資料庫 Key"), value: record.compactPatientId)
            NFCTagDetailRow(label: L("NFC URL"), value: vm.patientIDConfig.nfcURL(for: record.compactPatientId))
            NFCTagDetailRow(label: L("格式"), value: record.format)
            NFCTagDetailRow(label: L("容量"), value: L("%@/%@ bytes", "\(record.payloadLength)", "\(record.tagCapacity)"))
            NFCTagDetailRow(label: L("寫入裝置"), value: record.sourceText)
            NFCTagDetailRow(label: L("裝置 ID"), value: record.deviceID.isEmpty ? L("未知") : record.deviceID)
            NFCTagDetailRow(label: L("寫入時間"), value: record.fullTimeText)

            HStack(spacing: 10) {
                Button {
                    copyToPasteboard(record.payload)
                } label: {
                    Label(L("複製 Payload"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    copyToPasteboard(vm.patientIDConfig.nfcURL(for: record.compactPatientId))
                } label: {
                    Label(L("複製 URL"), systemImage: "link")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding()
        .hqPanelChrome(accent: NV.info)
    }

    private func payloadSection(for record: NFCTagWriteRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Payload", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(record.payload)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .hqThemedSurfaceBackground(opacity: 0.72)
                .cornerRadius(8)
        }
        .padding()
        .hqPanelChrome(accent: NV.command)
    }

    private func decodedFieldsSection(for record: NFCTagWriteRecord) -> some View {
        let fields = NFCPayloadInspector.fields(from: record.payload)
        return VStack(alignment: .leading, spacing: 8) {
            Label(L("離線欄位"), systemImage: "list.bullet.rectangle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.fixed(92), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    Text(field.label)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(field.value.isEmpty ? "-" : field.value)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .hqPanelChrome(accent: NV.green)
    }

    private func count(formatPrefix: String) -> Int {
        vm.nfcTagWrites.filter { $0.format.uppercased().hasPrefix(formatPrefix) }.count
    }

    private func displayPatientID(for record: NFCTagWriteRecord) -> String {
        vm.patientIDConfig.displayID(from: record.patientId)
            ?? vm.patientIDConfig.displayID(from: record.compactPatientId)
            ?? PatientIDConfig.displayID(fromCompact: record.compactPatientId)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

private enum NFCFormatFilter: String, CaseIterable, Identifiable {
    case all
    case lg1
    case lg2
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("全部")
        case .lg1: return "LG1"
        case .lg2: return "LG2"
        case .other: return L("其他")
        }
    }

    func matches(_ format: String) -> Bool {
        let normalized = format.uppercased()
        switch self {
        case .all: return true
        case .lg1: return normalized.hasPrefix("LG1")
        case .lg2: return normalized.hasPrefix("LG2")
        case .other: return !normalized.hasPrefix("LG1") && !normalized.hasPrefix("LG2")
        }
    }
}

private struct NFCTagStatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct NFCTagRecordRow: View {
    let record: NFCTagWriteRecord
    let displayPatientID: String
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.compactPatientId)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Text(record.format)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(record.formatColor.opacity(0.18))
                        .foregroundColor(record.formatColor)
                        .cornerRadius(NV.tagRadius)
                }

                Text(displayPatientID)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(record.sourceText, systemImage: "iphone")
                        .lineLimit(1)
                    Spacer()
                    Label(record.relativeTimeText, systemImage: "clock")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ProgressView(value: record.capacityUsage)
                        .tint(record.capacityUsage > 0.9 ? NV.warning : NV.info)
                        .frame(width: 96)
                    Text("\(record.payloadLength)/\(record.tagCapacity) bytes")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NV.info.opacity(0.12) : NV.surface.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius)
                    .stroke(isSelected ? NV.info : Color.secondary.opacity(0.18), lineWidth: NV.strokeWidth)
            )
            .cornerRadius(NV.cardRadius)
        }
        .buttonStyle(.plain)
    }
}

private struct NFCTagDetailHeader: View {
    let record: NFCTagWriteRecord
    let displayPatientID: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.title2)
                .foregroundColor(record.formatColor)
                .frame(width: 36, height: 36)
                .background(record.formatColor.opacity(0.16))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayPatientID)
                    .font(.headline.monospaced())
                    .textSelection(.enabled)
                Text(record.compactPatientId)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Text(record.format)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(record.formatColor.opacity(0.18))
                .foregroundColor(record.formatColor)
                .cornerRadius(NV.tagRadius)
        }
    }
}

private struct NFCTagDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum NFCPayloadInspector {
    static func fields(from payload: String) -> [(label: String, value: String)] {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let version = parts.first, !version.isEmpty else { return [(L("Payload"), payload)] }

        if version.uppercased() == "LG1" {
            return lg1Fields(from: parts)
        }

        let keyedFields = parts.dropFirst().enumerated().map { index, part -> (label: String, value: String) in
            let pair = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if pair.count == 2 {
                return (pair[0], pair[1])
            }
            return (L("欄位 %@", "\(index + 1)"), part)
        }
        return [(L("格式"), version)] + keyedFields
    }

    private static func lg1Fields(from parts: [String]) -> [(label: String, value: String)] {
        let labels = [L("格式"), "ID", "T", "S", "I", "V", "TX", "TM"]
        return parts.enumerated().map { index, value in
            let label = index < labels.count ? labels[index] : L("欄位 %@", "\(index)")
            return (label, value)
        }
    }
}

private enum NFCTagDateFormatters {
    static let hhmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
}

private extension NFCTagWriteRecord {
    var date: Date { Date(timeIntervalSince1970: timestamp) }

    var timeText: String {
        NFCTagDateFormatters.hhmmss.string(from: date)
    }

    var fullTimeText: String {
        NFCTagDateFormatters.full.string(from: date)
    }

    var relativeTimeText: String {
        let seconds = max(0, Int(Date().timeIntervalSince1970 - timestamp))
        if seconds < 60 { return L("剛剛") }
        if seconds < 3600 { return L("%@ 分鐘前", "\(seconds / 60)") }
        if seconds < 86400 { return L("%@ 小時前", "\(seconds / 3600)") }
        return timeText
    }

    var sourceText: String {
        if !senderName.isEmpty { return senderName }
        if !deviceID.isEmpty { return deviceID }
        return L("未知來源")
    }

    var capacityUsage: Double {
        guard tagCapacity > 0 else { return 0 }
        return min(1, Double(payloadLength) / Double(tagCapacity))
    }

    var formatColor: Color {
        let normalized = format.uppercased()
        if normalized.hasPrefix("LG1") { return NV.warning }
        if normalized.hasPrefix("LG2") { return NV.green }
        return NV.command
    }
}