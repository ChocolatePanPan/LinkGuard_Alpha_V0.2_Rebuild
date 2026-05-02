import SwiftUI
import AVKit

// MARK: - HQ 照片牆

struct HQPhotoWallView: View {
    @ObservedObject var vm: HQViewModel

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

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("照片回報"))
                    .font(.title).bold()
                Spacer()
                Text(L("%lld 張照片", entries.count))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L("尚未收到照片回報"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        ForEach(entries) { entry in
                            PhotoCard(data: entry.data)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top)
    }
}

private struct PhotoWallEntry: Identifiable {
    let id: String
    let data: [String: Any]
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
            // 縮圖
            ZStack {
                if let url = thumbnailSource {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            thumbnailPlaceholder
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 150)
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
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 180)
            .clipped()
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                if fullSource != nil { showFull = true }
            }

            // 資訊
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(photoId)
                        .font(.caption.bold())
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
                HStack {
                    Text(sender)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !locationDesc.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(locationDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if lat != 0 || lon != 0 {
                    Text("GPS: \(lat, specifier: "%.4f"), \(lon, specifier: "%.4f")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(NV.surface.opacity(0.5))
        .cornerRadius(12)
        .sheet(isPresented: $showFull) {
            MediaDetailSheet(isVideo: isVideo, url: fullSource) {
                showFull = false
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: isVideo ? "video" : "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct MediaDetailSheet: View {
    let isVideo: Bool
    let url: URL?
    let onClose: () -> Void

    var body: some View {
        VStack {
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
                    .padding()
                }
            } else {
                unavailableMediaView
            }
            Spacer()
        }
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
