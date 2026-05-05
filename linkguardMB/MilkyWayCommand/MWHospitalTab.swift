import SwiftUI
import CoreLocation
import Combine

// MARK: - GPS 定位（Milky Way 版）

private final class MWCityLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
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
                let allCities = Array(Set(MWHospitalDirectory.all.map(\.city)))
                self?.detectedCity = allCities.first { $0.hasPrefix(normalized) || normalized.hasPrefix($0) }
                    ?? allCities.first { $0.contains(normalized) || normalized.contains($0) }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.isLocating = false; self.errorMsg = "定位失敗" }
    }
}

// MARK: - 靜態快取

private let mwAllGrouped = MWHospitalDirectory.grouped()
private let mwAllRegions = MWHospital.Region.allCases
private let mwAllLevels = MWHospital.Level.allCases
private let mwAllCitiesByRegion: [MWHospital.Region?: [String]] = {
    var result: [MWHospital.Region?: [String]] = [:]
    result[nil] = Array(Set(MWHospitalDirectory.all.map(\.city))).sorted()
    for r in MWHospital.Region.allCases {
        result[r] = Array(Set(MWHospitalDirectory.all.filter { $0.region == r }.map(\.city))).sorted()
    }
    return result
}()

// MARK: - 後送醫院 Tab

struct MWHospitalTab: View {
    @StateObject private var locator = MWCityLocator()
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedRegion: MWHospital.Region? = nil
    @State private var selectedLevel: MWHospital.Level? = nil
    @State private var selectedCity: String? = nil

    @State private var filteredGroups: [(region: MWHospital.Region, items: [MWHospital])] = mwAllGrouped
    @State private var availableCities: [String] = mwAllCitiesByRegion[nil]!
    @State private var debounceTask: AnyCancellable? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredGroups, id: \.region) { group in
                    Section {
                        ForEach(group.items) { h in
                            MWHospitalRow(h: h, openURL: openURL)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                            Text("\(group.region.rawValue)（\(group.items.count) 家）")
                        }
                    }
                }
                if filteredGroups.isEmpty {
                    Section {
                        Label("沒有符合的醫院", systemImage: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("後送醫院（\(MWHospitalDirectory.all.count) 家）")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                filterHeader
            }
            .onChange(of: query) { q in
                debounceTask?.cancel()
                debounceTask = Just(q)
                    .delay(for: .milliseconds(250), scheduler: RunLoop.main)
                    .sink { val in
                        debouncedQuery = val
                        recompute()
                    }
            }
            .onChange(of: selectedRegion) { _ in
                availableCities = mwAllCitiesByRegion[selectedRegion] ?? []
                recompute()
            }
            .onChange(of: selectedCity) { _ in recompute() }
            .onChange(of: selectedLevel) { _ in recompute() }
            .onChange(of: locator.detectedCity) { city in
                guard let city else { return }
                selectedCity = city
                selectedRegion = nil
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 篩選 Header

    private var filterHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋縣市 / 醫院名稱", text: $query)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 22)
                Button { locator.requestLocation() } label: {
                    if locator.isLocating {
                        ProgressView().scaleEffect(0.9).frame(width: 24, height: 24)
                    } else {
                        Image(systemName: locator.detectedCity != nil && locator.detectedCity == selectedCity
                              ? "location.fill" : "location")
                            .foregroundStyle(MWTheme.green)
                    }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                if selectedCity != nil {
                    Button { selectedCity = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))

            if let err = locator.errorMsg {
                Text(err).font(.caption2).foregroundStyle(.red)
                    .padding(.horizontal, 16)
            } else if let city = locator.detectedCity {
                Label("已定位：\(city)", systemImage: "location.fill")
                    .font(.caption2).foregroundStyle(MWTheme.green)
                    .padding(.horizontal, 16)
            }

            Divider()

            chipRow(title: "全部區域", accent: MWTheme.green, isSelected: selectedRegion == nil, action: {
                selectedRegion = nil; selectedCity = nil
            }, items: mwAllRegions, selected: selectedRegion, itemLabel: \.rawValue, itemAction: { r in
                selectedRegion = r; selectedCity = nil
            })

            chipRow(title: "全部縣市", accent: MWTheme.cyan, isSelected: selectedCity == nil, action: {
                selectedCity = nil
            }, items: availableCities, selected: selectedCity, itemLabel: { $0 }, itemAction: { c in
                selectedCity = c
            })

            chipRow(title: "全部層級", accent: MWTheme.violet, isSelected: selectedLevel == nil, action: {
                selectedLevel = nil
            }, items: mwAllLevels, selected: selectedLevel, itemLabel: \.rawValue, itemAction: { lv in
                selectedLevel = lv
            })

            Divider()
        }
        .background(Color(.systemBackground))
    }

    // 泛型 chip row
    private func chipRow<T: Hashable>(
        title: String, accent: Color, isSelected: Bool, action: @escaping () -> Void,
        items: [T], selected: T?, itemLabel: @escaping (T) -> String, itemAction: @escaping (T) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                mwChip(label: title, accent: accent, sel: isSelected, action: action)
                ForEach(items, id: \.self) { item in
                    mwChip(label: itemLabel(item), accent: accent, sel: selected == item) {
                        itemAction(item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func mwChip(label: String, accent: Color, sel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(sel ? .black : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(sel ? accent : accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 過濾

    private func recompute() {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespaces)
        let result = mwAllGrouped.compactMap { group -> (region: MWHospital.Region, items: [MWHospital])? in
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
}

// MARK: - Row

private struct MWHospitalRow: View {
    let h: MWHospital
    let openURL: OpenURLAction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: h.level.icon)
                    .foregroundStyle(h.level.color)
                    .frame(width: 22)
                Text(h.name).font(.headline)
                Spacer(minLength: 0)
                Text(h.level.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(h.level.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(h.level.color.opacity(0.14))
                    .clipShape(Capsule())
            }
            if !h.address.isEmpty {
                Text(h.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                if h.totalBeds > 0 {
                    Label("\(h.totalBeds)床", systemImage: "bed.double.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if h.icuBeds > 0 {
                    Label("ICU \(h.icuBeds)", systemImage: "waveform.path.ecg")
                        .font(.caption).foregroundStyle(.red.opacity(0.8))
                }
                if h.erBeds > 0 {
                    Label("急觀\(h.erBeds)", systemImage: "staroflife.fill")
                        .font(.caption).foregroundStyle(.orange.opacity(0.9))
                }
            }
            if !h.phone.isEmpty {
                Button {
                    if let url = URL(string: "tel://\(h.phone)") {
                        openURL(url)
                    }
                } label: {
                    Label(h.phone, systemImage: "phone.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(MWTheme.cyan)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
    }
}
