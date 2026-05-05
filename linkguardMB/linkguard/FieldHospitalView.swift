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
            errorMsg = "位置權限未開放"
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
        DispatchQueue.main.async { self.isLocating = false; self.errorMsg = "定位失敗" }
    }
}

// MARK: - 預先計算靜態資料

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

// MARK: - View

struct FieldHospitalView: View {
    @StateObject private var locator = FieldCityLocator()
    @EnvironmentObject private var l10n: L10n

    // 篩選狀態
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedRegion: FieldHospital.Region? = nil
    @State private var selectedLevel: FieldHospital.Level? = nil
    @State private var selectedCity: String? = nil

    // 快取結果（onChange 更新，避免每次 render 重算）
    @State private var filteredGroups: [(region: FieldHospital.Region, items: [FieldHospital])] = allGrouped
    @State private var availableCities: [String] = allCitiesByRegion[nil]!

    // debounce timer
    @State private var debounceTask: AnyCancellable? = nil

    var body: some View {
        VStack(spacing: 0) {
            filterHeader
            Divider()
            List {
                    ForEach(filteredGroups, id: \.region) { group in
                        Section {
                            ForEach(group.items) { h in
                                HospitalRow(h: h)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text("\(group.region.rawValue)（\(group.items.count) 家）")
                            }
                        }
                    }
                    if filteredGroups.isEmpty {
                        Section {
                            Label(L("沒有符合的醫院"), systemImage: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .manualTopBar44(title: L("後送醫院（\(FieldHospitalDirectory.all.count) 家）"))
            .onChange(of: query) { q in
                debounceTask?.cancel()
                debounceTask = Just(q)
                    .delay(for: .milliseconds(250), scheduler: RunLoop.main)
                    .sink { val in
                        debouncedQuery = val
                        recompute()
                    }
            }
            .onChange(of: selectedRegion) { _, _ in
                availableCities = allCitiesByRegion[selectedRegion] ?? []
                if let sel = selectedCity, !availableCities.contains(sel) { selectedCity = nil }
                recompute()
            }
            .onChange(of: selectedCity) { _, _ in recompute() }
            .onChange(of: selectedLevel) { _, _ in recompute() }
            .onChange(of: locator.detectedCity) { _, city in
                guard let city else { return }
                selectedCity = city
                selectedRegion = nil
                availableCities = allCitiesByRegion[nil] ?? []
            }
    }

    // MARK: - 篩選 header

    private var filterHeader: some View {
        VStack(spacing: 0) {
            // 搜尋列
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(L("搜尋縣市 / 醫院名稱"), text: $query)
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
                Label("\(L("已定位至"))：\(city)", systemImage: "location.fill")
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
                        chip(label: r.rawValue, accent: NV.info, isSelected: selectedRegion == r) {
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
                        chip(label: city, accent: NV.command, isSelected: selectedCity == city) {
                            selectedCity = city
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // 層級 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: L("全部層級"), accent: NV.green, isSelected: selectedLevel == nil) {
                        selectedLevel = nil
                    }
                    ForEach(allLevels, id: \.self) { lv in
                        chip(label: lv.rawValue, accent: lv.color, isSelected: selectedLevel == lv) {
                            selectedLevel = lv
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - 過濾邏輯（在 onChange 中呼叫，不是 computed property）

    private func recompute() {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespaces)
        let result = allGrouped.compactMap { group -> (region: FieldHospital.Region, items: [FieldHospital])? in
            if let r = selectedRegion, r != group.region { return nil }
            let items = group.items.filter { h in
                if let city = selectedCity, h.city != city { return false }
                if let lv = selectedLevel, lv != h.level { return false }
                if trimmed.isEmpty { return true }
                return h.name.localizedCaseInsensitiveContains(trimmed)
                    || h.city.localizedCaseInsensitiveContains(trimmed)
            }
            return items.isEmpty ? nil : (group.region, items)
        }
        filteredGroups = result
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: h.level.icon)
                    .foregroundColor(h.level.color)
                    .frame(width: 18)
                Text(h.name).font(.subheadline.bold())
                Spacer(minLength: 0)
                Text(h.level.rawValue)
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
                    Label("\(h.totalBeds)床", systemImage: "bed.double.fill")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if h.icuBeds > 0 {
                    Label("ICU \(h.icuBeds)", systemImage: "waveform.path.ecg")
                        .font(.caption2).foregroundColor(.red.opacity(0.8))
                }
                if h.erBeds > 0 {
                    Label("急觀\(h.erBeds)", systemImage: "staroflife.fill")
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

