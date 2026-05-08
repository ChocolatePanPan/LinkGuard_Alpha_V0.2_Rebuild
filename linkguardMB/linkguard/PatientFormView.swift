import SwiftUI
import CoreLocation
import Combine
#if os(iOS)
import CoreNFC
#endif

#if os(iOS)
private final class PatientNFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    enum Mode {
        case read
        case write((Int) -> String)
    }

    @Published var statusText: String = L("NFC 待命")
    @Published var lastPayload: String = ""

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .read
    private var completedSuccessfully = false
    private var onProgress: ((String, String) -> Void)?
    private var onRead: ((String) -> Void)?
    private var onWrite: ((String, Int, Int) -> Void)?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    func beginRead(onProgress: ((String, String) -> Void)? = nil,
                   onRead: @escaping (String) -> Void) {
        guard isAvailable else {
            statusText = L("此裝置不支援 NFC")
            onProgress?(L("無法啟動 NFC"), L("此裝置不支援 NFC"))
            return
        }

        mode = .read
        completedSuccessfully = false
        self.onProgress = onProgress
        self.onRead = onRead
        onWrite = nil
        statusText = L("請靠近傷患 NFC 標籤")
        publishProgress(L("等待標籤"), detail: L("請靠近傷患 NFC 標籤"))
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = L("靠近傷患 NFC 標籤以讀取回報資料")
        session?.begin()
    }

    func beginWrite(payloadForCapacity: @escaping (Int) -> String,
                    onProgress: ((String, String) -> Void)? = nil,
                    onWrite: @escaping (String, Int, Int) -> Void) {
        guard isAvailable else {
            statusText = L("此裝置不支援 NFC")
            onProgress?(L("無法啟動 NFC"), L("此裝置不支援 NFC"))
            return
        }

        mode = .write(payloadForCapacity)
        completedSuccessfully = false
        self.onProgress = onProgress
        onRead = nil
        self.onWrite = onWrite
        statusText = L("請靠近可寫入的 NFC 標籤")
        publishProgress(L("等待標籤"), detail: L("請靠近空白或可覆寫的 NFC 標籤"))
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = L("靠近空白或可覆寫的 NFC 標籤")
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
        guard case .read = mode else { return }
        publishProgress(L("讀取 NDEF"), detail: L("%lld 筆訊息", messages.count))
        let payload = messages
            .flatMap(\.records)
            .compactMap { PatientNFCManager.text(from: $0) }
            .first ?? ""

        DispatchQueue.main.async {
            guard !payload.isEmpty else {
                self.statusText = L("NFC 標籤沒有可讀取的文字資料")
                self.onProgress?(L("讀取失敗"), L("標籤沒有可讀取的文字資料"))
                return
            }
            self.lastPayload = payload
            self.statusText = L("NFC 讀取完成")
            self.completedSuccessfully = true
            self.onProgress?(L("取得 Payload"), "\(payload.utf8.count) bytes")
            self.onRead?(payload)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard case .write(let payloadForCapacity) = mode else { return }
        publishProgress(L("偵測標籤"), detail: "\(tags.count) 張")
        guard let tag = tags.first else {
            publishProgress(L("偵測失敗"), detail: L("找不到 NFC 標籤"))
            session.invalidate(errorMessage: L("找不到 NFC 標籤"))
            return
        }

        if tags.count > 1 {
            session.alertMessage = L("一次只靠近一張 NFC 標籤")
            publishProgress(L("等待單張標籤"), detail: L("一次只靠近一張 NFC 標籤"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { session.restartPolling() }
            return
        }

        publishProgress(L("連線標籤"), detail: L("讀取 NDEF 狀態"))
        session.connect(to: tag) { error in
            if let error {
                self.publishProgress(L("連線失敗"), detail: error.localizedDescription)
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }

            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    self.publishProgress(L("容量檢查失敗"), detail: error.localizedDescription)
                    session.invalidate(errorMessage: error.localizedDescription)
                    return
                }

                self.publishProgress(L("檢查容量"), detail: "\(capacity) bytes")
                guard status == .readWrite else {
                    self.publishProgress(L("不可寫入"), detail: L("此 NFC 標籤不可寫入"))
                    session.invalidate(errorMessage: L("此 NFC 標籤不可寫入"))
                    return
                }

                let payload = payloadForCapacity(capacity)
                let message = NFCNDEFMessage(records: [PatientNFCManager.record(from: payload)])
                let format = payload.components(separatedBy: "|").first ?? "NFC"
                self.publishProgress(L("選擇格式"), detail: "\(format) · \(message.length)/\(capacity) bytes")
                guard message.length <= capacity else {
                    self.publishProgress(L("容量不足"), detail: "\(message.length)/\(capacity) bytes")
                    session.invalidate(errorMessage: L("NFC 標籤容量不足"))
                    return
                }

                self.publishProgress(L("寫入 NDEF"), detail: "\(message.length) bytes")
                tag.writeNDEF(message) { error in
                    if let error {
                        self.publishProgress(L("寫入失敗"), detail: error.localizedDescription)
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        self.publishProgress(L("寫入完成"), detail: format)
                        self.completedSuccessfully = true
                        session.alertMessage = L("傷患 NFC 標籤寫入完成")
                        session.invalidate()
                        DispatchQueue.main.async {
                            self.lastPayload = payload
                            self.statusText = L("NFC 寫入完成")
                            self.onWrite?(payload, capacity, message.length)
                        }
                    }
                }
            }
        }
    }

    private func publishProgress(_ title: String, detail: String = "") {
        DispatchQueue.main.async {
            self.onProgress?(title, detail)
        }
    }

    private static func record(from text: String) -> NFCNDEFPayload {
        NFCNDEFPayload.wellKnownTypeTextPayload(string: text, locale: Locale(identifier: "zh-Hant"))!
    }

    private static func text(from record: NFCNDEFPayload) -> String? {
        record.linkGuardReadableString()
    }

    static func ndefLength(for text: String) -> Int {
        NFCNDEFMessage(records: [record(from: text)]).length
    }
}
#else
private final class PatientNFCManager: ObservableObject {
    @Published var statusText: String = L("NFC 僅支援 iPhone 實機")
    @Published var lastPayload: String = ""
    var isAvailable: Bool { false }
    func beginRead(onProgress: ((String, String) -> Void)? = nil,
                   onRead: @escaping (String) -> Void) {
        statusText = L("NFC 僅支援 iPhone 實機")
        onProgress?(L("無法啟動 NFC"), L("NFC 僅支援 iPhone 實機"))
    }
    func beginWrite(payloadForCapacity: @escaping (Int) -> String,
                    onProgress: ((String, String) -> Void)? = nil,
                    onWrite: @escaping (String, Int, Int) -> Void) {
        statusText = L("NFC 僅支援 iPhone 實機")
        onProgress?(L("無法啟動 NFC"), L("NFC 僅支援 iPhone 實機"))
    }
}
#endif

