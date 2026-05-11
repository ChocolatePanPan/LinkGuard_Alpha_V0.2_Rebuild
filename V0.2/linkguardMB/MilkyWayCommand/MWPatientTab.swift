import SwiftUI
import CoreLocation
import Combine

// MARK: - GPS 定位

private final class MWPatientLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        // startUpdatingLocation() 等授權後在 delegate 裡呼叫
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

// MARK: - 傷患表單 Tab

struct MWPatientTab: View {
    @StateObject private var locationMgr = MWPatientLocationManager()

    // 身分資料
    @State private var nationalId = ""
    @State private var patientName = ""
    @State private var useROC = false
    @State private var birthYearText = ""
    @State private var birthMonthText = ""
    @State private var birthDayText = ""

    private enum DateField: Hashable { case year, month, day }
    @FocusState private var focusedDateField: DateField?

    // 生命跡象 / 位置
    @State private var location = ""
    @State private var breathingRateText = ""
    @State private var capillaryRefillText = ""
    @State private var canFollowCommands = false
    @State private var notes = ""

    // 回饋
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    // 傷員 ID 在表單建立時就固定，進入送出時不再重算
    @State private var patientId: String = "P\(Int(Date().timeIntervalSince1970))"

    // iPad 雙欄判斷
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var yearMaxLen: Int { useROC ? 3 : 4 }

    private var ceYear: Int? {
        guard let y = Int(birthYearText) else { return nil }
        return useROC ? y + 1911 : y
    }

    private var birthDateString: String? {
        guard let y = ceYear,
              let m = Int(birthMonthText), (1...12).contains(m),
              let d = Int(birthDayText), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

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

    private var breathingRate: Int? { Int(breathingRateText) }
    private var capillaryRefill: Int? { Int(capillaryRefillText) }

    var body: some View {
        NavigationStack {
            Form {
                if hSizeClass == .regular {
                    // iPad 橫屏：雙欄展示
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            identityColumn
                            vitalSignsColumn
                        }
                    }
                } else {
                    identitySection
                    vitalSignsSection
                }

                // 送出
                Section {
                    Button {
                        submitPatient()
                    } label: {
                        HStack {
                            Spacer()
                            Label("提交傷患回報", systemImage: "paperplane.fill")
                                .font(.headline.bold())
                            Spacer()
                        }
                        .frame(height: MWTouch.minH)
                        .contentShape(Rectangle())
                    }
                    .tint(MWTheme.green)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MWTheme.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("傷患表單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清除") { clearForm() }
                        .foregroundStyle(MWTheme.amber)
                }
            }
            .alert("傷患回報", isPresented: $showConfirmation) {
                Button("確認") { }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    // MARK: - 身分欄（獨立 section / 雙欄 column）

    @ViewBuilder
    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("身分資料").font(.headline).padding(.bottom, 8)
            identityRows
        }
    }

    private var identitySection: some View {
        Section("身分資料") {
            identityRows
        }
    }

