import SwiftUI
import MapKit
import CoreLocation

struct HQZoneMapView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject private var commandServer: HQCommandServer
    @ObservedObject private var backendBridge: HQBackendBridge
    @State private var showAddZone = false
    @State private var editingZone: RescueZone?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedTrackingLayer: HQTrackingLayer = .all
    @State private var selectedTrackingPinID: String?

    init(vm: HQViewModel) {
        self.vm = vm
        self._commandServer = ObservedObject(wrappedValue: vm.server)
        self._backendBridge = ObservedObject(wrappedValue: vm.backendBridge)
    }

    private var zones: [RescueZone] {
        vm.disasterSite?.zones ?? []
    }

    private var allTrackingPins: [HQTrackingPin] {
        sosPins + fieldUnitPins + patientPins + photoPins + loraPins
    }

    private var filteredTrackingPins: [HQTrackingPin] {
        allTrackingPins.filter { pin in
            selectedTrackingLayer == .all || pin.layer == selectedTrackingLayer
        }
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("分區地圖"), icon: "map.fill", accent: NV.green)

            trackingMapSection

            // 統計條
            statsBar

            // 分區卡片網格
            if zones.isEmpty {
                emptyState
                    .hqPanelChrome(accent: NV.green)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: NV.panelSpacing)], spacing: NV.panelSpacing) {
                    ForEach(zones) { zone in
                        ZoneCard(zone: zone, personnel: matchedPersonnel(for: zone)) {
                            editingZone = zone
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                showAddZone = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? NV.green : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("新增搜救分區"))
        }
        .sheet(isPresented: $showAddZone) {
            AddZoneSheet(vm: vm)
        }
        .sheet(item: $editingZone) { zone in
            EditZoneSheet(vm: vm, zone: zone)
        }
        .onAppear { fitMapToPins() }
        .onChange(of: trackingCameraKey) { _, _ in fitMapToPins() }
        .onChange(of: selectedTrackingLayer) { _, _ in fitMapToPins() }
    }

    private var trackingMapSection: some View {
        HQPanel(title: L("即時地圖追蹤"), icon: "location.viewfinder", accent: NV.green) {
            VStack(alignment: .leading, spacing: 14) {
                trackingToolbar

                HStack(alignment: .top, spacing: 14) {
                    trackingMap
                    trackingList
                        .frame(width: 320)
                }
                .frame(minHeight: 420)
            }
        }
    }

    private var trackingToolbar: some View {
        HStack(spacing: 12) {
            Picker(L("追蹤圖層"), selection: $selectedTrackingLayer) {
                ForEach(HQTrackingLayer.allCases) { layer in
                    Label(layer.label, systemImage: layer.icon).tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)

            Spacer()

            Button {
                selectedTrackingPinID = nil
                fitMapToPins()
            } label: {
                Label(L("縮放至全部"), systemImage: "scope")
            }
            .buttonStyle(.bordered)
            .disabled(filteredTrackingPins.isEmpty)
        }
    }

    private var trackingMap: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $cameraPosition) {
                ForEach(filteredTrackingPins) { pin in
                    Annotation(pin.title, coordinate: pin.coordinate) {
                        HQTrackingPinView(pin: pin, isSelected: selectedTrackingPinID == pin.id)
                            .onTapGesture { focus(on: pin) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous)
                    .stroke(NV.green.opacity(0.22), lineWidth: NV.strokeWidth)
            )

            if filteredTrackingPins.isEmpty {
                HQEmptyStateView(
                    icon: selectedTrackingLayer.emptyIcon,
                    title: selectedTrackingLayer.emptyTitle,
                    subtitle: L("前線裝置回報 GPS、照片或傷員座標後會自動出現在這裡。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NV.bg.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
            } else {
                trackingLegend
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var trackingLegend: some View {
        HStack(spacing: 10) {
            ForEach(HQTrackingLayer.legendLayers) { layer in
                HStack(spacing: 5) {
                    Image(systemName: layer.icon)
                        .foregroundColor(layer.color)
                    Text(layer.shortLabel)
                        .foregroundColor(.white.opacity(0.9))
                }
                .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
    }

    private var trackingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("追蹤點位"), systemImage: selectedTrackingLayer.icon)
                    .font(.headline)
                Spacer()
                Text("\(filteredTrackingPins.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(selectedTrackingLayer.color)
            }

            if filteredTrackingPins.isEmpty {
                Text(selectedTrackingLayer.emptyTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .hqThemedSurfaceBackground()
                    .cornerRadius(NV.cardRadius)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredTrackingPins.sorted(by: trackingSort)) { pin in
                            HQTrackingListRow(pin: pin, isSelected: selectedTrackingPinID == pin.id) {
                                focus(on: pin)
                            }
                        }
                    }
                }
                .frame(maxHeight: 390)
            }
        }
        .padding(12)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }

    // MARK: - 統計條

    private var statsBar: some View {
        HStack(spacing: 16) {
            ZoneStatLabel(icon: "map.fill", label: L("總分區"), value: "\(zones.count)", color: NV.info)
            ZoneStatLabel(icon: "location.fill", label: L("GPS 點位"), value: "\(allTrackingPins.count)", color: NV.green)
            ZoneStatLabel(icon: "figure.walk.motion", label: L("前線追蹤"), value: "\(fieldUnitPins.count)", color: NV.team)
            ZoneStatLabel(icon: "cross.case.fill", label: L("傷員座標"), value: "\(patientPins.count)", color: NV.danger)
            ZoneStatLabel(icon: "antenna.radiowaves.left.and.right", label: "LoRa", value: "\(loraPins.count)", color: NV.green)
            ZoneStatLabel(icon: "magnifyingglass", label: L("搜救中"),
                          value: "\(zones.filter { $0.status == .active }.count)", color: NV.green)
            ZoneStatLabel(icon: "checkmark.circle.fill", label: L("已清除"),
                          value: "\(zones.filter { $0.status == .cleared }.count)", color: NV.info)
            ZoneStatLabel(icon: "exclamationmark.triangle.fill", label: L("危險區"),
                          value: "\(zones.filter { $0.status == .dangerous }.count)", color: NV.danger)
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        HQEmptyStateView(
            icon: "map",
            title: L("尚未定義搜救分區"),
            subtitle: L("點按左下角 + 新增分區，或在「災害狀態」頁面中新增")
        )
    }

    private func matchedPersonnel(for zone: RescueZone) -> [PersonnelAssignment] {
        vm.personnelAssignments.filter { $0.assignedZone == zone.name }
    }

    private var fieldUnitPins: [HQTrackingPin] {
        commandServer.deviceLocations.sorted(by: { $0.key < $1.key }).compactMap { deviceID, data in
            guard let latitude = doubleValue(data["lat"]),
                  let longitude = doubleValue(data["lon"]),
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

            let name = stringValue(data["name"])
            let role = stringValue(data["role"])
            let timestamp = dateValue(data["timestamp"])
            let accuracy = doubleValue(data["accuracy"])
            let unit = commandServer.fieldUnits.first { unit in
                unit.deviceID == deviceID || unit.deviceID == name
            }
            let subtitle = compactParts([
                role,
                unit.map { L("電量 %lld%%", $0.battery) },
                accuracy.map { $0 >= 0 ? String(format: L("精度 %.0f m"), $0) : "" },
                timestamp.map(relativeAge)
            ])

            return HQTrackingPin(
                id: "field-\(deviceID)",
                title: name.isEmpty ? deviceID : name,
                subtitle: subtitle.isEmpty ? deviceID : subtitle,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                layer: .field,
                color: unit?.isOnline == false ? .gray : HQTrackingLayer.field.color,
                icon: HQTrackingLayer.field.icon,
                timestamp: timestamp ?? Date.distantPast
            )
        }
    }

    private var patientPins: [HQTrackingPin] {
        vm.patientReports.compactMap { report in
            guard let latitude = report.gpsLat,
                  let longitude = report.gpsLon,
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            let priority = vm.victimPriorities[report.patientId] ?? .unset
            let title = report.name.isEmpty ? report.patientId : report.name
            let subtitle = compactParts([
                report.location,
                priority == .unset ? "" : priority.label,
                relativeAge(Date(timeIntervalSince1970: report.receivedAt))
            ])
            return HQTrackingPin(
                id: "patient-\(report.patientId)",
                title: title,
                subtitle: subtitle,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                layer: .patient,
                color: priority == .unset ? HQTrackingLayer.patient.color : priority.color,
                icon: HQTrackingLayer.patient.icon,
                timestamp: Date(timeIntervalSince1970: report.receivedAt)
            )
        }
    }

    private var photoPins: [HQTrackingPin] {
        vm.photoAlerts.prefix(80).enumerated().compactMap { index, photo in
            let data = photo["data"] as? [String: Any] ?? photo
            guard let latitude = doubleValue(data["lat"]),
                  let longitude = doubleValue(data["lon"]),
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

            let photoID = stringValue(data["photo_id"])
            let caption = stringValue(data["caption"])
            let sender = stringValue(data["sender_name"])
            let locationDesc = stringValue(data["location_desc"])
            let timestamp = dateValue(data["timestamp"]) ?? Date()
            return HQTrackingPin(
                id: "photo-\(photoID.isEmpty ? "\(index)" : photoID)",
                title: caption.isEmpty ? L("照片回報") : caption,
                subtitle: compactParts([sender, locationDesc, relativeAge(timestamp)]),
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                layer: .photo,
                color: HQTrackingLayer.photo.color,
                icon: HQTrackingLayer.photo.icon,
                timestamp: timestamp
            )
        }
    }

    private var sosPins: [HQTrackingPin] {
        vm.activeSOSAlerts.compactMap { alert in
            guard isValidCoordinate(latitude: alert.lat, longitude: alert.lon) else { return nil }
            return HQTrackingPin(
                id: "sos-\(alert.id)",
                title: alert.senderName.isEmpty ? alert.deviceID : alert.senderName,
                subtitle: compactParts(["SOS", alert.deviceID, relativeAge(alert.timestamp)]),
                coordinate: CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lon),
                layer: .sos,
                color: HQTrackingLayer.sos.color,
                icon: HQTrackingLayer.sos.icon,
                timestamp: alert.timestamp
            )
        }
    }

    private var loraPins: [HQTrackingPin] {
        backendBridge.loraNodes.compactMap { node in
            guard let latitude = node.lat,
                  let longitude = node.lon,
                  isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return HQTrackingPin(
                id: "lora-\(node.nodeId)",
                title: node.nodeId,
                subtitle: compactParts([
                    L("電量 %lld%%", node.battery),
                    "RSSI \(node.rssi)",
                    String(format: "SNR %.1f", node.snr)
                ]),
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                layer: .lora,
                color: HQTrackingLayer.lora.color,
                icon: HQTrackingLayer.lora.icon,
                timestamp: Date()
            )
        }
    }

    private var trackingCameraKey: String {
        filteredTrackingPins.map { pin in
            "\(pin.id):\(String(format: "%.5f", pin.coordinate.latitude)):\(String(format: "%.5f", pin.coordinate.longitude))"
        }
        .joined(separator: "|")
    }

    private func focus(on pin: HQTrackingPin) {
        selectedTrackingPinID = pin.id
        cameraPosition = .region(MKCoordinateRegion(
            center: pin.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    private func fitMapToPins() {
        selectedTrackingPinID = selectedTrackingPinID.flatMap { selectedID in
            filteredTrackingPins.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        guard selectedTrackingPinID == nil else { return }
        guard !filteredTrackingPins.isEmpty else {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6978, longitude: 120.9605),
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            ))
            return
        }

        let latitudes = filteredTrackingPins.map(\.coordinate.latitude)
        let longitudes = filteredTrackingPins.map(\.coordinate.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else { return }

        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.8, 0.01),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.8, 0.01)
            )
        ))
    }

    private func trackingSort(_ left: HQTrackingPin, _ right: HQTrackingPin) -> Bool {
        if left.layer.sortOrder != right.layer.sortOrder { return left.layer.sortOrder < right.layer.sortOrder }
        if left.timestamp != right.timestamp { return left.timestamp > right.timestamp }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
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

    private func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Double { return Date(timeIntervalSince1970: value) }
        if let value = value as? Int { return Date(timeIntervalSince1970: Double(value)) }
        if let value = value as? String {
            if let seconds = Double(value) { return Date(timeIntervalSince1970: seconds) }
            return ISO8601DateFormatter().date(from: value)
        }
        return nil
    }

    private func compactParts(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private func relativeAge(_ date: Date) -> String {
        let age = max(0, Int(Date().timeIntervalSince(date)))
        if age < 60 { return L("%lld 秒前", age) }
        if age < 3600 { return L("%lld 分鐘前", age / 60) }
        return L("%lld 小時前", age / 3600)
    }
}

