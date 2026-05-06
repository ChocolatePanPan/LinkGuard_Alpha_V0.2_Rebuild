import SwiftUI
import CoreLocation
import MapKit
#if os(macOS)
import AppKit
#endif

// MARK: - GPS City Locator

private final class HQCityLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var detectedCity: String? = nil
    @Published var isLocating = false
    @Published var errorMsg: String? = nil

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        errorMsg = nil
        isLocating = true
        #if os(macOS)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized: manager.requestLocation()
        default:
            isLocating = false
            errorMsg = "位置權限未開放"
        }
        #else
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default:
            isLocating = false
            errorMsg = "位置權限未開放"
        }
        #endif
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if os(macOS)
        if manager.authorizationStatus == .authorized { manager.requestLocation() }
        #else
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { isLocating = false; return }
        reverseGeocodeCity(from: loc)
    }

    private func reverseGeocodeCity(from location: CLLocation) {
        if #available(macOS 26.0, *) {
            reverseGeocodeCityWithMapKit(from: location)
        } else {
            reverseGeocodeCityWithCoreLocation(from: location)
        }
    }

    @available(macOS 26.0, *)
    private func reverseGeocodeCityWithMapKit(from location: CLLocation) {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            DispatchQueue.main.async { [weak self] in
                self?.isLocating = false
                self?.errorMsg = "定位失敗"
            }
            return
        }

        request.getMapItems { [weak self] mapItems, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self?.isLocating = false
                    self?.errorMsg = "定位失敗"
                    return
                }
                let item = mapItems?.first
                let addressRepresentations = item?.addressRepresentations
                let address = item?.address
                self?.applyReverseGeocodedCity(candidates: [
                    addressRepresentations?.cityName,
                    addressRepresentations?.cityWithContext,
                    addressRepresentations?.cityWithContext(.full),
                    address?.shortAddress,
                    address?.fullAddress
                ].compactMap { $0 })
            }
        }
    }

    private func reverseGeocodeCityWithCoreLocation(from location: CLLocation) {
        if #unavailable(macOS 26.0) {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                DispatchQueue.main.async {
                    let placemark = placemarks?.first
                    self?.applyReverseGeocodedCity(candidates: [
                        placemark?.subAdministrativeArea,
                        placemark?.administrativeArea
                    ].compactMap { $0 })
                }
            }
        }
    }

    private func applyReverseGeocodedCity(candidates: [String]) {
        isLocating = false
        let allCities = Array(Set(HQHospitalDirectory.all.map(\.city)))
        for raw in candidates {
            let normalized = raw.replacingOccurrences(of: "台", with: "臺")
            if let city = allCities.first(where: { $0.hasPrefix(normalized) || normalized.hasPrefix($0) })
                ?? allCities.first(where: { $0.contains(normalized) || normalized.contains($0) }) {
                detectedCity = city
                return
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLocating = false
            self.errorMsg = "定位失敗"
        }
    }
}

// MARK: - View

/// 全臺急救責任醫院目錄（HQ Mac 版）
struct HQHospitalDirectoryView: View {
    @ObservedObject var vm: HQViewModel
    @StateObject private var locator = HQCityLocator()
    @State private var query = ""
    @State private var selectedRegion: HQHospital.Region? = nil
    @State private var selectedLevel: HQHospital.Level? = nil
    @State private var selectedCity: String? = nil
    @State private var visibleCount = 60

    private let pageSize = 60

    // 依目前選定區域動態產生縣市列表
    private var availableCities: [String] {
        let base: [HQHospital]
        if let r = selectedRegion {
            base = HQHospitalDirectory.all.filter { $0.region == r }
        } else {
            base = HQHospitalDirectory.all
        }
        return Array(Set(base.map(\.city))).sorted()
    }

    private var filtered: [(region: HQHospital.Region, items: [HQHospital])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return HQHospitalDirectory.grouped().compactMap { group in
            if let r = selectedRegion, r != group.region { return nil }
            let items = group.items.filter { h in
                if let city = selectedCity, h.city != city { return false }
                if let lv = selectedLevel, lv != h.level { return false }
                guard !trimmed.isEmpty else { return true }
                return h.name.localizedCaseInsensitiveContains(trimmed)
                    || h.city.localizedCaseInsensitiveContains(trimmed)
                    || h.purpose.localizedCaseInsensitiveContains(trimmed)
            }
            return items.isEmpty ? nil : (group.region, items)
        }
    }

    private var totalCount: Int { filtered.reduce(0) { $0 + $1.items.count } }

    private var visibleFiltered: [(region: HQHospital.Region, items: [HQHospital])] {
        var remaining = visibleCount
        var result: [(region: HQHospital.Region, items: [HQHospital])] = []
        for group in filtered where remaining > 0 {
            let visibleItems = Array(group.items.prefix(remaining))
            if !visibleItems.isEmpty {
                result.append((group.region, visibleItems))
                remaining -= visibleItems.count
            }
        }
        return result
    }

