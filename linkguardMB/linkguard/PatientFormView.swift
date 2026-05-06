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
        case write(String)
    }

    @Published var statusText: String = L("NFC 待命")
    @Published var lastPayload: String = ""

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .read
    private var onRead: ((String) -> Void)?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    func beginRead(onRead: @escaping (String) -> Void) {
        guard isAvailable else {
            statusText = L("此裝置不支援 NFC")
            return
        }

        mode = .read
        self.onRead = onRead
        statusText = L("請靠近傷患 NFC 標籤")
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = L("靠近傷患 NFC 標籤以讀取回報資料")
        session?.begin()
    }

    func beginWrite(payload: String) {
        guard isAvailable else {
            statusText = L("此裝置不支援 NFC")
            return
        }

        mode = .write(payload)
        statusText = L("請靠近可寫入的 NFC 標籤")
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = L("靠近空白或可覆寫的 NFC 標籤")
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            let nsError = error as NSError
            if nsError.code != NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
                self.statusText = L("NFC 已停止：%@", error.localizedDescription)
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard case .read = mode else { return }
        let payload = messages
            .flatMap(\.records)
            .compactMap { PatientNFCManager.text(from: $0) }
            .first ?? ""

        DispatchQueue.main.async {
            guard !payload.isEmpty else {
                self.statusText = L("NFC 標籤沒有可讀取的文字資料")
                return
            }
            self.lastPayload = payload
            self.statusText = L("NFC 讀取完成")
            self.onRead?(payload)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard case .write(let payload) = mode else { return }
        guard let tag = tags.first else {
            session.invalidate(errorMessage: L("找不到 NFC 標籤"))
            return
        }

        if tags.count > 1 {
            session.alertMessage = L("一次只靠近一張 NFC 標籤")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { session.restartPolling() }
            return
        }

        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }

            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    session.invalidate(errorMessage: error.localizedDescription)
                    return
                }

                guard status == .readWrite else {
                    session.invalidate(errorMessage: L("此 NFC 標籤不可寫入"))
                    return
                }

                let message = NFCNDEFMessage(records: [PatientNFCManager.record(from: payload)])
                guard message.length <= capacity else {
                    session.invalidate(errorMessage: L("NFC 標籤容量不足"))
                    return
                }

                tag.writeNDEF(message) { error in
                    if let error {
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        session.alertMessage = L("傷患 NFC 標籤寫入完成")
                        session.invalidate()
                        DispatchQueue.main.async {
                            self.lastPayload = payload
                            self.statusText = L("NFC 寫入完成")
                        }
                    }
                }
            }
        }
    }

    private static func record(from text: String) -> NFCNDEFPayload {
        NFCNDEFPayload.wellKnownTypeTextPayload(string: text, locale: Locale(identifier: "zh-Hant"))!
    }

    private static func text(from record: NFCNDEFPayload) -> String? {
        if let decoded = record.wellKnownTypeTextPayload().0 {
            return decoded
        }
        return String(data: record.payload, encoding: .utf8)
    }
}
#else
private final class PatientNFCManager: ObservableObject {
    @Published var statusText: String = L("NFC 僅支援 iPhone 實機")
    @Published var lastPayload: String = ""
    var isAvailable: Bool { false }
    func beginRead(onRead: @escaping (String) -> Void) { statusText = L("NFC 僅支援 iPhone 實機") }
    func beginWrite(payload: String) { statusText = L("NFC 僅支援 iPhone 實機") }
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

struct PatientFormView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @StateObject private var voiceManager = VoiceInputManager()
    @StateObject private var locationMgr = PatientLocationManager()
    @StateObject private var nfcManager = PatientNFCManager()

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
            // 傷員 ID（自動生成，僅顯示預覽）
            Section {
                HStack {
                    Text(L("傷員 ID"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("P\(Int(Date().timeIntervalSince1970))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                } header: {
                    Text(L("自動生成"))
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

                    HStack(spacing: 12) {
                        Button {
                            nfcManager.beginRead { payload in
                                applyNFCPayload(payload)
                            }
                        } label: {
                            Label(L("讀取"), systemImage: "wave.3.right")
                        }
                        .disabled(!nfcManager.isAvailable)

                        Button {
                            nfcManager.beginWrite(payload: currentNFCPayload())
                        } label: {
                            Label(L("寫入"), systemImage: "square.and.pencil")
                        }
                        .disabled(!nfcManager.isAvailable)
                    }
                } header: {
                    Text(L("NFC 讀取／寫入"))
                } footer: {
                    Text(L("支援 LinkGuard LG1 文字格式，可將傷患 ID、分級、年齡、傷勢與生命徵象同步到 NFC 標籤。"))
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

    private func currentNFCPayload() -> String {
        var fields = ["LG1"]
        fields.append("ID:\(nationalId.isEmpty ? "P\(Int(Date().timeIntervalSince1970))" : nationalId.trimmingCharacters(in: .whitespaces))")
        if let age = calculatedAge { fields.append("AGE:\(age)") }
        if !location.trimmingCharacters(in: .whitespaces).isEmpty { fields.append("LOC:\(location.trimmingCharacters(in: .whitespaces))") }
        if !breathingRateText.isEmpty { fields.append("RR\(breathingRateText)") }
        fields.append("CMD:\(canFollowCommands ? "Y" : "N")")
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty { fields.append("NOTE:\(notes.trimmingCharacters(in: .whitespaces))") }
        fields.append("TIME:\(LGDateFormat.hm.string(from: Date()).replacingOccurrences(of: ":", with: ""))")
        return fields.joined(separator: "|")
    }

    private func applyNFCPayload(_ payload: String) {
        let parts = payload.split(separator: "|").map(String.init)
        guard parts.first == "LG1" else {
            nfcManager.statusText = L("NFC 格式不是 LinkGuard LG1")
            return
        }

        for part in parts.dropFirst() {
            if let value = value(after: "ID:", in: part) {
                nationalId = value
            } else if let value = value(after: "AGE:", in: part) {
                notes = appendNote(notes, L("NFC 年齡：%@", value))
            } else if let value = value(after: "INJ:", in: part) {
                notes = appendNote(notes, L("傷勢：%@", value))
            } else if let value = value(after: "TX:", in: part) {
                notes = appendNote(notes, L("處置：%@", value))
            } else if let value = value(after: "LOC:", in: part) {
                location = value
            } else if let value = value(after: "RR", in: part) ?? value(after: "RR:", in: part) {
                breathingRateText = value
            } else if let value = value(after: "GCS", in: part) ?? value(after: "GCS:", in: part) {
                if let gcs = Int(value) { canFollowCommands = gcs >= 13 }
                notes = appendNote(notes, "GCS\(value)")
            } else if let value = value(after: "T:", in: part) {
                notes = appendNote(notes, L("分級：%@", value))
            } else if let value = value(after: "TIME:", in: part) {
                notes = appendNote(notes, L("標籤時間：%@", value))
            }
        }
    }

    private func value(after prefix: String, in text: String) -> String? {
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

        let report = PatientReport(
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
