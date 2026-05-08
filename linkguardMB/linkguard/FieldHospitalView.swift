import SwiftUI
import CoreLocation
import Combine

// MARK: - GPS City Locator (iOS)

private final class FieldCityLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var detectedCity: String? = nil
    @Published var isLocating = false
    @Published var errorMsg: String? = nil

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        errorMsg = nil
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default:
            isLocating = false
            errorMsg = L("位置權限未開放")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { isLocating = false; return }
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                self?.isLocating = false
                let raw = placemarks?.first?.subAdministrativeArea
                    ?? placemarks?.first?.administrativeArea ?? ""
                let normalized = raw.replacingOccurrences(of: "台", with: "臺")
                let allCities = Array(Set(FieldHospitalDirectory.all.map(\.city)))
                self?.detectedCity = allCities.first { $0.hasPrefix(normalized) || normalized.hasPrefix($0) }
                    ?? allCities.first { $0.contains(normalized) || normalized.contains($0) }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.isLocating = false; self.errorMsg = L("定位失敗") }
    }
}

// MARK: - 預先計算靜態資料

private enum FieldPointMode: String, CaseIterable, Hashable {
    case hospitals = "後送醫院"
    case responseCenters = "應變中心"
    case rescueUnits = "救援單位"
    case fireTraining = "訓練機構"

    var label: String { L(rawValue) }

    var supportKind: FieldSupportSite.Kind? {
        switch self {
        case .hospitals, .fireTraining: return nil
        case .responseCenters: return .responseCenter
        case .rescueUnits: return .rescueUnit
        }
    }

    var count: Int {
        switch self {
        case .hospitals: return FieldHospitalDirectory.all.count
        case .responseCenters: return FieldSupportSiteDirectory.responseCenters.count
        case .rescueUnits: return FieldSupportSiteDirectory.rescueUnits.count
        case .fireTraining: return FieldFireTrainingInstitutionDirectory.all.count
        }
    }

    var title: String {
        switch self {
        case .hospitals: return L("後送醫院（%lld 家）", count)
        case .responseCenters: return L("應變中心（%lld 筆）", count)
        case .rescueUnits: return L("救援單位（%lld 筆）", count)
        case .fireTraining: return L("防火訓練機構（%lld 筆）", count)
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .hospitals: return L("搜尋縣市 / 醫院名稱")
        case .responseCenters, .rescueUnits: return L("搜尋縣市 / 名稱 / 地址")
        case .fireTraining: return L("搜尋縣市 / 名稱 / 地址 / 聯絡人")
        }
    }

    var emptyMessage: String {
        switch self {
        case .hospitals: return L("沒有符合的醫院")
        case .responseCenters, .rescueUnits: return L("沒有符合的點位")
        case .fireTraining: return L("沒有符合的機構")
        }
    }
}

private let allGrouped = FieldHospitalDirectory.grouped()
private let allRegions = FieldHospital.Region.allCases
private let allLevels = FieldHospital.Level.allCases
private let allCitiesByRegion: [FieldHospital.Region?: [String]] = {
    var result: [FieldHospital.Region?: [String]] = [:]
    result[nil] = Array(Set(FieldHospitalDirectory.all.map(\.city))).sorted()
    for r in FieldHospital.Region.allCases {
        result[r] = Array(Set(FieldHospitalDirectory.all.filter { $0.region == r }.map(\.city))).sorted()
    }
    return result
}()

private func pointCities(for mode: FieldPointMode, region: FieldHospital.Region?) -> [String] {
    switch mode {
    case .hospitals:
        return allCitiesByRegion[region] ?? []
    case .responseCenters, .rescueUnits:
        guard let kind = mode.supportKind else { return [] }
        return FieldSupportSiteDirectory.cities(kind: kind, region: region)
    case .fireTraining:
        return FieldFireTrainingInstitutionDirectory.cities(region: region)
    }
}

// MARK: - View

struct FieldHospitalView: View {
    @StateObject private var locator = FieldCityLocator()
    @EnvironmentObject private var l10n: L10n

    // 篩選狀態
    @State private var selectedMode: FieldPointMode = .hospitals
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedRegion: FieldHospital.Region? = nil
    @State private var selectedLevel: FieldHospital.Level? = nil
    @State private var selectedCity: String? = nil

    // 快取結果（onChange 更新，避免每次 render 重算）
    @State private var filteredGroups: [(region: FieldHospital.Region, items: [FieldHospital])] = allGrouped
    @State private var filteredSupportGroups: [(region: FieldHospital.Region, items: [FieldSupportSite])] = []
    @State private var filteredTrainingGroups: [(region: FieldHospital.Region, items: [FieldFireTrainingInstitution])] = []
    @State private var availableCities: [String] = pointCities(for: .hospitals, region: nil)