private enum HQTrackingLayer: String, CaseIterable, Identifiable {
    case all, field, patient, photo, sos, lora

    var id: String { rawValue }

    static var legendLayers: [HQTrackingLayer] { [.field, .patient, .photo, .sos, .lora] }

    var label: String {
        switch self {
        case .all: return L("全部")
        case .field: return L("前線")
        case .patient: return L("傷員")
        case .photo: return L("照片")
        case .sos: return "SOS"
        case .lora: return "LoRa"
        }
    }

    var shortLabel: String {
        switch self {
        case .all: return L("全部")
        case .field: return L("前線")
        case .patient: return L("傷員")
        case .photo: return L("照片")
        case .sos: return "SOS"
        case .lora: return "LoRa"
        }
    }

    var icon: String {
        switch self {
        case .all: return "map.fill"
        case .field: return "figure.walk.motion"
        case .patient: return "cross.case.fill"
        case .photo: return "photo.fill"
        case .sos: return "sos.circle.fill"
        case .lora: return "antenna.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .all: return NV.green
        case .field: return NV.team
        case .patient: return NV.danger
        case .photo: return NV.info
        case .sos: return NV.danger
        case .lora: return NV.green
        }
    }

    var sortOrder: Int {
        switch self {
        case .sos: return 0
        case .field: return 1
        case .patient: return 2
        case .photo: return 3
        case .lora: return 4
        case .all: return 5
        }
    }

