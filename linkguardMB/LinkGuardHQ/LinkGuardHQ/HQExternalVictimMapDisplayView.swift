import SwiftUI
import MapKit
import CoreLocation

struct HQExternalVictimMapDisplayView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject private var backendBridge: HQBackendBridge
    @ObservedObject private var commandServer: HQCommandServer
    @StateObject private var locationProvider = HQExternalLocationProvider()
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(vm: HQViewModel) {
        self.vm = vm
        self._backendBridge = ObservedObject(wrappedValue: vm.backendBridge)
        self._commandServer = ObservedObject(wrappedValue: vm.server)
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = max(14, min(24, proxy.size.width * 0.014))
            let listWidth = max(420, min(640, proxy.size.width * 0.34))

            HStack(spacing: spacing) {
                victimListPanel
                    .frame(width: listWidth)
                mapPanel
            }
            .padding(spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NV.bg.ignoresSafeArea())
        }
    }

    private var victimListPanel: some View {
        externalPanel(title: L("受困者清單"), icon: "person.fill.questionmark", accent: NV.warning) {
            VStack(alignment: .leading, spacing: 14) {
                victimStats

                if victimRecords.isEmpty {
                    emptyState(icon: "person.crop.circle.badge.questionmark", title: L("目前無受困者資料"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(victimRecords) { record in
                                ExternalVictimListRow(record: record, hasCoordinate: coordinate(for: record) != nil)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
        }
    }

    private var victimStats: some View {
        HStack(spacing: 10) {
            statBadge(title: L("總計"), value: victimRecords.count, color: NV.warning)
            statBadge(title: "SOS", value: victimRecords.filter(\.isSOS).count, color: NV.danger)
            statBadge(title: L("上線"), value: victimRecords.filter(\.isOnline).count, color: NV.green)
            statBadge(title: "GPS", value: victimRecords.filter { coordinate(for: $0) != nil }.count, color: NV.info)
        }
    }

    private var mapPanel: some View {
        externalPanel(title: L("地圖"), icon: "map.fill", accent: NV.green) {
            ZStack(alignment: .bottomLeading) {
                Map(position: $cameraPosition) {
                    ForEach(mapPins) { pin in
                        Annotation(pin.title, coordinate: pin.coordinate) {
                            ExternalMapPinView(pin: pin)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onAppear {
                    locationProvider.start()
                    fitMapToPins()
                }
                .onChange(of: mapCameraKey) { _, _ in fitMapToPins() }

                if mapPins.isEmpty {
                    emptyState(icon: locationProvider.emptyStateIcon, title: locationProvider.statusText)
                        .background(NV.bg.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        mapLegend
                        locationStatusBadge
                    }
                    .padding(14)
                }
            }
        }
    }

    private var mapLegend: some View {
        HStack(spacing: 10) {
            legendItem(title: L("指揮中心"), icon: "location.circle.fill", color: NV.command)
            legendItem(title: L("搜救人員"), icon: "figure.walk.motion", color: NV.team)
            legendItem(title: L("受困者"), icon: "person.fill.questionmark", color: NV.warning)
            legendItem(title: L("照片"), icon: "photo.fill", color: NV.info)
            legendItem(title: "LoRa", icon: "antenna.radiowaves.left.and.right", color: NV.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var locationStatusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: locationProvider.isLocated ? "location.fill" : locationProvider.emptyStateIcon)
                .foregroundColor(locationProvider.isLocated ? NV.command : NV.warning)
            Text(locationProvider.statusText)
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func externalPanel<Content: View>(title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 22)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NV.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func statBadge(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundColor(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func legendItem(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .foregroundColor(.white.opacity(0.88))
        }
        .font(.caption.weight(.semibold))
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.65))
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var victimRecords: [HQVictimRecord] {
        vm.allVictimRecords.sorted { left, right in
            if left.isSOS != right.isSOS { return left.isSOS && !right.isSOS }
            if left.priority != right.priority { return left.priority > right.priority }
            if left.isOnline != right.isOnline { return left.isOnline && !right.isOnline }
            return left.id.localizedStandardCompare(right.id) == .orderedAscending
        }
    }

    private var mapPins: [ExternalMapPin] {
        hqLocationPin + personnelPins + victimPins + photoPins + loraPins
    }

    private var hqLocationPin: [ExternalMapPin] {
        guard let location = locationProvider.location else { return [] }
        return [
            ExternalMapPin(
                id: "hq-current-location",
                title: L("指揮中心"),
                subtitle: locationProvider.accuracyText,
                coordinate: location.coordinate,
                color: NV.command,
                icon: "location.circle.fill"
            )
        ]
    }

    private var victimPins: [ExternalMapPin] {
        victimRecords.compactMap { record in
            guard let coordinate = coordinate(for: record) else { return nil }
            return ExternalMapPin(
                id: "victim-\(record.id)",
                title: displayName(for: record),
                subtitle: record.location.isEmpty ? record.sourceDeviceID : record.location,
                coordinate: coordinate,
                color: record.isSOS ? NV.danger : record.priority.color,
                icon: record.isSOS ? "sos.circle.fill" : "person.fill.questionmark"
            )
        }
    }

    private var personnelPins: [ExternalMapPin] {
        commandServer.deviceLocations.sorted(by: { $0.key < $1.key }).compactMap { deviceID, data in
            guard let latitude = doubleValue(data["lat"]),
                  let longitude = doubleValue(data["lon"]),
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

            let name = stringValue(data["name"])
            let role = stringValue(data["role"])
            return ExternalMapPin(
                id: "personnel-\(deviceID)",
                title: name.isEmpty ? deviceID : name,
                subtitle: personnelSubtitle(deviceID: deviceID, role: role, data: data),
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                color: NV.team,
                icon: "figure.walk.motion"
            )
        }
    }

    private var photoPins: [ExternalMapPin] {
        vm.photoAlerts.prefix(30).enumerated().compactMap { index, photo in
            let data = photo["data"] as? [String: Any] ?? photo
            guard let latitude = doubleValue(data["lat"]),
                  let longitude = doubleValue(data["lon"]),
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

            let photoID = stringValue(data["photo_id"])
            let caption = stringValue(data["caption"])
            let sender = stringValue(data["sender_name"])
            return ExternalMapPin(
                id: "photo-\(photoID.isEmpty ? "\(index)" : photoID)",
                title: caption.isEmpty ? L("照片回報") : caption,
                subtitle: sender.isEmpty ? L("未知來源") : sender,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                color: NV.info,
                icon: "photo.fill"
            )
        }
    }

    private var loraPins: [ExternalMapPin] {
        backendBridge.loraNodes.compactMap { node in
            guard let latitude = node.lat,
                  let longitude = node.lon,
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

            return ExternalMapPin(
                id: "lora-\(node.nodeId)",
                title: node.nodeId,
                subtitle: "RSSI \(node.rssi) / SNR \(String(format: "%.1f", node.snr))",
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                color: NV.green,
                icon: "antenna.radiowaves.left.and.right"
            )
        }
    }

    private var mapCameraKey: String {
        mapPins.map { pin in
            "\(pin.id):\(String(format: "%.5f", pin.coordinate.latitude)):\(String(format: "%.5f", pin.coordinate.longitude))"
        }
        .joined(separator: "|")
    }

    private func coordinate(for record: HQVictimRecord) -> CLLocationCoordinate2D? {
        guard let report = vm.patientReports.first(where: { $0.patientId == record.id }),
              let latitude = report.gpsLat,
              let longitude = report.gpsLon,
              isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func fitMapToPins() {
        guard !mapPins.isEmpty else {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6978, longitude: 120.9605),
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            ))
            return
        }

        let latitudes = mapPins.map(\.coordinate.latitude)
        let longitudes = mapPins.map(\.coordinate.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.8, 0.01),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.8, 0.01)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func displayName(for record: HQVictimRecord) -> String {
        record.patientName.isEmpty ? record.id : "\(record.patientName) / \(record.id)"
    }

    private func personnelSubtitle(deviceID: String, role: String, data: [String: Any]) -> String {
        var parts: [String] = []
        if !role.isEmpty { parts.append(role) }
        if let accuracy = doubleValue(data["accuracy"]), accuracy >= 0 {
            parts.append(String(format: L("精度 %.0f m"), accuracy))
        }
        if let timestamp = data["timestamp"] as? Date {
            let age = max(0, Int(Date().timeIntervalSince(timestamp)))
            parts.append(L("%lld 秒前", age))
        }
        if parts.isEmpty { parts.append(deviceID) }
        return parts.joined(separator: " / ")
    }

    private func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 && !(latitude == 0 && longitude == 0)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value { return "\(value)" }
        return ""
    }
}

private final class HQExternalLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published private var authorizationStatus: CLAuthorizationStatus
    @Published private var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    var isLocated: Bool {
        location != nil
    }

    var statusText: String {
        if let lastError { return lastError }
        switch authorizationStatus {
        case .notDetermined:
            return L("等待定位授權")
        case .restricted, .denied:
            return L("定位權限未開啟")
        case .authorizedAlways, .authorizedWhenInUse:
            if location != nil { return L("指揮中心定位已更新") }
            return L("定位中...")
        @unknown default:
            return L("定位狀態未知")
        }
    }

    var emptyStateIcon: String {
        switch authorizationStatus {
        case .restricted, .denied:
            return "location.slash"
        default:
            return "location.magnifyingglass"
        }
    }

    var accuracyText: String {
        guard let accuracy = location?.horizontalAccuracy, accuracy >= 0 else {
            return L("目前位置")
        }
        return L("精度 %.0f m", accuracy)
    }

    func start() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            lastError = nil
            manager.startUpdatingLocation()
        case .restricted, .denied:
            manager.stopUpdatingLocation()
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            self.start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastError = nil
            self?.location = latestLocation
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
        }
    }
}

private struct ExternalVictimListRow: View {
    let record: HQVictimRecord
    let hasCoordinate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 5) {
                    Circle()
                        .fill(record.priority.color)
                        .frame(width: 11, height: 11)
                    Circle()
                        .fill(record.isOnline ? NV.green : .gray)
                        .frame(width: 8, height: 8)
                }
                .padding(.top, 5)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(record.patientName.isEmpty ? record.id : record.patientName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        if !record.patientName.isEmpty {
                            Text(record.id)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if record.isSOS {
                            Text("SOS")
                                .font(.caption2.bold())
                                .foregroundColor(NV.danger)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NV.danger.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        rowChip(record.priority.label, icon: record.priority.icon, color: record.priority.color)
                        rowChip(record.status.label, icon: record.status.icon, color: record.status.color)
                        rowChip(hasCoordinate ? "GPS" : "--", icon: hasCoordinate ? "mappin.circle.fill" : "mappin.slash", color: hasCoordinate ? NV.info : .gray)
                    }
                }
            }

            HStack(spacing: 12) {
                metricText(icon: "heart.fill", text: record.heartRate > 0 ? "\(record.heartRate) bpm" : "--", color: NV.danger)
                metricText(icon: "battery.75", text: "\(record.battery)%", color: record.battery < 30 ? NV.warning : NV.green)
                metricText(icon: "antenna.radiowaves.left.and.right", text: String(format: "%.0f", record.rssi), color: NV.info)
            }

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .foregroundColor(.secondary)
                Text(locationText)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowAccent.opacity(0.28), lineWidth: 1)
        )
    }

    private var rowAccent: Color {
        record.isSOS ? NV.danger : record.priority.color
    }

    private var locationText: String {
        if !record.location.isEmpty { return record.location }
        if !record.sourceDeptCode.isEmpty { return "\(record.sourceDeptCode) / \(record.sourceDeviceID)" }
        return record.sourceDeviceID
    }

    private func rowChip(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }

    private func metricText(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

private struct ExternalMapPinView: View {
    let pin: ExternalMapPin

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(pin.color)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                Image(systemName: pin.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(spacing: 1) {
                Text(pin.title)
                    .font(.caption2.bold())
                    .lineLimit(1)
                if !pin.subtitle.isEmpty {
                    Text(pin.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: 130)
            .background(.black.opacity(0.72))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct ExternalMapPin: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let icon: String
}