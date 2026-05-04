import SwiftUI

struct HQExternalDisplayDashboardView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject private var backendBridge: HQBackendBridge
    @ObservedObject private var audioServer: UDPAudioServer

    init(vm: HQViewModel) {
        self.vm = vm
        self._backendBridge = ObservedObject(wrappedValue: vm.backendBridge)
        self._audioServer = ObservedObject(wrappedValue: vm.udpAudioServer)
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = max(14, min(24, proxy.size.width * 0.014))
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    timeWeatherPanel
                    latestLogPanel
                }
                .frame(height: max(170, proxy.size.height * 0.24))

                HStack(spacing: spacing) {
                    latestPhotoPanel
                    voiceTranslationPanel
                }
                .frame(maxHeight: .infinity)

                bottomMetricsPanel
                    .frame(height: max(150, proxy.size.height * 0.22))
            }
            .padding(spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    NV.bg.ignoresSafeArea()
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(60)
                        .opacity(0.055)
                        .blendMode(.plusLighter)
                        .ignoresSafeArea()
                }
            }
        }
    }

    private var timeWeatherPanel: some View {
        dashboardPanel(title: L("時間與天氣"), icon: "clock.fill", accent: NV.info) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clockText(context.date))
                            .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        Text(dateText(context.date))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    weatherContent
                }
            }
        }
    }

    private var weatherContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let weather = backendBridge.backendWeather {
                HStack(spacing: 10) {
                    weatherChip(icon: "thermometer.medium", value: format(weather.temperature, digits: 1, suffix: "°C"), color: NV.warning)
                    weatherChip(icon: "humidity.fill", value: format(weather.humidity, digits: 0, suffix: "%"), color: NV.info)
                }
                HStack(spacing: 10) {
                    weatherChip(icon: "wind", value: format(weather.windSpeed, digits: 1, suffix: " m/s"), color: NV.green)
                    weatherChip(icon: "cloud.rain.fill", value: format(weather.rainfall, digits: 1, suffix: " mm"), color: NV.command)
                }
                if let obsTime = weather.obsTime, !obsTime.isEmpty {
                    Text(obsTime)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Label(L("等待氣象更新"), systemImage: "cloud.sun")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var latestLogPanel: some View {
        dashboardPanel(title: L("最新日誌"), icon: "list.bullet.rectangle", accent: latestTimelineEvent?.eventType.color ?? NV.command) {
            if let event = latestTimelineEvent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.eventType.icon)
                            .font(.title2)
                            .foregroundColor(event.eventType.color)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title)
                                .font(.title2.bold())
                                .lineLimit(2)
                            if !event.detail.isEmpty {
                                Text(event.detail)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Text(event.source)
                        Spacer()
                        Text(event.relativeTimeText)
                    }
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                }
            } else {
                largeEmptyState(icon: "tray", title: L("尚無事件日誌"))
            }
        }
    }

    private var latestPhotoPanel: some View {
        dashboardPanel(title: L("最新上傳照片"), icon: "photo.fill", accent: NV.team) {
            if let photo = latestPhotoData {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        if let url = photoURL(from: photo) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    photoPlaceholder
                                default:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        } else {
                            photoPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(photoString(photo, "caption", fallback: photoString(photo, "photo_id", fallback: L("照片回報"))))
                            .font(.title3.bold())
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Label(photoString(photo, "sender_name", fallback: L("未知來源")), systemImage: "person.fill")
                            let location = photoString(photo, "location_desc")
                            if !location.isEmpty {
                                Label(location, systemImage: "location.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
            } else {
                largeEmptyState(icon: "photo.on.rectangle.angled", title: L("尚未收到照片回報"))
            }
        }
    }

    private var voiceTranslationPanel: some View {
        dashboardPanel(title: L("最新語音與翻譯"), icon: "waveform.and.bubble.left", accent: NV.green) {
            VStack(alignment: .leading, spacing: 14) {
                voiceBlock
                Divider().background(NV.green.opacity(0.25))
                translationBlock
            }
        }
    }

    private var voiceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("語音"), systemImage: "mic.fill")
                .font(.headline)
                .foregroundColor(NV.green)
            if let report = vm.radioReports.first {
                HStack {
                    Text(report.senderName)
                        .font(.caption.bold())
                    Spacer()
                    Text(report.timestamp, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(report.transcription)
                    .font(.title3)
                    .foregroundColor(.primary)
                    .lineLimit(5)
            } else if let live = latestLiveTranscription {
                Text(live.deviceID)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text(live.text)
                    .font(.title3)
                    .lineLimit(5)
            } else {
                Text(L("尚無轉錄紀錄"))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var translationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("翻譯"), systemImage: "character.bubble.fill")
                .font(.headline)
                .foregroundColor(NV.info)
            if let translation = vm.latestTranslation {
                Text(translation.original)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(translation.translated)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                    .lineLimit(4)
                Text("\(translation.detectedLang) → \(translation.targetLang)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            } else {
                Text(L("尚無翻譯結果"))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var bottomMetricsPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            metricTile(title: L("搜救參與總人數"), value: rescueParticipantCount, icon: "person.3.fill", color: NV.team)
            metricTile(title: L("受困者人數"), value: vm.totalVictimCount, icon: "person.fill.questionmark", color: NV.warning)
            metricTile(title: L("即刻"), value: triageCounts.immediate, icon: "cross.case.fill", color: NV.danger)
            metricTile(title: L("延遲"), value: triageCounts.delayed, icon: "clock.badge.exclamationmark", color: NV.warning)
            metricTile(title: L("輕微"), value: triageCounts.minor, icon: "figure.walk", color: NV.green)
            metricTile(title: L("期望"), value: triageCounts.expectant, icon: "waveform.path.ecg.rectangle", color: .gray)
        }
    }

    private func dashboardPanel<Content: View>(title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private func metricTile(title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    private var photoPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            Image(systemName: "photo")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    private func largeEmptyState(icon: String, title: String) -> some View {
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

    private var latestTimelineEvent: TimelineEvent? {
        vm.timelineEvents.first
    }

    private var latestPhotoData: [String: Any]? {
        guard let photo = vm.photoAlerts.first else { return nil }
        return photo["data"] as? [String: Any] ?? photo
    }

    private var latestLiveTranscription: (deviceID: String, text: String)? {
        if let final = audioServer.finalTranscriptions.sorted(by: { $0.key < $1.key }).last, !final.value.isEmpty {
            return (final.key, final.value)
        }
        if let live = audioServer.liveTranscriptions.sorted(by: { $0.key < $1.key }).last, !live.value.isEmpty {
            return (live.key, live.value)
        }
        return nil
    }

    private var rescueParticipantCount: Int {
        vm.personnelAssignments.count + vm.allTeamOverview.count
    }

    private var triageCounts: ExternalTriageCounts {
        if let patients = vm.latestStatsUpdate?["patients"] as? [String: Any] {
            return ExternalTriageCounts(
                immediate: intValue(patients["immediate"]),
                delayed: intValue(patients["delayed"]),
                minor: intValue(patients["minor"]),
                expectant: intValue(patients["expectant"])
            )
        }

        if !vm.patientReports.isEmpty {
            return vm.patientReports.reduce(into: ExternalTriageCounts()) { result, report in
                if report.breathingRate <= 0 {
                    result.expectant += 1
                } else if report.breathingRate > 30 || report.capillaryRefill > 2.0 || !report.canFollowCommands {
                    result.immediate += 1
                } else {
                    result.minor += 1
                }
            }
        }

        return vm.allVictimRecords.reduce(into: ExternalTriageCounts()) { result, record in
            switch record.priority {
            case .critical:
                result.immediate += 1
            case .high, .medium:
                result.delayed += 1
            case .low:
                result.minor += 1
            case .unset:
                break
            }
        }
    }

    private func photoURL(from data: [String: Any]) -> URL? {
        let thumbnail = photoString(data, "thumbnail_url")
        if !thumbnail.isEmpty { return URL(string: thumbnail) }
        let full = photoString(data, "full_url")
        return full.isEmpty ? nil : URL(string: full)
    }

    private func photoString(_ data: [String: Any], _ key: String, fallback: String = "") -> String {
        if let value = data[key] as? String { return value }
        if let value = data[key] { return "\(value)" }
        return fallback
    }

    private func weatherChip(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(value)
                .monospacedDigit()
        }
        .font(.headline)
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func format(_ value: Double?, digits: Int, suffix: String) -> String {
        guard let value else { return "--\(suffix)" }
        return String(format: "%.*f%@", digits, value, suffix)
    }

    private func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd EEEE"
        return formatter.string(from: date)
    }
}

private struct ExternalTriageCounts {
    var immediate = 0
    var delayed = 0
    var minor = 0
    var expectant = 0
}