    var emptyIcon: String {
        switch self {
        case .all: return "map"
        case .field: return "location.slash"
        case .patient: return "cross.case"
        case .photo: return "photo"
        case .sos: return "sos"
        case .lora: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return L("目前沒有可追蹤點位")
        case .field: return L("目前沒有前線 GPS 回報")
        case .patient: return L("目前沒有傷員 GPS 座標")
        case .photo: return L("目前沒有照片 GPS 座標")
        case .sos: return L("目前沒有 SOS 座標")
        case .lora: return L("目前沒有 LoRa 節點座標")
        }
    }
}

private struct HQTrackingPin: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let layer: HQTrackingLayer
    let color: Color
    let icon: String
    let timestamp: Date
}

private struct HQTrackingPinView: View {
    let pin: HQTrackingPin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(pin.color)
                    .frame(width: isSelected ? 42 : 34, height: isSelected ? 42 : 34)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                Image(systemName: pin.icon)
                    .font(.system(size: isSelected ? 17 : 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 3)
            )

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
            .frame(maxWidth: 140)
            .background(.black.opacity(0.72))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: NV.tagRadius, style: .continuous))
        }
    }
}

private struct HQTrackingListRow: View {
    let pin: HQTrackingPin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pin.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(pin.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(pin.subtitle.isEmpty ? pin.layer.label : pin.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Text(String(format: "%.4f\n%.4f", pin.coordinate.latitude, pin.coordinate.longitude))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? pin.color.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous)
                    .stroke(isSelected ? pin.color.opacity(0.55) : Color.secondary.opacity(0.16), lineWidth: NV.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 統計標籤

private struct ZoneStatLabel: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.title3).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(NV.cardPadding)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
    }
}

