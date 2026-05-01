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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("照片回報"))
                    .font(.title).bold()
                Spacer()
                Text(L("%lld 張照片", vm.photoAlerts.count))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if vm.photoAlerts.isEmpty {
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
                        ForEach(0..<vm.photoAlerts.count, id: \.self) { idx in
                            let photo = vm.photoAlerts[idx]
                            let data = photo["data"] as? [String: Any] ?? photo
                            PhotoCard(data: data)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top)
    }
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

    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 縮圖
            if let url = URL(string: thumbnailURL), !thumbnailURL.isEmpty {
                ZStack {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: isVideo ? "video" : "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 150)
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 150)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipped()
                    .cornerRadius(8)

                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
                .onTapGesture { showFull = true }
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
            VStack {
                HStack {
                    Spacer()
                    Button(L("關閉")) { showFull = false }
                        .padding()
                }
                if isVideo, let url = URL(string: fullURL), !fullURL.isEmpty {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(minHeight: 300)
                        .padding()
                } else if let url = URL(string: fullURL), !fullURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            ProgressView()
                        }
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