    // debounce timer
    @State private var debounceTask: AnyCancellable? = nil

    var body: some View {
        VStack(spacing: 0) {
            filterHeader
            Divider()
            List {
                switch selectedMode {
                case .hospitals:
                    ForEach(filteredGroups, id: \.region) { group in
                        Section {
                            ForEach(group.items) { h in
                                HospitalRow(h: h)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(L("%@ （%lld 家）", group.region.label, group.items.count))
                            }
                        }
                    }
                    if filteredGroups.isEmpty {
                        Section {
                            Label(L("沒有符合的醫院"), systemImage: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                    }
                case .responseCenters, .rescueUnits:
                    ForEach(filteredSupportGroups, id: \.region) { group in
                        Section {
                            ForEach(group.items) { site in
                                SupportSiteRow(site: site)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(L("%@ （%lld 筆）", group.region.label, group.items.count))
                            }
                        }
                    }
                    if filteredSupportGroups.isEmpty {
                        Section {
                            Label(selectedMode.emptyMessage, systemImage: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                    }
                case .fireTraining:
                    ForEach(filteredTrainingGroups, id: \.region) { group in
                        Section {
                            ForEach(group.items) { institution in
                                FireTrainingInstitutionRow(institution: institution)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: "graduationcap.fill")
                                Text(L("%@ （%lld 筆）", group.region.label, group.items.count))
                            }
                        }
                    }
                    if filteredTrainingGroups.isEmpty {
                        Section {
                            Label(selectedMode.emptyMessage, systemImage: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                }
                .listStyle(.plain)
            }
            .outerNavigationTitle(selectedMode.title)
            .onChange(of: query) { q in
                debounceTask?.cancel()
                debounceTask = Just(q)
                    .delay(for: .milliseconds(250), scheduler: RunLoop.main)
                    .sink { val in
                        debouncedQuery = val
                        recompute()
                    }
            }
            .onChange(of: selectedMode) { _, _ in
                if selectedMode != .hospitals { selectedLevel = nil }
                availableCities = pointCities(for: selectedMode, region: selectedRegion)
                if let sel = selectedCity, !availableCities.contains(sel) { selectedCity = nil }
                recompute()
            }
            .onChange(of: selectedRegion) { _, _ in
                availableCities = pointCities(for: selectedMode, region: selectedRegion)
                if let sel = selectedCity, !availableCities.contains(sel) { selectedCity = nil }
                recompute()
            }
            .onChange(of: selectedCity) { _, _ in recompute() }
            .onChange(of: selectedLevel) { _, _ in recompute() }
            .onChange(of: l10n.language) { _, _ in recompute() }
            .onChange(of: locator.detectedCity) { _, city in
                guard let city else { return }
                selectedCity = city
                selectedRegion = nil
                availableCities = pointCities(for: selectedMode, region: nil)
            }
    }

    // MARK: - 篩選 header

    private var filterHeader: some View {
        VStack(spacing: 0) {
            Picker(L("點位類型"), selection: $selectedMode) {
                ForEach(FieldPointMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 搜尋列
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(selectedMode.searchPlaceholder, text: $query)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 20)
                Button {
                    locator.requestLocation()
                } label: {
                    if locator.isLocating {
                        ProgressView().scaleEffect(0.8).frame(width: 20, height: 20)
                    } else {
                        Image(systemName: selectedCity != nil && locator.detectedCity == selectedCity
                              ? "location.fill" : "location")
                            .foregroundColor(NV.info)
                    }
                }
                .buttonStyle(.plain)
                if selectedCity != nil {
                    Button { selectedCity = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let err = locator.errorMsg {
                Text(err).font(.caption2).foregroundColor(NV.danger).padding(.horizontal, 12).padding(.bottom, 4)
            } else if let city = locator.detectedCity {
                Label("\(L("已定位至"))：\(L(city))", systemImage: "location.fill")
                    .font(.caption2).foregroundColor(NV.info).padding(.horizontal, 12).padding(.bottom, 4)
            }

            Divider()

            // 區域 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: L("全部區域"), accent: NV.info, isSelected: selectedRegion == nil) {
                        selectedRegion = nil; selectedCity = nil
                        availableCities = allCitiesByRegion[nil] ?? []
                    }
                    ForEach(allRegions, id: \.self) { r in
                        chip(label: r.label, accent: NV.info, isSelected: selectedRegion == r) {
                            selectedRegion = r; selectedCity = nil
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // 縣市 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: L("全部縣市"), accent: NV.command, isSelected: selectedCity == nil) {
                        selectedCity = nil
                    }
                    ForEach(availableCities, id: \.self) { city in
                        chip(label: L(city), accent: NV.command, isSelected: selectedCity == city) {
                            selectedCity = city
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if selectedMode == .hospitals {
                Divider()

                // 層級 chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(label: L("全部層級"), accent: NV.green, isSelected: selectedLevel == nil) {
                            selectedLevel = nil
                        }
                        ForEach(allLevels, id: \.self) { lv in
                            chip(label: lv.label, accent: lv.color, isSelected: selectedLevel == lv) {
                                selectedLevel = lv
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - 過濾邏輯（在 onChange 中呼叫，不是 computed property）

    private func recompute() {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespaces)
        switch selectedMode {
        case .hospitals:
            let result = allGrouped.compactMap { group -> (region: FieldHospital.Region, items: [FieldHospital])? in
                if let r = selectedRegion, r != group.region { return nil }
                let items = group.items.filter { h in
                    if let city = selectedCity, h.city != city { return false }
                    if let lv = selectedLevel, lv != h.level { return false }
                    if trimmed.isEmpty { return true }
                    return h.name.localizedCaseInsensitiveContains(trimmed)
                        || h.englishName.localizedCaseInsensitiveContains(trimmed)
                        || h.city.localizedCaseInsensitiveContains(trimmed)
                }
                return items.isEmpty ? nil : (group.region, items)
            }
            filteredGroups = result
            filteredSupportGroups = []
            filteredTrainingGroups = []
            return

        case .responseCenters, .rescueUnits:
            guard let supportKind = selectedMode.supportKind else { return }
            let supportResult = FieldSupportSiteDirectory.grouped(kind: supportKind).compactMap { group -> (region: FieldHospital.Region, items: [FieldSupportSite])? in
                if let r = selectedRegion, r != group.region { return nil }
                let items = group.items.filter { site in
                    if let city = selectedCity, site.city != city { return false }
                    if trimmed.isEmpty { return true }
                    return site.name.localizedCaseInsensitiveContains(trimmed)
                        || site.address.localizedCaseInsensitiveContains(trimmed)
                        || site.phone.localizedCaseInsensitiveContains(trimmed)
                        || site.city.localizedCaseInsensitiveContains(trimmed)
                        || site.note.localizedCaseInsensitiveContains(trimmed)
                }
                return items.isEmpty ? nil : (group.region, items)
            }
            filteredGroups = []
            filteredSupportGroups = supportResult
            filteredTrainingGroups = []

        case .fireTraining:
            let trainingResult = FieldFireTrainingInstitutionDirectory.grouped().compactMap { group -> (region: FieldHospital.Region, items: [FieldFireTrainingInstitution])? in
                if let r = selectedRegion, r != group.region { return nil }
                let items = group.items.filter { institution in
                    if let city = selectedCity, institution.city != city { return false }
                    if trimmed.isEmpty { return true }
                    return institution.name.localizedCaseInsensitiveContains(trimmed)
                        || institution.address.localizedCaseInsensitiveContains(trimmed)
                        || institution.phone.localizedCaseInsensitiveContains(trimmed)
                        || institution.fax.localizedCaseInsensitiveContains(trimmed)
                        || institution.email.localizedCaseInsensitiveContains(trimmed)
                        || institution.website.localizedCaseInsensitiveContains(trimmed)
                        || institution.contact.localizedCaseInsensitiveContains(trimmed)
                        || institution.city.localizedCaseInsensitiveContains(trimmed)
                        || institution.postcode.localizedCaseInsensitiveContains(trimmed)
                }
                return items.isEmpty ? nil : (group.region, items)
            }
            filteredGroups = []
            filteredSupportGroups = []
            filteredTrainingGroups = trainingResult
        }
    }

    // MARK: - Chip

    private func chip(label: String, accent: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? accent : accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row（獨立 struct 防止不必要 re-render）

private struct HospitalRow: View {
    let h: FieldHospital
    @EnvironmentObject private var l10n: L10n

    var body: some View {
        let displayName = h.displayName(language: l10n.language)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: h.level.icon)
                    .foregroundColor(h.level.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName).font(.subheadline.bold())
                    if displayName != h.name {
                        Text(h.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(h.level.label)
                    .font(.caption2.bold())
                    .foregroundColor(h.level.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(h.level.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            if !h.address.isEmpty {
                Text(h.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if h.totalBeds > 0 {
                    Label(L("%lld 床", h.totalBeds), systemImage: "bed.double.fill")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if h.icuBeds > 0 {
                    Label(L("ICU %lld", h.icuBeds), systemImage: "waveform.path.ecg")
                        .font(.caption2).foregroundColor(.red.opacity(0.8))
                }
                if h.erBeds > 0 {
                    Label(L("急觀 %lld", h.erBeds), systemImage: "staroflife.fill")
                        .font(.caption2).foregroundColor(.orange.opacity(0.8))
                }
            }
            if !h.phone.isEmpty {
                Button {
                    if let url = URL(string: "tel://\(h.phone)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(h.phone, systemImage: "phone.fill")
                        .font(.caption.bold()).foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SupportSiteRow: View {
    let site: FieldSupportSite

    private var icon: String {
        switch site.kind {
        case .responseCenter: return "building.columns.fill"
        case .rescueUnit: return site.name.contains("特種搜救") ? "shield.lefthalf.filled" : "flame.fill"
        }
    }

    private var accent: Color {
        switch site.kind {
        case .responseCenter: return NV.command
        case .rescueUnit: return site.name.contains("特種搜救") ? NV.danger : NV.info
        }
    }

    private var badgeText: String? {
        switch site.kind {
        case .responseCenter:
            guard !site.note.isEmpty else { return nil }
            return site.note == "是" ? L("消防局同址") : site.note
        case .rescueUnit:
            if site.name.contains("特種搜救") { return L("特搜") }
            if site.name.contains("大隊") { return L("大隊") }
            if site.name.contains("分隊") { return L("分隊") }
            return L("消防局")
        }
    }

    private var dialablePhone: String? {
        guard !site.phone.isEmpty else { return nil }
        let first = site.phone.components(separatedBy: CharacterSet(charactersIn: "、,，；;()（）")).first ?? site.phone
        let cleaned = first.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" || $0 == "-" }
        return cleaned.isEmpty ? nil : cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.name).font(.subheadline.bold())
                    Text(L(site.city))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                if let badgeText {
                    Text(badgeText)
                        .font(.caption2.bold())
                        .foregroundColor(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            if !site.address.isEmpty {
                Text(site.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if let coordinateDescription = site.coordinateDescription {
                    Label(coordinateDescription, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if site.coordinateDescription == nil {
                    Label(L("無座標"), systemImage: "mappin.slash")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                if !site.phone.isEmpty {
                    Button {
                        if let dialablePhone, let url = URL(string: "tel://\(dialablePhone)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(site.phone, systemImage: "phone.fill")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                if let mapsURL = site.mapsURL {
                    Button {
                        UIApplication.shared.open(mapsURL)
                    } label: {
                        Label(L("開啟地圖"), systemImage: "map.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FireTrainingInstitutionRow: View {
    let institution: FieldFireTrainingInstitution

    private var dialablePhone: String? {
        guard !institution.phone.isEmpty else { return nil }
        let first = institution.phone.components(separatedBy: CharacterSet(charactersIn: "、,，；;()（）/／")).first ?? institution.phone
        let cleaned = first.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" || $0 == "-" }
        return cleaned.isEmpty ? nil : cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .foregroundColor(.purple)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(institution.name).font(.subheadline.bold())
                    Text([L(institution.city), institution.postcode].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Text(L("防火管理"))
                    .font(.caption2.bold())
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
            }
            if !institution.address.isEmpty {
                Text(institution.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !institution.contact.isEmpty {
                    Label(L("聯絡人：%@", institution.contact), systemImage: "person.crop.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !institution.phone.isEmpty {
                    Label(institution.phone, systemImage: "phone.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !institution.fax.isEmpty {
                    Label(L("傳真：%@", institution.fax), systemImage: "printer.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !institution.email.isEmpty {
                    Label(institution.email, systemImage: "envelope.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !institution.website.isEmpty {
                    Label(institution.website, systemImage: "safari.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                if let dialablePhone {
                    Button {
                        if let url = URL(string: "tel://\(dialablePhone)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(L("撥打"), systemImage: "phone.fill")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                if let emailURL = institution.emailURL {
                    Button {
                        UIApplication.shared.open(emailURL)
                    } label: {
                        Label(L("寄信"), systemImage: "envelope.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.info)
                    }
                    .buttonStyle(.plain)
                }
                if let websiteURL = institution.websiteURL {
                    Button {
                        UIApplication.shared.open(websiteURL)
                    } label: {
                        Label(L("網站"), systemImage: "safari.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.command)
                    }
                    .buttonStyle(.plain)
                }
                if let mapsURL = institution.mapsURL {
                    Button {
                        UIApplication.shared.open(mapsURL)
                    } label: {
                        Label(L("開啟地圖"), systemImage: "map.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