// MARK: - 分區卡片

struct ZoneCard: View {
    let zone: RescueZone
    let personnel: [PersonnelAssignment]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // 標題 + 狀態
                HStack {
                    Text(zone.name)
                        .font(.headline)
                    Spacer()
                    Text(zone.status.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(zone.status.color.opacity(NV.tagOpacity))
                        .foregroundColor(zone.status.color)
                        .cornerRadius(NV.tagRadius)
                }

                // 指派人員
                if !personnel.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("指派人員"), systemImage: "person.fill")
                            .font(.caption2).foregroundColor(.secondary)
                        ForEach(personnel) { p in
                            HStack(spacing: 4) {
                                Image(systemName: p.role.icon)
                                    .font(.caption2)
                                    .foregroundColor(NV.info)
                                Text(p.name)
                                    .font(.caption)
                                Text("(\(p.role.label))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                } else if !zone.assignedPersonnel.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(zone.assignedPersonnel.joined(separator: ", "))
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text(L("尚未指派人員"))
                        .font(.caption2).foregroundColor(.secondary)
                }

                // 危害
                if !zone.hazards.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(zone.hazards, id: \.self) { hazard in
                            HStack(spacing: 2) {
                                Image(systemName: hazard.icon)
                                    .font(.caption2)
                                    .foregroundColor(hazard.color)
                                Text(hazard.label)
                                    .font(.caption2)
                                    .foregroundColor(hazard.color)
                            }
                        }
                    }
                }

