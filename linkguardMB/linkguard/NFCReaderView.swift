import SwiftUI
import Combine
#if os(iOS)
import CoreNFC
import UIKit
#endif

// MARK: - 專用 NFC 讀取頁

struct NFCReaderView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @StateObject private var reader = NFCReadPageManager()
    @State private var steps: [NFCReadStep] = []
    @State private var decoded: NFCReadDecodedPayload?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: reader.isAvailable ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .font(.title2)
                        .foregroundColor(reader.isAvailable ? NV.info : .gray)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("NFC 讀取器"))
                            .font(.headline)
                        Text(reader.statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Button {
                    startRead()
                } label: {
                    Label(L("開始讀取 NFC"), systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!reader.isAvailable)
            } header: {
                Text(L("讀取狀態"))
            } footer: {
                Text(reader.isAvailable ? L("已啟用 NDEF 讀取能力") : L("NFC 僅支援具備 NFC 的 iPhone 實機"))
            }

            if let decoded {
                Section {
                    NFCReadSummaryView(decoded: decoded)

                    HStack(spacing: 10) {
                        Button {
                            copyToPasteboard(decoded.payload)
                        } label: {
                            Label(L("複製 Payload"), systemImage: "doc.on.doc")
                        }

                        if let url = decoded.nfcURL {
                            Button {
                                copyToPasteboard(url)
                            } label: {
                                Label(L("複製 URL"), systemImage: "link")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text(L("讀取結果"))
                }

                Section {
                    Text(decoded.payload)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Payload")
                }

                Section {
                    ForEach(decoded.fields) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(field.label)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .frame(width: 84, alignment: .leading)
                            Text(field.value.isEmpty ? "-" : field.value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text(L("離線欄位"))
                }
            }

            if !steps.isEmpty {
                Section {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Text(step.timeText)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 62, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.caption.bold())
                                if !step.detail.isEmpty {
                                    Text(step.detail)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L("讀取流程"))
                }
            }
        }
        .outerNavigationTitle(L("NFC 讀取"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    private func startRead() {
        decoded = nil
        steps = [NFCReadStep(title: L("開始讀取"), detail: L("等待 NFC 標籤"))]
        reader.beginRead(onProgress: { title, detail in
            appendStep(title, detail: detail)
        }) { payload in
            let result = NFCReadDecodedPayload(payload: payload, config: vm.patientIDConfig)
            decoded = result
            appendStep(L("解析完成"), detail: result.summaryLine)
        }
    }

    private func appendStep(_ title: String, detail: String = "") {
        steps.append(NFCReadStep(title: title, detail: detail))
        if steps.count > 12 {
            steps = Array(steps.suffix(12))
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

private struct NFCReadSummaryView: View {
    let decoded: NFCReadDecodedPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: decoded.icon)
                    .font(.title3)
                    .foregroundColor(decoded.accentColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(decoded.title)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(decoded.summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Text(decoded.format)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(decoded.accentColor.opacity(0.18))
                    .foregroundColor(decoded.accentColor)
                    .cornerRadius(4)
            }

            if let url = decoded.nfcURL {
                Text(url)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct NFCReadStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let timestamp = Date()

    var timeText: String { LGDateFormat.hms.string(from: timestamp) }
}

private struct NFCReadField: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct NFCReadDecodedPayload {
    let payload: String
    let format: String
    let title: String
    let summaryLine: String
    let nfcURL: String?
    let fields: [NFCReadField]

    var icon: String {
        format == "URL" ? "link.circle.fill" : "tag.fill"
    }

    var accentColor: Color {
        if format == "LG1" { return NV.warning }
        if format == "LG2" { return NV.green }
        return NV.info
    }

    init(payload: String, config: PatientIDConfig) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        self.payload = trimmed

        let parts = trimmed.components(separatedBy: "|")
        let prefix = parts.first?.uppercased() ?? "NFC"
        let compactID = Self.compactID(from: trimmed, parts: parts)
        let displayID = compactID.map { PatientIDConfig.displayID(fromCompact: $0) }

        if prefix == "LG1" {
            self.format = "LG1"
            self.title = displayID ?? L("LG1 傷患標籤")
            self.summaryLine = Self.summary(format: "LG1", compactID: compactID, byteCount: trimmed.utf8.count)
            self.nfcURL = compactID.map { config.nfcURL(for: $0) }
            self.fields = Self.lg1Fields(parts)
            return
        }

        if prefix == "LG2" || prefix == "LG3" || prefix == "LG3E" {
            self.format = prefix
            self.title = displayID ?? L("%@ 傷患標籤", prefix)
            self.summaryLine = Self.summary(format: prefix, compactID: compactID, byteCount: trimmed.utf8.count)
            self.nfcURL = compactID.map { config.nfcURL(for: $0) }
            self.fields = Self.keyedFields(parts)
            return
        }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            self.format = "URL"
            self.title = displayID ?? L("NFC URL")
            self.summaryLine = Self.summary(format: "URL", compactID: compactID, byteCount: trimmed.utf8.count)
            self.nfcURL = trimmed
            self.fields = [
                NFCReadField(label: "URL", value: trimmed),
                NFCReadField(label: "ID", value: compactID ?? "")
            ]
            return
        }

        if let compactID {
            self.format = "ID"
            self.title = displayID ?? compactID
            self.summaryLine = Self.summary(format: "ID", compactID: compactID, byteCount: trimmed.utf8.count)
            self.nfcURL = config.nfcURL(for: compactID)
            self.fields = [NFCReadField(label: "ID", value: compactID)]
            return
        }

        self.format = prefix.isEmpty ? "NFC" : prefix
        self.title = L("未識別 NFC Payload")
        self.summaryLine = L("%@ bytes", "\(trimmed.utf8.count)")
        self.nfcURL = nil
        self.fields = [NFCReadField(label: L("內容"), value: trimmed)]
    }

    private static func compactID(from text: String, parts: [String]) -> String? {
        if let compact = PatientIDConfig.extractCompactID(from: text) { return compact }
        if parts.first?.uppercased() == "LG1", parts.count > 1 {
            return PatientIDConfig.extractCompactID(from: parts[1])
        }
        for part in parts.dropFirst() {
            let pair = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if pair.count == 2, pair[0].uppercased() == "ID" {
                return PatientIDConfig.extractCompactID(from: pair[1])
            }
        }
        return nil
    }

    private static func summary(format: String, compactID: String?, byteCount: Int) -> String {
        if let compactID {
            return "\(format) · \(compactID) · \(byteCount) bytes"
        }
        return "\(format) · \(byteCount) bytes"
    }

    private static func lg1Fields(_ parts: [String]) -> [NFCReadField] {
        let labels = [L("格式"), "ID", "T", "S", "I", "V", "TX", "TM"]
        return parts.enumerated().map { index, value in
            NFCReadField(label: index < labels.count ? labels[index] : L("欄位 %@", "\(index)"), value: value)
        }
    }

    private static func keyedFields(_ parts: [String]) -> [NFCReadField] {
        var fields = [NFCReadField(label: L("格式"), value: parts.first ?? "")]
        fields += parts.dropFirst().enumerated().map { index, part in
            let pair = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if pair.count == 2 {
                return NFCReadField(label: pair[0], value: pair[1])
            }
            return NFCReadField(label: L("欄位 %@", "\(index + 1)"), value: part)
        }
        return fields
    }
}

#if os(iOS)
private final class NFCReadPageManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    @Published var statusText: String = L("NFC 待命")
    @Published var lastPayload: String = ""

    private var session: NFCNDEFReaderSession?
    private var completedSuccessfully = false
    private var onProgress: ((String, String) -> Void)?
    private var onRead: ((String) -> Void)?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    func beginRead(onProgress: ((String, String) -> Void)? = nil,
                   onRead: @escaping (String) -> Void) {
        guard isAvailable else {
            statusText = L("此裝置不支援 NFC")
            onProgress?(L("無法啟動 NFC"), L("此裝置不支援 NFC"))
            return
        }

        completedSuccessfully = false
        self.onProgress = onProgress
        self.onRead = onRead
        statusText = L("請靠近傷患 NFC 標籤")
        publishProgress(L("等待標籤"), detail: L("請靠近傷患 NFC 標籤"))
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = L("靠近傷患 NFC 標籤以讀取回報資料")
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            let nsError = error as NSError
            if !self.completedSuccessfully,
               nsError.code != NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
                self.statusText = L("NFC 已停止：%@", error.localizedDescription)
                self.onProgress?(L("流程停止"), error.localizedDescription)
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        publishProgress(L("讀取 NDEF"), detail: L("%lld 筆訊息", messages.count))
        let payload = messages
            .flatMap(\.records)
            .compactMap { $0.linkGuardReadableString() }
            .first ?? ""

        DispatchQueue.main.async {
            guard !payload.isEmpty else {
                self.statusText = L("NFC 標籤沒有可讀取的文字或 URL 資料")
                self.onProgress?(L("讀取失敗"), L("標籤沒有可讀取的文字或 URL 資料"))
                return
            }
            self.completedSuccessfully = true
            self.lastPayload = payload
            self.statusText = L("NFC 讀取完成")
            self.onProgress?(L("取得 Payload"), L("%@ bytes", "\(payload.utf8.count)"))
            self.onRead?(payload)
        }
    }

    private func publishProgress(_ title: String, detail: String = "") {
        DispatchQueue.main.async {
            self.onProgress?(title, detail)
        }
    }
}

extension NFCNDEFPayload {
    func linkGuardReadableString() -> String? {
        if let text = wellKnownTypeTextPayload().0, !text.isEmpty {
            return text
        }

        if let url = wellKnownTypeURIPayload() {
            return url.absoluteString
        }

        if typeNameFormat == .absoluteURI,
           let uri = String(data: type, encoding: .utf8),
           !uri.isEmpty {
            return uri
        }

        if let uri = decodedWellKnownURI() {
            return uri
        }

        if let raw = String(data: payload, encoding: .utf8), !raw.isEmpty {
            return raw.trimmingCharacters(in: .controlCharacters)
        }

        return nil
    }

    private func decodedWellKnownURI() -> String? {
        guard typeNameFormat == .nfcWellKnown,
              String(data: type, encoding: .utf8) == "U",
              let prefixByte = payload.first else { return nil }

        let bodyData = payload.dropFirst()
        guard let body = String(data: bodyData, encoding: .utf8) else { return nil }
        let prefixes = [
            "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
            "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://",
            "nfs://", "ftp://", "dav://", "news:", "telnet://", "imap:", "rtsp://",
            "urn:", "pop:", "sip:", "sips:", "tftp:", "btspp://", "btl2cap://",
            "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
            "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:"
        ]
        let prefix = Int(prefixByte) < prefixes.count ? prefixes[Int(prefixByte)] : ""
        return prefix + body
    }
}
#else
private final class NFCReadPageManager: ObservableObject {
    @Published var statusText: String = L("NFC 僅支援 iPhone 實機")
    @Published var lastPayload: String = ""
    var isAvailable: Bool { false }

    func beginRead(onProgress: ((String, String) -> Void)? = nil,
                   onRead: @escaping (String) -> Void) {
        statusText = L("NFC 僅支援 iPhone 實機")
        onProgress?(L("無法啟動 NFC"), L("NFC 僅支援 iPhone 實機"))
    }
}
#endif