    // 當 GPS 偵測到縣市時自動套用
    private func applyDetectedCity(_ city: String?) {
        guard let city else { return }
        selectedCity = city
        // 自動切換到對應區域（取消單獨限制，讓縣市篩選接手）
        selectedRegion = nil
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("後送醫院"),
                           subtitle: "全臺有急診醫院 \(HQHospitalDirectory.all.count) 家，依縣市分組",
                           icon: "cross.fill",
                           accent: NV.info) {
                Text(L("%lld 家", HQHospitalDirectory.all.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // 搜尋 + 篩選
            VStack(spacing: 8) {
                // 搜尋列 + GPS 按鈕
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(L("搜尋縣市 / 醫院名稱 / 用途"), text: $query)
                        .textFieldStyle(.plain)
                    Spacer()
                    // GPS 定位按鈕
                    Button {
                        locator.requestLocation()
                    } label: {
                        if locator.isLocating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: selectedCity != nil && locator.detectedCity == selectedCity
                                  ? "location.fill" : "location")
                                .foregroundColor(NV.info)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(locator.errorMsg ?? "GPS 自動定位縣市")

                    if selectedCity != nil {
                        Button {
                            selectedCity = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除縣市篩選")
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NV.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(NV.info.opacity(0.3), lineWidth: NV.strokeWidth))
                )

                // 區域篩選
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil as HQHospital.Region?, label: L("全部區域"), accent: NV.info,
                                   isSelected: selectedRegion == nil) {
                            selectedRegion = nil
                            selectedCity = nil
                            resetVisibleCount()
                        }
                        ForEach(HQHospital.Region.allCases, id: \.self) { r in
                            filterChip(r, label: L(r.rawValue), accent: NV.info,
                                       isSelected: selectedRegion == r) {
                                selectedRegion = r
                                selectedCity = nil
                                resetVisibleCount()
                            }
                        }
                    }
                }

                // 縣市篩選（隨區域動態變化）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil as String?, label: "全部縣市", accent: NV.info.opacity(0.8),
                                   isSelected: selectedCity == nil) {
                            selectedCity = nil
                            resetVisibleCount()
                        }
                        ForEach(availableCities, id: \.self) { city in
                            filterChip(city, label: city, accent: NV.info.opacity(0.8),
                                       isSelected: selectedCity == city) {
                                selectedCity = city
                                resetVisibleCount()
                            }
                        }
                    }
                }

                // 層級篩選
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil as HQHospital.Level?, label: L("全部層級"), accent: NV.green,
                                   isSelected: selectedLevel == nil) {
                            selectedLevel = nil
                            resetVisibleCount()
                        }
                        ForEach(HQHospital.Level.allCases, id: \.self) { lv in
                            filterChip(lv, label: L(lv.rawValue), accent: levelColor(lv),
                                       isSelected: selectedLevel == lv) {
                                selectedLevel = lv
                                resetVisibleCount()
                            }
                        }
                    }
                }

                // GPS 狀態提示
                if let err = locator.errorMsg {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(NV.danger)
                } else if let city = locator.detectedCity {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").foregroundColor(NV.info)
                        Text("已定位至：\(city)")
                            .font(.caption)
                            .foregroundColor(NV.info)
                    }
                }
            }
            .hqPanelChrome(accent: NV.info)
            .onChange(of: locator.detectedCity) { _, city in
                applyDetectedCity(city)
            }
            .onChange(of: query) { _, _ in
                resetVisibleCount()
            }

            if filtered.isEmpty {
                HQEmptyStateView(icon: "magnifyingglass", title: L("沒有符合的醫院"))
                    .hqPanelChrome(accent: NV.info)
            } else {
                LazyVStack(alignment: .leading, spacing: NV.panelSpacing) {
                    ForEach(visibleFiltered, id: \.region) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse").foregroundColor(NV.info)
                                Text(L(group.region.rawValue)).font(.headline)
                                Text(L("%lld 家", group.items.count))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            LazyVStack(spacing: 6) {
                                ForEach(group.items) { h in hospitalRow(h) }
                            }
                        }
                        .hqPanelChrome(accent: NV.info)
                    }
                    if visibleCount < totalCount {
                        Button {
                            visibleCount += pageSize
                        } label: {
                            Label(L("載入更多"), systemImage: "chevron.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func hospitalRow(_ h: HQHospital) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: h.level.icon)
                    .foregroundColor(levelColor(h.level))
                    .font(.title3)
                Text(h.city)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(h.name).font(.subheadline.bold())
                    levelBadge(h.level)
                }
                if !h.address.isEmpty {
                    Text(h.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                // 病床數（鄉鎮市區合計）
                HStack(spacing: 10) {
                    if h.totalBeds > 0 {
                        Label("\(h.totalBeds) 床", systemImage: "bed.double.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if h.icuBeds > 0 {
                        Label("ICU \(h.icuBeds)", systemImage: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundColor(NV.danger.opacity(0.9))
                    }
                    if h.erBeds > 0 {
                        Label("急觀 \(h.erBeds)", systemImage: "staroflife.fill")
                            .font(.caption2)
                            .foregroundColor(NV.warning.opacity(0.9))
                    }
                }
                if !h.purpose.isEmpty {
                    Text(h.purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if !h.phone.isEmpty {
                Button { callOrCopy(phone: h.phone) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                        Text(h.phone).monospacedDigit()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NV.info))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(NV.surface.opacity(0.6)))
    }

    // MARK: - Helpers

    private func levelColor(_ lv: HQHospital.Level) -> Color {
        switch lv {
        case .heavy:    return NV.danger
        case .moderate: return NV.warning
        case .children: return NV.command
        case .unknown:  return .secondary
        }
    }

    private func levelBadge(_ lv: HQHospital.Level) -> some View {
        Text(L(lv.rawValue))
            .font(.caption2.bold())
            .foregroundColor(levelColor(lv))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(levelColor(lv).opacity(0.12))
            .clipShape(Capsule())
    }

    private func filterChip<T>(_ value: T?,
                                label: String,
                                accent: Color,
                                isSelected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? accent : accent.opacity(0.12)))
                .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: NV.strokeWidth))
        }
        .buttonStyle(.plain)
    }

    private func callOrCopy(phone: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phone, forType: .string)
        #else
        if let url = URL(string: "tel://\(phone)") { UIApplication.shared.open(url) }
        #endif
    }

    private func resetVisibleCount() {
        visibleCount = pageSize
    }
}