// MARK: - GPS 位置管理

private class PatientLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}

// MARK: - 傷員回報表單

private enum PatientNFCFormat: String, CaseIterable, Identifiable {
    case lg1 = "LG1"
    case lg2 = "LG2"
    case lg3 = "LG3"

    static let allCases: [PatientNFCFormat] = [.lg1, .lg2]
    static let ntag215MaxNDEFCapacity = 600

    var id: String { rawValue }

    var capacityHint: String {
        switch self {
        case .lg1: return L("NTAG215 / LG1 精簡離線格式")
        case .lg2: return L("NTAG216 / LG2 完整離線格式")
        case .lg3: return L("DESFire／高容量完整離線紀錄")
        }
    }
}

private struct NFCProcessStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let timestamp = Date()

    var timeText: String { LGDateFormat.hms.string(from: timestamp) }
}

private struct NFCAutoFillValues {
    let triageCode: String
    let sexAgeCode: String
    let injuryCode: String
    let pulseText: String
    let gcsText: String
    let treatmentCode: String
    let allergyCode: String
}

struct PatientFormView: View {
    private typealias NFCPayloadCandidate = (format: PatientNFCFormat, payload: String, length: Int)

    @ObservedObject var vm: LinkGuardViewModel
    @StateObject private var voiceManager = VoiceInputManager()
    @StateObject private var locationMgr = PatientLocationManager()
    @StateObject private var nfcManager = PatientNFCManager()
    @State private var patientIdOverride: String?
    @State private var selectedNFCFormat: PatientNFCFormat = .lg1
    @State private var nfcAutoFillEnabled = true
    @State private var nfcProcessSteps: [NFCProcessStep] = []
    @State private var nfcDecodedSummary: String = ""
    @State private var nfcTriageCode: String = "U"
    @State private var nfcSexAgeCode: String = "U"
    @State private var nfcInjuryCode: String = ""
    @State private var nfcPulseText: String = ""
    @State private var nfcGCSText: String = ""
    @State private var nfcTreatmentCode: String = ""
    @State private var nfcTreatmentBodyCode: String = "GEN"
    @State private var nfcTreatmentStatusCode: String = "DONE"
    @State private var nfcAllergyCode: String = ""
    @State private var nfcFlagCode: String = ""
    @State private var nfcEvacStatus: String = "WAIT"
    @State private var nfcDestinationCode: String = ""
    @State private var nfcTeamCode: String = ""

    private let triageCodes = ["U", "R", "Y", "G", "B"]
    private let evacuationCodes = ["WAIT", "MOVE", "ARRV", "HOLD", "DEAD"]

    // 身分資料
    @State private var nationalId: String = ""
    @State private var patientName: String = ""
    @State private var useROC: Bool = false          // false=西元, true=民國
    @State private var birthYearText: String = ""
    @State private var birthMonthText: String = ""
    @State private var birthDayText: String = ""

    private enum DateField: Hashable { case year, month, day }
    @FocusState private var focusedDateField: DateField?

    @State private var location: String = ""
    @State private var breathingRateText: String = ""
    @State private var capillaryRefillText: String = ""
    @State private var canFollowCommands: Bool = false
    @State private var notes: String = ""
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""

    /// 年份欄位滿位長度（西元4碼，民國3碼）
    private var yearMaxLen: Int { useROC ? 3 : 4 }

    /// 將輸入的年份轉為西元年
    private var ceYear: Int? {
        guard let y = Int(birthYearText) else { return nil }
        return useROC ? y + 1911 : y
    }