    @ViewBuilder
    private var identityRows: some View {
        // 傷員 ID 預覽
        HStack {
            Text("傷員 ID").foregroundStyle(.secondary)
            Spacer()
            Text(patientId)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: MWTouch.minH)

        // 身分證
        HStack {
            Image(systemName: "person.text.rectangle").foregroundStyle(MWTheme.cyan).frame(width: 24)
            TextField("身分證字號", text: $nationalId)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .frame(minHeight: MWTouch.minH)

        // 姓名
        HStack {
            Image(systemName: "person.fill").foregroundStyle(MWTheme.cyan).frame(width: 24)
            TextField("姓名", text: $patientName)
        }
        .frame(minHeight: MWTouch.minH)

        // 曆法切換
        Picker("曆法", selection: $useROC) {
            Text("西元").tag(false)
            Text("民國").tag(true)
        }
        .pickerStyle(.segmented)
        .onChange(of: useROC) { _, _ in birthYearText = ""; focusedDateField = .year }

        // 出生日期
        HStack(spacing: 6) {
            Image(systemName: "calendar").foregroundStyle(MWTheme.violet).frame(width: 24)
            TextField(useROC ? "民國年" : "西元年", text: $birthYearText)
                .frame(maxWidth: 90)
                .focused($focusedDateField, equals: .year)
                .keyboardType(.numberPad)
                .onChange(of: birthYearText) { _, val in
                    let f = String(val.prefix(yearMaxLen)).filter { $0.isNumber }
                    if f != val { birthYearText = f }
                    if f.count >= yearMaxLen { focusedDateField = .month }
                }
            Text("/").foregroundStyle(.secondary)
            TextField("月", text: $birthMonthText)
                .frame(maxWidth: 56)
                .focused($focusedDateField, equals: .month)
                .keyboardType(.numberPad)
                .onChange(of: birthMonthText) { _, val in
                    let f = String(val.prefix(2)).filter { $0.isNumber }
                    if f != val { birthMonthText = f }
                    if f.count >= 2 { focusedDateField = .day }
                }
            Text("/").foregroundStyle(.secondary)
            TextField("日", text: $birthDayText)
                .frame(maxWidth: 56)
                .focused($focusedDateField, equals: .day)
                .keyboardType(.numberPad)
                .onChange(of: birthDayText) { _, val in
                    let f = String(val.prefix(2)).filter { $0.isNumber }
                    if f != val { birthDayText = f }
                    if f.count >= 2 { focusedDateField = nil }
                }
            if let age = calculatedAge {
                Spacer()
                Text("\(age) 歲")
                    .font(.subheadline.bold())
                    .foregroundStyle(MWTheme.green)
            }
        }
        .frame(minHeight: MWTouch.minH)
    }

    // MARK: - 生命跡象欄

    @ViewBuilder
    private var vitalSignsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("生命跡象 / 位置").font(.headline).padding(.bottom, 8)
            vitalRows
        }
    }

    private var vitalSignsSection: some View {
        Section("生命跡象 / 位置") {
            vitalRows
        }
    }

    @ViewBuilder
    private var vitalRows: some View {
        // 位置
        HStack {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(MWTheme.amber).frame(width: 24)
            TextField("例：A區 3F 走廊", text: $location)
        }
        .frame(minHeight: MWTouch.minH)

        // GPS 座標
        if let loc = locationMgr.lastLocation {
            HStack {
                Image(systemName: "location.fill").foregroundStyle(MWTheme.green).frame(width: 24)
                Text(String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: MWTouch.minH)
        }

        // 呼吸速率
        HStack {
            Image(systemName: breathingRateText == "-1" ? "lungs.fill" : "lungs")
                .foregroundStyle(breathingRateText == "-1" ? MWTheme.red : MWTheme.violet)
                .frame(width: 24)
            TextField("呼吸速率（次/分，-1=無）", text: $breathingRateText)
                .keyboardType(.numbersAndPunctuation)
        }
        .frame(minHeight: MWTouch.minH)

        // 毛細血管充盈
        HStack {
            Image(systemName: "drop.fill").foregroundStyle(MWTheme.cyan).frame(width: 24)
            TextField("毛細血管充盈（秒，≥2=異常）", text: $capillaryRefillText)
                .keyboardType(.decimalPad)
        }
        .frame(minHeight: MWTouch.minH)

        // 聽令
        Toggle(isOn: $canFollowCommands) {
            HStack {
                Image(systemName: "ear.fill").foregroundStyle(MWTheme.green).frame(width: 24)
                Text("可聽令")
            }
        }
        .frame(minHeight: MWTouch.minH)

        // 備註
        HStack(alignment: .top) {
            Image(systemName: "note.text").foregroundStyle(.secondary).frame(width: 24).padding(.top, 2)
            TextField("備註 / 傷情描述", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - 動作

    private func submitPatient() {
        var lines: [String] = []
        lines.append("傷員 ID：\(patientId)")
        if !patientName.isEmpty { lines.append("姓名：\(patientName)") }
        if !nationalId.isEmpty { lines.append("身分證：\(nationalId)") }
        if let age = calculatedAge { lines.append("年齡：\(age) 歲") }
        if !location.isEmpty { lines.append("位置：\(location)") }
        if let loc = locationMgr.lastLocation {
            lines.append(String(format: "GPS：%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
        }
        if !breathingRateText.isEmpty { lines.append("呼吸：\(breathingRateText) 次/分") }
        if !capillaryRefillText.isEmpty { lines.append("毛細：\(capillaryRefillText) 秒") }
        lines.append("聽令：\(canFollowCommands ? "是" : "否")")
        if !notes.isEmpty { lines.append("備註：\(notes)") }

        confirmationMessage = lines.joined(separator: "\n")
        showConfirmation = true
    }

    private func clearForm() {
        nationalId = ""; patientName = ""; birthYearText = ""; birthMonthText = ""; birthDayText = ""
        location = ""; breathingRateText = ""; capillaryRefillText = ""; canFollowCommands = false
        notes = ""; useROC = false
    }
}
