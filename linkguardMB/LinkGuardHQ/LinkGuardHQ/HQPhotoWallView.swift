import SwiftUI
import AVKit

// MARK: - HQ 照片牆

struct HQPhotoWallView: View {
    @ObservedObject var vm: HQViewModel

    private let photoGridColumns = [
        GridItem(.adaptive(minimum: 320), spacing: NV.panelSpacing, alignment: .top)
    ]

    private var serverHost: String {
        // 從已連線的 server 取得 Python 後端 IP
        // 照片在 port 8014 — 使用第一個連線的前線裝置 IP 部分
        "localhost"
    }

    private var photoEntries: [PhotoWallEntry] {
        vm.photoAlerts.enumerated().map { index, photo in
            let data = photo["data"] as? [String: Any] ?? photo
            let photoId = data["photo_id"] as? String ?? ""
            let fullURL = data["full_url"] as? String ?? ""
            let timestamp = data["timestamp"] as? String ?? ""
            let stableId = [photoId, fullURL, timestamp]
                .filter { !$0.isEmpty }
                .joined(separator: "|")
            return PhotoWallEntry(id: stableId.isEmpty ? "photo-\(index)" : stableId, data: data)
        }
    }

    var body: some View {
        let entries = photoEntries

        HQPage {
            HQPageTitleBar(L("照片回報"), icon: "photo.on.rectangle.angled", accent: NV.info) {
                Text(L("%lld 張照片", entries.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if entries.isEmpty {
                HQEmptyStateView(icon: "photo.on.rectangle.angled", title: L("尚未收到照片回報"))
                    .hqPanelChrome(accent: NV.info)
            } else {
                LazyVGrid(columns: photoGridColumns, alignment: .leading, spacing: NV.panelSpacing) {
                    ForEach(entries) { entry in
                        PhotoCard(data: entry.data)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PhotoWallEntry: Identifiable {
    let id: String
    let data: [String: Any]
}

struct HQInlinePhotoStrip: View {
    @ObservedObject var vm: HQViewModel
    let reportType: String
    let keywords: [String]
    var title: String = L("照片附件")
    var limit: Int = 3
    var cardWidth: CGFloat = 220

    private var entries: [PhotoWallEntry] {
        matchingPhotoEntries(
            from: vm.photoAlerts,
            reportType: reportType,
            keywords: keywords,
            limit: limit
        )
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entries) { entry in
                            PhotoCard(data: entry.data)
                                .frame(width: cardWidth)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }
}

private func matchingPhotoEntries(
    from alerts: [[String: Any]],
    reportType: String,
    keywords: [String],
    limit: Int
) -> [PhotoWallEntry] {
    let normalizedReportTypeAliases = normalizedPhotoTypeAliases(reportType)
    let normalizedKeywords = keywords
        .map(normalizePhotoLookupText)
        .filter { !$0.isEmpty }

    let candidates = alerts.enumerated().compactMap { entry -> (photo: PhotoWallEntry, haystack: String)? in
        let (index, raw) = entry
        let data = raw["data"] as? [String: Any] ?? raw
        let photoId = data["photo_id"] as? String ?? ""
        let fullURL = data["full_url"] as? String ?? ""
        let timestamp = data["timestamp"] as? String ?? ""
        let stableId = [photoId, fullURL, timestamp]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        let haystack = normalizePhotoLookupText([
            data["location_desc"] as? String ?? "",
            data["caption"] as? String ?? "",
            data["sender_name"] as? String ?? "",
            photoId
        ].joined(separator: " "))

        let photo = PhotoWallEntry(id: stableId.isEmpty ? "inline-photo-\(index)" : stableId, data: data)
        return (photo: photo, haystack: haystack)
    }

    let typeMatches = candidates.filter { candidate in
        normalizedReportTypeAliases.contains(where: { candidate.haystack.contains($0) })
    }

    let keywordFilter: ([(photo: PhotoWallEntry, haystack: String)]) -> [PhotoWallEntry] = { rows in
        let selectedRows: [(photo: PhotoWallEntry, haystack: String)]
        if normalizedKeywords.isEmpty {
            selectedRows = rows
        } else {
            selectedRows = rows.filter { row in
                normalizedKeywords.contains(where: { row.haystack.contains($0) })
            }
        }
        return selectedRows.map(\.photo)
    }

    let phase1 = keywordFilter(typeMatches)
    if !phase1.isEmpty { return Array(phase1.prefix(limit)) }

    let phase2 = keywordFilter(candidates)
    if !phase2.isEmpty { return Array(phase2.prefix(limit)) }

    if !typeMatches.isEmpty {
        return Array(typeMatches.prefix(limit).map(\.photo))
    }

    return Array(candidates.prefix(limit).map(\.photo))
}

private func normalizedPhotoTypeAliases(_ reportType: String) -> [String] {
    let normalized = normalizePhotoLookupText(reportType)
    let aliases: [String]

    switch normalized {
    case normalizePhotoLookupText("隊伍能力概況"), "team_capability":
        aliases = ["隊伍能力概況", "team_capability", "team capability"]
    case normalizePhotoLookupText("傷員回報"), "patient_report":
        aliases = ["傷員回報", "傷患回報", "patient_report", "patient report"]
    case normalizePhotoLookupText("危險回報"), "hazard_report":
        aliases = ["危險回報", "危害回報", "hazard_report", "hazard report"]
    case normalizePhotoLookupText("AI 回報"), "ai_report":
        aliases = ["AI 回報", "ai_report", "ai report"]
    case normalizePhotoLookupText("小隊回報"), "squad_report":
        aliases = ["小隊回報", "squad_report", "squad report"]
    default:
        aliases = [reportType]
    }

    return aliases.map(normalizePhotoLookupText)
}

private func normalizePhotoLookupText(_ text: String) -> String {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

struct PhotoCard: View {
    let data: [String: Any]

    private var photoId: String { data["photo_id"] as? String ?? "" }
    private var sender: String { data["sender_name"] as? String ?? "" }
    private var caption: String { data["caption"] as? String ?? "" }
    private var locationDesc: String { data["location_desc"] as? String ?? "" }
    private var thumbnailURL: String { data["thumbnail_url"] as? String ?? "" }
    private var fullURL: String { data["full_url"] as? String ?? "" }
    private var lat: Double { data["lat"] as? Double ?? 0 }
    private var lon: Double { data["lon"] as? Double ?? 0 }
    private var mediaType: String { data["media_type"] as? String ?? "photo" }
    private var isVideo: Bool { mediaType == "video" }
    private var thumbnailSource: URL? {
        guard !thumbnailURL.isEmpty else { return nil }
        return URL(string: thumbnailURL)
    }
    private var fullSource: URL? {
        guard !fullURL.isEmpty else { return nil }
        return URL(string: fullURL)
    }

    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.secondary.opacity(0.10)

                if let url = thumbnailSource {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .failure:
                            thumbnailPlaceholder
                        default:
                            ProgressView()
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }

                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if fullSource != nil { showFull = true }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(photoId)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isVideo {
                        Text(L("影片"))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.25))
                            .cornerRadius(3)
                    }
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                let locationLine = [sender, locationDesc].filter { !$0.isEmpty }.joined(separator: " · ")
                if !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if lat != 0 || lon != 0 {
                    Text("GPS: \(lat, specifier: "%.4f"), \(lon, specifier: "%.4f")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .hqThemedSurfaceBackground()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NV.info.opacity(0.20), lineWidth: NV.strokeWidth)
        )
        .sheet(isPresented: $showFull) {
            MediaDetailSheet(isVideo: isVideo, url: fullSource) {
                showFull = false
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Image(systemName: isVideo ? "video" : "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaDetailSheet: View {
    let isVideo: Bool
    let url: URL?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L("關閉"), action: onClose)
                    .padding()
            }
            if let url {
                if isVideo {
                    VideoPlaybackView(url: url)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            unavailableMediaView
                        default:
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            } else {
                unavailableMediaView
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var unavailableMediaView: some View {
        VStack(spacing: 8) {
            Image(systemName: isVideo ? "video.slash" : "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(L("媒體無法載入"))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct VideoPlaybackView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 300)
        .padding()
        .onAppear {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