    /// 組合出生日期字串（西元 yyyy-MM-dd）
    private var birthDateString: String? {
        guard let y = ceYear,
              let m = Int(birthMonthText), (1...12).contains(m),
              let d = Int(birthDayText), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// 自動計算年齡
    private var calculatedAge: Int? {
        guard let dateStr = birthDateString else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let birth = fmt.date(from: dateStr) else { return nil }
        let comps = Calendar.current.dateComponents([.year], from: birth, to: Date())
        guard let age = comps.year, age >= 0 else { return nil }
        return age
    }

    var body: some View {
        Form {
            // 傷員 ID（由 HQ 配置產生，僅顯示預覽）
            Section {
                HStack {
                    Text(L("傷員 ID"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(activePatientID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(L("HQ 自動編號"))
            } footer: {
                Text(activeNFCPayloadPreview)
                    .font(.system(.caption2, design: .monospaced))
            }

            // 身分資料
            Section {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                            .foregroundColor(NV.command)
                            .frame(width: 22)
                        #if os(iOS)
                        TextField(L("身分證字號"), text: $nationalId)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        #else
                        TextField(L("身分證字號"), text: $nationalId)
                            .autocorrectionDisabled()
                        #endif
                    }

                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(NV.command)
                            .frame(width: 22)
                        TextField(L("姓名"), text: $patientName)
                    }

                    // 西元 / 民國切換
                    Picker(L("曆法"), selection: $useROC) {
                        Text(L("西元")).tag(false)
                        Text(L("民國")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: useROC) { _, _ in
                        birthYearText = ""
                        focusedDateField = .year
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundColor(NV.info)
                            .frame(width: 22)
                        TextField(useROC ? L("民國年") : L("西元年"), text: $birthYearText)
                            .frame(maxWidth: 80)
                            .focused($focusedDateField, equals: .year)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: birthYearText) { _, val in
                                let filtered = String(val.prefix(yearMaxLen)).filter { $0.isNumber }
                                if filtered != val { birthYearText = filtered }
                                if filtered.count >= yearMaxLen { focusedDateField = .month }
                            }
                        Text("/").foregroundColor(.secondary)
                        TextField(L("月"), text: $birthMonthText)
                            .frame(maxWidth: 50)
                            .focused($focusedDateField, equals: .month)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: birthMonthText) { _, val in
                                let filtered = String(val.prefix(2)).filter { $0.isNumber }
                                if filtered != val { birthMonthText = filtered }
                                if filtered.count >= 2 { focusedDateField = .day }
                            }
                        Text("/").foregroundColor(.secondary)
                        TextField(L("日"), text: $birthDayText)
                            .frame(maxWidth: 50)
                            .focused($focusedDateField, equals: .day)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: birthDayText) { _, val in
                                let filtered = String(val.prefix(2)).filter { $0.isNumber }
                                if filtered != val { birthDayText = filtered }
                                if filtered.count >= 2 { focusedDateField = nil }
                            }
                    }

                    // 年齡顯示
                    if let age = calculatedAge {
                        HStack {
                            Image(systemName: "number.circle")
                                .foregroundColor(NV.green)
                                .frame(width: 22)
                            Text(L("年齡：%lld 歲", age))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L("身分資料"))
                }

                // 位置與生理數據
                Section {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(NV.command)
                            .frame(width: 22)
                        TextField(L("例：A區 3F 走廊"), text: $location)
                    }

                    HStack {
                        Image(systemName: "lungs.fill")
                            .foregroundColor(breathingRateText == "-1" ? NV.danger : NV.info)
                            .frame(width: 22)
                        TextField(L("呼吸速率（次/分，-1=無呼吸）"), text: $breathingRateText)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }

                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(capillaryRefillText == "-1" ? NV.danger : NV.info)
                            .frame(width: 22)
                        TextField(L("微血管充盈時間（秒，-1=無脈搏）"), text: $capillaryRefillText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                } header: {
                    Text(L("傷員資訊"))
                }

                // 意識狀態
                Section {
                    Toggle(isOn: $canFollowCommands) {
                        HStack(spacing: 8) {
                            Image(systemName: canFollowCommands ? "brain.head.profile" : "xmark.circle.fill")
                                .foregroundColor(canFollowCommands ? NV.green : NV.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("可遵從指令"))
                                    .font(.body)
                                Text(canFollowCommands ? L("意識清醒") : L("意識不清"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(NV.green)
                } header: {
                    Text(L("意識狀態"))
                }

                Section {
                    Picker(L("離線格式"), selection: $selectedNFCFormat) {
                        ForEach(PatientNFCFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedNFCFormat.capacityHint)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $nfcAutoFillEnabled) {
                        Label(L("自動帶入傷患資料"), systemImage: "wand.and.stars")
                    }
                    .tint(NV.green)

                    Text(nfcAutoFillSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        applyNFCAutoFill(overwrite: true)
                        appendNFCProcessStep(L("自動帶入 NFC 欄位"), detail: nfcAutoFillSummary)
                    } label: {
                        Label(L("立即帶入"), systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)

                    Picker(L("檢傷"), selection: $nfcTriageCode) {
                        ForEach(triageCodes, id: \.self) { code in
                            Text(triageLabel(code)).tag(code)
                        }
                    }

                    HStack {
                        TextField(L("性別年齡 M45/F30/C08/U"), text: $nfcSexAgeCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField(L("傷勢代碼"), text: $nfcInjuryCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        TextField(L("脈搏"), text: $nfcPulseText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        TextField(L("GCS"), text: $nfcGCSText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        TextField(L("處置代碼"), text: $nfcTreatmentCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    if selectedNFCFormat == .lg3 {
                        HStack {
                            TextField(L("處置部位 BODY"), text: $nfcTreatmentBodyCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()

                            TextField(L("處置狀態 STATUS"), text: $nfcTreatmentStatusCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    }

                    if selectedNFCFormat == .lg3 {
                        TextField(L("警示 FLAG"), text: $nfcFlagCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    if selectedNFCFormat != .lg1 {
                        TextField(L("過敏代碼 ALG"), text: $nfcAllergyCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    if selectedNFCFormat == .lg3 {
                        HStack {
                            Picker(L("後送"), selection: $nfcEvacStatus) {
                                ForEach(evacuationCodes, id: \.self) { code in
                                    Text(evacuationLabel(code)).tag(code)
                                }
                            }
                        }
                        HStack {
                            TextField(L("目的地 DST"), text: $nfcDestinationCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            TextField(L("小隊 TEAM"), text: $nfcTeamCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .foregroundColor(nfcManager.isAvailable ? NV.command : .gray)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("NFC 傷患標籤"))
                                .font(.body)
                            Text(nfcManager.statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !nfcManager.lastPayload.isEmpty {
                        Text(nfcManager.lastPayload)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2...4)
                            .textSelection(.enabled)
                    }

                    if !nfcDecodedSummary.isEmpty {
                        Text(nfcDecodedSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if !nfcProcessSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(nfcProcessSteps) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(step.timeText)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 62, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
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
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 12) {
                        Button {
                            startNFCProcess(L("開始讀取"), detail: L("等待傷患 NFC 標籤"))
                            nfcManager.beginRead(onProgress: { title, detail in
                                appendNFCProcessStep(title, detail: detail)
                            }) { payload in
                                appendNFCProcessStep(L("解析 Payload"), detail: nfcPayloadDescription(payload))
                                applyNFCPayload(payload)
                                appendNFCProcessStep(L("讀取流程完成"), detail: compactPatientID(activePatientID))
                            }
                        } label: {
                            Label(L("讀取"), systemImage: "wave.3.right")
                        }
                        .disabled(!nfcManager.isAvailable)

                        Button {
                            let candidates = nfcPayloadCandidatesForWrite()
                            startNFCProcess(L("準備寫入"), detail: compactPatientID(activePatientID))
                            appendNFCProcessStep(L("建立候選格式"), detail: nfcCandidateSummary(candidates))
                            nfcManager.beginWrite(payloadForCapacity: { capacity in
                                nfcPayload(for: capacity, candidates: candidates)
                            }, onProgress: { title, detail in
                                appendNFCProcessStep(title, detail: detail)
                            }, onWrite: { payload, capacity, payloadLength in
                                appendNFCProcessStep(L("寫入結果"), detail: nfcWriteSummary(payload: payload, capacity: capacity, payloadLength: payloadLength))
                                appendNFCProcessStep(vm.commandClient.isConnected ? L("送出 HQ 同步") : L("HQ 未連線"), detail: compactPatientID(activePatientID))
                                syncNFCTagWrite(payload: payload, capacity: capacity, payloadLength: payloadLength)
                            })
                        } label: {
                            Label(L("寫入"), systemImage: "square.and.pencil")
                        }
                        .disabled(!nfcManager.isAvailable)
                    }
                } header: {
                    Text(L("NFC 讀取／寫入"))
                } footer: {
                    Text(L("NTAG215 固定寫 LG1 精簡格式；NTAG216 固定寫 LG2 完整格式。NFC 不寫姓名、身分證或電話。"))
                }

                // 語音輸入
                Section {
                    VoiceInputButton(
                        voiceManager: voiceManager,
                        serverHost: vm.transcriptionServerHost
                    ) { transcribedText in
                        applyTranscription(transcribedText)
                    }
                } header: {
                    Text(L("語音輸入"))
                } footer: {
                    Text(L("長按麥克風錄音，放開後自動上傳轉錄。轉錄結果會自動填入位置欄位。"))
                }

                // 備註
                Section {
                    TextField(L("備註（選填）"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(L("補充說明"))
                }

                // GPS 資訊
                Section {
                    if let loc = locationMgr.lastLocation {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(NV.green)
                            Text(String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "location.slash")
                                .foregroundColor(.gray)
                            Text(L("GPS 定位中…"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L("GPS 座標（自動取得）"))
                }

                // 送出按鈕
                Section {
                    Button {
                        submitReport()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "paperplane.fill")
                            Text(L("送出傷員回報"))
                                .bold()
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        isFormValid ? NV.danger : Color.gray.opacity(0.3)
                    )
                    .disabled(!isFormValid)
                }
            }
        .outerNavigationTitle(L("傷員回報"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("完成")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear { applyNFCAutoFillIfNeeded() }
        .onChange(of: nfcAutoFillEnabled) { _, enabled in
            if enabled { applyNFCAutoFill(overwrite: true) }
        }
        .onChange(of: nationalId) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: birthYearText) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: birthMonthText) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: birthDayText) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: breathingRateText) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: capillaryRefillText) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: canFollowCommands) { _, _ in applyNFCAutoFillIfNeeded() }
        .onChange(of: notes) { _, _ in applyNFCAutoFillIfNeeded() }
        .overlay(alignment: .bottom) {
            if showConfirmation {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NV.green)
                    Text(confirmationMessage)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(NV.green.opacity(0.2)), in: .capsule)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: showConfirmation)
            }
        }
    }

    // MARK: - 語音轉錄

    private func applyTranscription(_ text: String) {
        // 將轉錄結果填入位置欄位
        if location.isEmpty {
            location = text
        } else {
            location += " \(text)"
        }
    }

    // MARK: - NFC

    private var activePatientID: String {
        patientIdOverride ?? vm.previewPatientID
    }

    private var activeNFCPayloadPreview: String {
        buildNFCPayload(for: activePatientID, format: selectedNFCFormat)
    }

    private var nfcAutoFillSummary: String {
        let values = automaticNFCValues()
        var parts = [
            "T:", triageLabel(values.triageCode),
            "S:", values.sexAgeCode
        ]
        if !values.injuryCode.isEmpty { parts.append("I:"); parts.append(values.injuryCode) }
        if !values.pulseText.isEmpty { parts.append("P:"); parts.append(values.pulseText) }
        if !values.gcsText.isEmpty { parts.append("GCS:"); parts.append(values.gcsText) }
        if !values.treatmentCode.isEmpty { parts.append("TX:"); parts.append(values.treatmentCode) }
        if !values.allergyCode.isEmpty { parts.append("ALG:"); parts.append(values.allergyCode) }
        return parts.joined(separator: " ")
    }

    private func applyNFCAutoFillIfNeeded() {
        guard nfcAutoFillEnabled else { return }
        applyNFCAutoFill(overwrite: true)
    }

    private func applyNFCAutoFill(overwrite: Bool) {
        let values = automaticNFCValues()
        nfcTriageCode = values.triageCode
        nfcSexAgeCode = values.sexAgeCode
        if overwrite || nfcInjuryCode.isEmpty { nfcInjuryCode = values.injuryCode }
        if overwrite || nfcPulseText.isEmpty { nfcPulseText = values.pulseText }
        if overwrite || nfcGCSText.isEmpty { nfcGCSText = values.gcsText }
        if overwrite || nfcTreatmentCode.isEmpty { nfcTreatmentCode = values.treatmentCode }
        if overwrite || nfcAllergyCode.isEmpty { nfcAllergyCode = values.allergyCode }
    }

    private func automaticNFCValues() -> NFCAutoFillValues {
        NFCAutoFillValues(
            triageCode: automaticTriageCode(),
            sexAgeCode: automaticSexAgeCode(),
            injuryCode: automaticInjuryCode(),
            pulseText: automaticPulseText(),
            gcsText: automaticGCSText(),
            treatmentCode: automaticTreatmentCode(),
            allergyCode: automaticAllergyCode()
        )
    }

    private func automaticTriageCode() -> String {
        let breathingRate = Int(breathingRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        let capillaryRefill = Double(capillaryRefillText.trimmingCharacters(in: .whitespacesAndNewlines))

        guard breathingRate != nil || capillaryRefill != nil else { return "U" }
        if breathingRate == -1 { return "B" }
        if capillaryRefill == -1 { return "R" }
        if let breathingRate, breathingRate > 30 { return "R" }
        if let capillaryRefill, capillaryRefill > 2 { return "R" }
        if !canFollowCommands { return "Y" }
        return "G"
    }

    private func automaticSexAgeCode() -> String {
        guard let age = calculatedAge else { return "U" }
        let ageText = String(format: "%02d", min(max(age, 0), 99))
        if age < 13 { return "C\(ageText)" }
        guard let sexPrefix = inferredSexPrefixFromNationalID() else { return "U" }
        return "\(sexPrefix)\(ageText)"
    }

    private func inferredSexPrefixFromNationalID() -> String? {
        let compactID = nationalId.uppercased().filter { $0.isLetter || $0.isNumber }
        guard compactID.count >= 2 else { return nil }
        let secondIndex = compactID.index(after: compactID.startIndex)
        switch compactID[secondIndex] {
        case "1", "8": return "M"
        case "2", "9": return "F"
        default: return nil
        }
    }

    private func automaticInjuryCode() -> String {
        if Int(breathingRateText.trimmingCharacters(in: .whitespacesAndNewlines)) == -1 { return "CPA" }
        if Double(capillaryRefillText.trimmingCharacters(in: .whitespacesAndNewlines)) == -1 { return "CPA" }

        let source = nfcInferenceSource
        let hasBleeding = source.contains("出血") || source.contains("BLEED") || source.contains("流血")
        if hasBleeding, containsAny(source, ["左腿", "左下肢", "LEFT_LEG", "LEFT LEG"]) { return "LEFT_LEG_BLEED" }
        if hasBleeding, containsAny(source, ["右腿", "右下肢", "RIGHT_LEG", "RIGHT LEG"]) { return "RIGHT_LEG_BLEED" }
        if hasBleeding, containsAny(source, ["腿", "下肢", "LEG"]) { return "LEG_BLEED" }
        if hasBleeding, containsAny(source, ["手", "上肢", "臂", "ARM"]) { return "ARM_BLEED" }
        if containsAny(source, ["頭", "HEAD"]) { return "HEAD" }
        if containsAny(source, ["胸", "CHEST"]) { return "CHEST" }
        if containsAny(source, ["腹", "ABD", "ABDOMEN"]) { return "ABD" }
        if containsAny(source, ["骨折", "FRACTURE", "FX"]) { return "FX" }
        if containsAny(source, ["燒", "燙", "BURN"]) { return "BURN" }
        if containsAny(source, ["壓", "砸", "夾", "CRUSH"]) { return "CRUSH" }
        if !canFollowCommands, hasClinicalInput { return "UNCON" }
        return ""
    }

    private func automaticPulseText() -> String {
        firstNumber(after: ["P", "PULSE", "脈搏"], in: nfcInferenceSource) ?? ""
    }

    private func automaticGCSText() -> String {
        if let gcs = firstNumber(after: ["GCS", "G"], in: nfcInferenceSource) { return gcs }
        guard hasClinicalInput else { return "" }
        return canFollowCommands ? "15" : "12"
    }

    private func automaticTreatmentCode() -> String {
        let source = nfcInferenceSource
        var codes: [String] = []
        if containsAny(source, ["TQL", "左止血帶", "左側止血帶"]) { codes.append("TQL") }
        if containsAny(source, ["TQR", "右止血帶", "右側止血帶"]) { codes.append("TQR") }
        if !codes.contains("TQL"), !codes.contains("TQR"), containsAny(source, ["止血帶", "TOURNIQUET"]) { codes.append("TQL") }
        if containsAny(source, ["包紮", "BANDAGE", "BAND"]) { codes.append("BAND") }
        if containsAny(source, ["固定", "夾板", "SPLINT", "SPL"]) { codes.append("SPL") }
        if containsAny(source, ["給氧", "氧氣", "O2"]) { codes.append("O2") }
        if containsAny(source, ["CPR", "心肺復甦"]) { codes.append("CPR") }
        if containsAny(source, ["AED", "電擊"]) { codes.append("AED") }
        if containsAny(source, ["IV", "靜脈", "點滴"]) { codes.append("IV") }
        return Array(NSOrderedSet(array: codes)).compactMap { $0 as? String }.joined(separator: "+")
    }

    private func automaticAllergyCode() -> String {
        let source = nfcInferenceSource
        if containsAny(source, ["PCN", "PENICILLIN", "青黴素", "盤尼西林"]) { return "PCN" }
        return ""
    }

    private var hasClinicalInput: Bool {
        !breathingRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !capillaryRefillText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nfcInferenceSource: String {
        "\(location) \(notes) \(nfcInjuryCode) \(nfcTreatmentCode)".uppercased()
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0.uppercased()) }
    }

    private func firstNumber(after prefixes: [String], in text: String) -> String? {
        for prefix in prefixes {
            if let number = firstNumber(after: prefix, in: text) { return number }
        }
        return nil
    }

    private func firstNumber(after prefix: String, in text: String) -> String? {
        guard let range = text.range(of: prefix.uppercased()) else { return nil }
        let tail = text[range.upperBound...]
        let digits = tail.drop { !$0.isNumber }.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private func startNFCProcess(_ title: String, detail: String = "") {
        nfcProcessSteps = [NFCProcessStep(title: title, detail: detail)]
    }

    private func appendNFCProcessStep(_ title: String, detail: String = "") {
        nfcProcessSteps.append(NFCProcessStep(title: title, detail: detail))
        if nfcProcessSteps.count > 10 {
            nfcProcessSteps = Array(nfcProcessSteps.suffix(10))
        }
    }

    private func nfcCandidateSummary(_ candidates: [NFCPayloadCandidate]) -> String {
        candidates
            .map { "\($0.format.rawValue) \($0.length) bytes" }
            .joined(separator: " · ")
    }

    private func nfcPayloadDescription(_ payload: String) -> String {
        let format = payload.components(separatedBy: "|").first ?? "NFC"
        return "\(format) · \(payload.utf8.count) bytes"
    }

    private func nfcWriteSummary(payload: String, capacity: Int, payloadLength: Int) -> String {
        "\(nfcPayloadDescription(payload)) · \(payloadLength)/\(capacity) NDEF bytes"
    }

    private func nfcPayloadCandidatesForWrite() -> [NFCPayloadCandidate] {
        applyNFCAutoFillIfNeeded()
        let id = patientIdOverride ?? vm.reserveNextPatientID()
        patientIdOverride = id
        return writeFormats().map { format in
            let payload = buildNFCPayload(for: id, format: format)
            return (format, payload, ndefLength(for: payload))
        }
    }

    private func writeFormats() -> [PatientNFCFormat] {
        selectedNFCFormat == .lg3 ? [.lg3, .lg2, .lg1] : [.lg2, .lg1]
    }

    private func nfcPayload(for capacity: Int, candidates: [NFCPayloadCandidate]) -> String {
        let preferred = preferredNFCFormat(forTagCapacity: capacity)
        if let exact = candidates.first(where: { $0.format == preferred && $0.length <= capacity }) {
            return exact.payload
        }
        return candidates.first { $0.length <= capacity }?.payload ?? candidates.last?.payload ?? ""
    }

    private func preferredNFCFormat(forTagCapacity capacity: Int) -> PatientNFCFormat {
        if selectedNFCFormat == .lg3, capacity > 1024 { return .lg3 }
        return capacity <= PatientNFCFormat.ntag215MaxNDEFCapacity ? .lg1 : .lg2
    }

    private func ndefLength(for payload: String) -> Int {
        #if os(iOS)
        PatientNFCManager.ndefLength(for: payload)
        #else
        payload.utf8.count
        #endif
    }

    private func syncNFCTagWrite(payload: String, capacity: Int, payloadLength: Int) {
        vm.syncNFCTagWrite(
            patientId: activePatientID,
            payload: payload,
            tagCapacity: capacity,
            payloadLength: payloadLength
        )
        if vm.commandClient.isConnected {
            nfcManager.statusText = L("NFC 寫入完成，已同步 HQ")
        }
    }

    private func applyNFCPayload(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("LG1|") {
            applyLG1Payload(trimmed)
            return
        }
        if trimmed.hasPrefix("LG2|") {
            applyKeyedNFCPayload(trimmed, version: .lg2)
            return
        }
        if trimmed.hasPrefix("LG3|") {
            applyKeyedNFCPayload(trimmed, version: .lg3)
            return
        }
        if trimmed.hasPrefix("LG3E|") {
            applyEncryptedLG3Payload(trimmed)
            return
        }

        if let displayID = vm.displayPatientID(from: payload) {
            patientIdOverride = displayID
            nfcManager.statusText = vm.patientIDConfig.isValidChecksum(payload)
                ? L("NFC 傷患 ID 已讀取")
                : L("NFC 傷患 ID 已讀取（校驗待確認）")
            return
        }

        let parts = payload.split(separator: "|").map(String.init)
        guard parts.first == "LG1" else {
            nfcManager.statusText = L("NFC 格式不是 LinkGuard 傷患 ID 或 LG1/LG2/LG3")
            return
        }

        for part in parts.dropFirst() {
            if let value = payloadValue(after: "ID:", in: part) {
                if let displayID = vm.displayPatientID(from: value) {
                    patientIdOverride = displayID
                } else {
                    nationalId = value
                }
            } else if let value = payloadValue(after: "AGE:", in: part) {
                notes = appendNote(notes, L("NFC 年齡：%@", value))
            } else if let value = payloadValue(after: "INJ:", in: part) {
                notes = appendNote(notes, L("傷勢：%@", value))
            } else if let value = payloadValue(after: "TX:", in: part) {
                notes = appendNote(notes, L("處置：%@", value))
            } else if let value = payloadValue(after: "LOC:", in: part) {
                location = value
            } else if let value = payloadValue(after: "RR", in: part) ?? payloadValue(after: "RR:", in: part) {
                breathingRateText = value
            } else if let value = payloadValue(after: "GCS", in: part) ?? payloadValue(after: "GCS:", in: part) {
                if let gcs = Int(value) { canFollowCommands = gcs >= 13 }
                notes = appendNote(notes, "GCS\(value)")
            } else if let value = payloadValue(after: "T:", in: part) {
                notes = appendNote(notes, L("分級：%@", value))
            } else if let value = payloadValue(after: "TIME:", in: part) {
                notes = appendNote(notes, L("標籤時間：%@", value))
            }
        }
    }

    private func buildNFCPayload(for patientID: String, format: PatientNFCFormat) -> String {
        let compactID = compactPatientID(patientID)
        switch format {
        case .lg1:
            return [
                "LG1", compactID, triageCodeForNFC(), sexAgeCodeForNFC(), injuryCodeForNFC(),
                vitalsForNFC(), treatmentPayloadForNFC(format: .lg1), timeHM()
            ].joined(separator: "|")
        case .lg2:
            return [
                "LG2", "ID:\(compactID)", "T:\(triageCodeForNFC())", "S:\(sexAgeCodeForNFC())",
                "LOC:\(locationCodeForNFC())", "I:\(injuryCodeForNFC())", "V:\(vitalsForNFC())",
                "TX:\(treatmentPayloadForNFC(format: .lg2))", "ALG:\(codeValue(nfcAllergyCode))",
                "NOTE:\(noteForNFC())",
                "TM:\(timeFull())", "UPD:\(timeHM())"
            ].joined(separator: "|")
        case .lg3:
            let body = [
                "LG3", "ID:\(compactID)", "T:\(triageCodeForNFC())", "S:\(sexAgeCodeForNFC())",
                "LOC:\(locationCodeForNFC())", "GPS:\(gpsForNFC())", "I:\(injuryCodeForNFC())",
                "V:\(timeHM())/\(vitalsForNFC())", "TX:\(treatmentPayloadForNFC(format: .lg3))",
                "ALG:\(codeValue(nfcAllergyCode))", "FLAG:\(flagCodeForNFC())",
                "EVAC:\(codeValue(nfcEvacStatus, fallback: "WAIT"))", "DST:\(codeValue(nfcDestinationCode))",
                "TEAM:\(treatmentTeamCodeForNFC())", "TM:\(timeFull())", "UPD:\(timeHM())"
            ].joined(separator: "|")
            return "\(body)|CHK:\(nfcChecksum(for: body))"
        }
    }

    private func applyLG1Payload(_ payload: String) {
        let parts = payload.components(separatedBy: "|")
        guard parts.count >= 8 else {
            nfcManager.statusText = L("LG1 欄位不足")
            return
        }
        applyPatientID(parts[1])
        nfcTriageCode = codeValue(parts[2], fallback: "U")
        nfcSexAgeCode = codeValue(parts[3], fallback: "U")
        nfcInjuryCode = codeValue(parts[4])
        applyVitals(parts[5])
        applyTreatment(parts[6], version: .lg1)
        notes = appendNote(notes, L("NFC LG1 時間：%@", formatHM(parts[7])))
        for part in parts.dropFirst(8) {
            if let flags = payloadValue(after: "F:", in: part) ?? payloadValue(after: "FLAG:", in: part) {
                nfcFlagCode = codeValue(flags)
            }
        }
        selectedNFCFormat = .lg1
        updateNFCSummary(version: "LG1")
        nfcManager.statusText = L("NFC LG1 已讀取")
    }

    private func applyKeyedNFCPayload(_ payload: String, version: PatientNFCFormat) {
        let parts = payload.components(separatedBy: "|")
        var fields: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let separator = part.firstIndex(of: ":") else { continue }
            let key = String(part[..<separator]).uppercased()
            let value = String(part[part.index(after: separator)...])
            fields[key] = value
        }

        if let id = fields["ID"] { applyPatientID(id) }
        if let triage = fields["T"] { nfcTriageCode = codeValue(triage, fallback: "U") }
        if let sexAge = fields["S"] { nfcSexAgeCode = codeValue(sexAge, fallback: "U") }
        if let loc = fields["LOC"], !loc.isEmpty { location = loc }
        if let injury = fields["I"] { nfcInjuryCode = codeValue(injury) }
        if let vitals = fields["V"] { applyVitals(vitals) }
        if let tx = fields["TX"] { applyTreatment(tx, version: version) }
        if let alg = fields["ALG"] { nfcAllergyCode = codeValue(alg) }
        if let note = fields["NOTE"], !note.isEmpty { notes = appendNote(notes, L("NFC 備註：%@", note)) }
        if let flag = fields["FLAG"] { nfcFlagCode = codeValue(flag) }
        if let evac = fields["EVAC"] { nfcEvacStatus = codeValue(evac, fallback: "WAIT") }
        if let dst = fields["DST"] { nfcDestinationCode = codeValue(dst) }
        if let team = fields["TEAM"] { nfcTeamCode = codeValue(team) }
        if let tm = fields["TM"], !tm.isEmpty { notes = appendNote(notes, L("NFC 建立：%@", tm)) }
        if let upd = fields["UPD"], !upd.isEmpty { notes = appendNote(notes, L("NFC 更新：%@", formatHM(upd))) }

        selectedNFCFormat = version
        updateNFCSummary(version: version.rawValue)
        if version == .lg3, let checksum = fields["CHK"] {
            let body = parts.dropLast().joined(separator: "|")
            nfcManager.statusText = checksum == nfcChecksum(for: body) ? L("NFC LG3 已讀取") : L("NFC LG3 已讀取（校驗待確認）")
        } else {
            nfcManager.statusText = L("NFC %@ 已讀取", version.rawValue)
        }
    }

    private func applyEncryptedLG3Payload(_ payload: String) {
        let parts = payload.components(separatedBy: "|")
        for part in parts.dropFirst() {
            if let id = payloadValue(after: "ID:", in: part) { applyPatientID(id) }
            if let keyID = payloadValue(after: "KID:", in: part) { notes = appendNote(notes, L("LG3E 金鑰：%@", keyID)) }
        }
        selectedNFCFormat = .lg3
        updateNFCSummary(version: "LG3E")
        nfcManager.statusText = L("NFC LG3E 已讀取（需 App 解密）")
    }

    private func applyPatientID(_ idText: String) {
        if let displayID = vm.displayPatientID(from: idText) {
            patientIdOverride = displayID
        }
    }

    private func applyVitals(_ vitalsText: String) {
        let latest = vitalsText.components(separatedBy: ";").last ?? vitalsText
        for rawSegment in latest.components(separatedBy: "/") {
            let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let rr = payloadValue(after: "RR", in: segment) {
                breathingRateText = rr
            } else if let pulse = payloadValue(after: "P", in: segment) {
                nfcPulseText = pulse
            } else if let gcs = payloadValue(after: "G", in: segment) {
                nfcGCSText = gcs
                if let gcsValue = Int(gcs) { canFollowCommands = gcsValue >= 13 }
            }
        }
    }

    private func updateNFCSummary(version: String) {
        var lines = ["\(version) \(compactPatientID(activePatientID))"]
        lines.append("\(L("檢傷")): \(triageLabel(nfcTriageCode))")
        lines.append("\(L("性別年齡")): \(nfcSexAgeCode)")
        if !nfcInjuryCode.isEmpty { lines.append("\(L("傷勢")): \(nfcInjuryCode)") }
        if !breathingRateText.isEmpty || !nfcPulseText.isEmpty || !nfcGCSText.isEmpty {
            lines.append("\(L("生命徵象")): \(vitalsForNFC())")
        }
        if !nfcTreatmentCode.isEmpty { lines.append("\(L("處置")): \(nfcTreatmentCode)") }
        if !nfcFlagCode.isEmpty { lines.append("\(L("警示")): \(nfcFlagCode)") }
        if selectedNFCFormat == .lg3, !nfcEvacStatus.isEmpty { lines.append("\(L("後送")): \(evacuationLabel(nfcEvacStatus))") }
        nfcDecodedSummary = lines.joined(separator: "\n")
    }

    private func compactPatientID(_ idText: String) -> String {
        PatientIDConfig.extractCompactID(from: idText) ?? idText.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func triageCodeForNFC() -> String { codeValue(nfcTriageCode, fallback: "U") }

    private func sexAgeCodeForNFC() -> String { codeValue(nfcSexAgeCode, fallback: "U") }

    private func injuryCodeForNFC() -> String {
        let fallback = canFollowCommands ? "" : "UNCON"
        return codeValue(nfcInjuryCode, fallback: fallback)
    }

    private func treatmentCodesForNFC() -> [String] {
        codeValue(nfcTreatmentCode)
            .components(separatedBy: "+")
            .map { codeValue($0) }
            .filter { !$0.isEmpty }
    }

    private func treatmentBodyCodeForNFC() -> String { codeValue(nfcTreatmentBodyCode, fallback: "GEN") }

    private func treatmentStatusCodeForNFC() -> String { codeValue(nfcTreatmentStatusCode, fallback: "DONE") }

    private func treatmentTeamCodeForNFC() -> String { codeValue(nfcTeamCode, fallback: "UNK") }

    private func flagCodeForNFC() -> String { codeValue(nfcFlagCode) }

    private func treatmentPayloadForNFC(format: PatientNFCFormat) -> String {
        let codes = treatmentCodesForNFC()
        guard !codes.isEmpty else { return "NONE" }

        switch format {
        case .lg1:
            return codes.joined(separator: "+")
        case .lg2:
            return codes.joined(separator: "+")
        case .lg3:
            let team = treatmentTeamCodeForNFC()
            let status = treatmentStatusCodeForNFC()
            return codes.map { "\(timeHM())/\($0)/\(treatmentBodyCodeForNFC())/\(team)/\(status)" }.joined(separator: ";")
        }
    }

    private func vitalsForNFC() -> String {
        let rr = numericCode(breathingRateText, prefix: "RR", fallback: "RRU")
        let pulse = numericCode(nfcPulseText, prefix: "P", fallback: "PU")
        let gcsFallback = canFollowCommands ? "G15" : "G12"
        let gcs = numericCode(nfcGCSText, prefix: "G", fallback: gcsFallback)
        return "\(rr)/\(pulse)/\(gcs)"
    }

    private func locationCodeForNFC() -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? configuredLocationCode(separator: "-") : codeValue(trimmed, fallback: configuredLocationCode(separator: "-"))
    }

    private func configuredLocationCode(separator: String) -> String {
        let config = vm.patientIDConfig
        return [config.siteCode, config.buildingCode, config.floorCode, config.zoneCode]
            .map { codeValue($0) }
            .joined(separator: separator)
    }

    private func gpsForNFC() -> String {
        guard let coordinate = locationMgr.lastLocation?.coordinate else { return "" }
        return String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    private func noteForNFC() -> String {
        let firstLine = notes.components(separatedBy: .newlines).first ?? ""
        return codeValue(String(firstLine.prefix(32)))
    }

    private func codeValue(_ value: String, fallback: String = "") -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-.,/;")
        let uppercased = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sanitized = String(uppercased.unicodeScalars.filter { allowed.contains($0) })
        return sanitized.isEmpty ? fallback : sanitized
    }

    private func numericCode(_ value: String, prefix: String, fallback: String) -> String {
        let digits = value.filter { $0.isNumber || $0 == "-" }
        return digits.isEmpty ? fallback : "\(prefix)\(digits)"
    }

    private func applyTreatment(_ value: String, version: PatientNFCFormat) {
        let normalizedValue = payloadValue(after: "TX:", in: value) ?? value
        let entries = normalizedValue.components(separatedBy: ";")
        var codes: [String] = []
        var firstBody = ""
        var firstTeam = ""
        var firstStatus = ""

        for entry in entries {
            let parts = entry.components(separatedBy: "/").map { codeValue($0) }
            if parts.count >= 2 {
                if !parts[1].isEmpty { codes.append(parts[1]) }
                if firstBody.isEmpty, parts.count >= 3 { firstBody = parts[2] }
                if firstTeam.isEmpty, parts.count >= 4 { firstTeam = parts[3] }
                if firstStatus.isEmpty, parts.count >= 5 { firstStatus = parts[4] }
            } else {
                codes.append(contentsOf: entry.components(separatedBy: "+").map { codeValue($0) }.filter { !$0.isEmpty })
            }
        }

        nfcTreatmentCode = codes.joined(separator: "+")
        if !firstBody.isEmpty { nfcTreatmentBodyCode = firstBody }
        if version == .lg3, !firstTeam.isEmpty { nfcTeamCode = firstTeam }
        if version == .lg3, !firstStatus.isEmpty { nfcTreatmentStatusCode = firstStatus }
    }

    private func nfcChecksum(for text: String) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let total = text.utf8.reduce(23) { (($0 * 31) + Int($1)) % 1296 }
        return "\(alphabet[total / 36])\(alphabet[total % 36])"
    }

    private func timeHM() -> String {
        LGDateFormat.hm.string(from: Date()).replacingOccurrences(of: ":", with: "")
    }

    private func timeFull() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "yyyyMMdd'T'HHmm"
        return formatter.string(from: Date())
    }

    private func formatHM(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        guard digits.count == 4 else { return value }
        return "\(digits.prefix(2)):\(digits.suffix(2))"
    }

    private func triageLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "R": return "R - \(L("紅色"))"
        case "Y": return "Y - \(L("黃色"))"
        case "G": return "G - \(L("綠色"))"
        case "B": return "B - \(L("黑色"))"
        default: return "U - \(L("未分類"))"
        }
    }

    private func evacuationLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "MOVE": return "MOVE - \(L("後送中"))"
        case "ARRV": return "ARRV - \(L("已抵達"))"
        case "HOLD": return "HOLD - \(L("暫留"))"
        case "DEAD": return "DEAD - \(L("死亡確認"))"
        default: return "WAIT - \(L("等待後送"))"
        }
    }

    private func payloadValue(after prefix: String, in text: String) -> String? {
        guard text.hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private func appendNote(_ current: String, _ line: String) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? line : "\(trimmed)\n\(line)"
    }

    // MARK: - 驗證

    private var isFormValid: Bool {
        !location.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(breathingRateText) != nil &&
        Double(capillaryRefillText) != nil
    }

    // MARK: - 送出

    private func submitReport() {
        guard let breathingRate = Int(breathingRateText),
              let capillaryRefill = Double(capillaryRefillText) else { return }

        let patientID = patientIdOverride ?? vm.reserveNextPatientID()

        let report = PatientReport(
            patientId: patientID,
            nationalId: nationalId.trimmingCharacters(in: .whitespaces),
            name: patientName.trimmingCharacters(in: .whitespaces),
            birthDate: birthDateString ?? "",
            age: calculatedAge,
            location: location.trimmingCharacters(in: .whitespaces),
            breathingRate: breathingRate,
            capillaryRefill: capillaryRefill,
            canFollowCommands: canFollowCommands,
            gpsLat: locationMgr.lastLocation?.coordinate.latitude,
            gpsLon: locationMgr.lastLocation?.coordinate.longitude,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )

        vm.sendPatientReport(report)

        // 清空表單
        patientIdOverride = nil
        nationalId = ""
        patientName = ""
        birthYearText = ""
        birthMonthText = ""
        birthDayText = ""
        useROC = false
        location = ""
        breathingRateText = ""
        capillaryRefillText = ""
        canFollowCommands = false
        notes = ""

        // 顯示確認提示
        confirmationMessage = L("傷員回報已送出")
        withAnimation { showConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showConfirmation = false }
        }
    }
}