                // 備註
                if !zone.note.isEmpty {
                    Text(zone.note)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .hqThemedSurfaceBackground()
            .cornerRadius(NV.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius)
                    .stroke(zone.status.color.opacity(0.4), lineWidth: NV.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新增分區 Sheet

struct AddZoneSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var status: ZoneStatus = .standby
    @State private var note = ""
    @State private var selectedHazards: Set<HazardType> = []

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    TextField(L("分區名稱"), text: $name)
                    Picker(L("狀態"), selection: $status) {
                        ForEach(ZoneStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }

                Section(L("危害因素")) {
                    ForEach(HazardType.allCases, id: \.self) { hazard in
                        Toggle(isOn: Binding(
                            get: { selectedHazards.contains(hazard) },
                            set: { isOn in
                                if isOn { selectedHazards.insert(hazard) }
                                else { selectedHazards.remove(hazard) }
                            }
                        )) {
                            Label(hazard.label, systemImage: hazard.icon)
                        }
                    }
                }

                Section(L("備註")) {
                    TextField(L("備註（選填）"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L("新增搜救分區"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("新增")) {
                        let zone = RescueZone(
                            name: name,
                            status: status,
                            hazards: Array(selectedHazards),
                            note: note
                        )
                        vm.addRescueZone(zone)
                        vm.logEvent(type: .zoneUpdate, title: L("新增分區：%@", name), detail: status.label)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }
}

// MARK: - 編輯分區 Sheet

struct EditZoneSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    let zone: RescueZone
    @State private var name: String
    @State private var status: ZoneStatus
    @State private var note: String
    @State private var selectedHazards: Set<HazardType>
    @State private var assignedNames: String

    init(vm: HQViewModel, zone: RescueZone) {
        self._vm = ObservedObject(wrappedValue: vm)
        self.zone = zone
        self._name = State(initialValue: zone.name)
        self._status = State(initialValue: zone.status)
        self._note = State(initialValue: zone.note)
        self._selectedHazards = State(initialValue: Set(zone.hazards))
        self._assignedNames = State(initialValue: zone.assignedPersonnel.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("基本資訊")) {
                    TextField(L("分區名稱"), text: $name)
                    Picker(L("狀態"), selection: $status) {
                        ForEach(ZoneStatus.allCases, id: \.self) { s in
                            HStack {
                                Circle().fill(s.color).frame(width: 8, height: 8)
                                Text(s.label)
                            }.tag(s)
                        }
                    }
                }

                Section(L("指派人員")) {
                    TextField(L("人員名稱（逗號分隔）"), text: $assignedNames)
                    if !vm.personnelAssignments.isEmpty {
                        Text(L("已配置人員：%@", vm.personnelAssignments.filter { $0.assignedZone == zone.name }.map(\.name).joined(separator: ", ")))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(L("危害因素")) {
                    ForEach(HazardType.allCases, id: \.self) { hazard in
                        Toggle(isOn: Binding(
                            get: { selectedHazards.contains(hazard) },
                            set: { isOn in
                                if isOn { selectedHazards.insert(hazard) }
                                else { selectedHazards.remove(hazard) }
                            }
                        )) {
                            Label(hazard.label, systemImage: hazard.icon)
                        }
                    }
                }

                Section(L("備註")) {
                    TextField(L("備註（選填）"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button(role: .destructive) {
                        vm.disasterSite?.zones.removeAll { $0.id == zone.id }
                        if let site = vm.disasterSite {
                            vm.updateDisasterSite(site)
                        }
                        vm.logEvent(type: .zoneUpdate, title: L("刪除分區：%@", zone.name))
                        dismiss()
                    } label: {
                        Label(L("刪除分區"), systemImage: "trash")
                            .foregroundColor(NV.danger)
                    }
                }
            }
            .navigationTitle(L("編輯分區"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("儲存")) {
                        saveChanges()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    private func saveChanges() {
        guard var site = vm.disasterSite,
              let idx = site.zones.firstIndex(where: { $0.id == zone.id }) else { return }

        let personnel = assignedNames.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        site.zones[idx].name = name
        site.zones[idx].status = status
        site.zones[idx].note = note
        site.zones[idx].hazards = Array(selectedHazards)
        site.zones[idx].assignedPersonnel = personnel

        vm.updateDisasterSite(site)
        vm.logEvent(type: .zoneUpdate, title: L("更新分區：%@", name), detail: status.label)
        dismiss()
    }
}
