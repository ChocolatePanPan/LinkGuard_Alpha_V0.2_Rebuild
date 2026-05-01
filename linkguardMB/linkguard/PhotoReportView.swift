import SwiftUI
import PhotosUI
import CoreLocation
import Combine
import AVKit
#if canImport(UIKit)
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
#endif

// MARK: - 照片/影片回報頁面

#if canImport(UIKit)
struct PhotoReportView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @StateObject private var locationMgr = PhotoLocationManager()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnail: UIImage?
    @State private var isVideo = false
    @State private var caption: String = ""
    @State private var locationDesc: String = ""
    @State private var isUploading = false
    @State private var showCamera = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var serverHost: String { vm.transcriptionServerHost }

    var body: some View {
        NavigationStack {
            Form {
                // 預覽
                Section {
                    if isVideo, let thumb = videoThumbnail {
                        ZStack {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(radius: 4)
                        }
                    } else if let img = selectedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(L("選擇或拍攝照片/影片"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                // 來源
                Section(L("來源")) {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label(L("拍照/錄影"), systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        PhotosPicker(selection: $selectedItems,
                                     maxSelectionCount: 1,
                                     matching: .any(of: [.images, .videos])) {
                            Label(L("相簿"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                }

                // 說明
                Section(L("說明")) {
                    TextField(L("位置描述（如：B區3F走廊）"), text: $locationDesc)
                    TextField(L("照片/影片說明"), text: $caption)
                }

                // GPS
                Section("GPS") {
                    if let loc = locationMgr.lastLocation {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.green)
                            Text(gpsText(loc))
                                .font(.system(.caption, design: .monospaced))
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text(L("取得位置中…"))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 伺服器
                Section(L("伺服器")) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(serverHost == "localhost" ? .orange : NV.green)
                        Text("\(serverHost):8014")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(serverHost == "localhost" ? L("未連線 HQ") : "Mac HQ")
                            .font(.caption2)
                            .foregroundColor(serverHost == "localhost" ? .orange : .secondary)
                    }
                }

                // 上傳按鈕
                Section {
                    Button {
                        uploadMedia()
                    } label: {
                        if isUploading {
                            HStack {
                                ProgressView()
                                Text(L("上傳中…"))
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label(isVideo ? L("上傳影片回報") : L("上傳照片回報"),
                                  systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NV.green)
                    .disabled((selectedImage == nil && selectedVideoURL == nil) || isUploading)
                }

                // 已上傳列表
                if !vm.photoReports.isEmpty {
                    Section(L("已回報")) {
                        ForEach(vm.photoReports) { photo in
                            HStack(spacing: 12) {
                                ZStack {
                                    AsyncImage(url: URL(string: photo.thumbnailURL)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            Image(systemName: photo.mediaType == "video" ? "video" : "photo")
                                                .foregroundColor(.secondary)
                                        default:
                                            ProgressView()
                                        }
                                    }
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    if photo.mediaType == "video" {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(photo.caption.isEmpty ? photo.id : photo.caption)
                                        .font(.subheadline).bold()
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        if photo.mediaType == "video" {
                                            Text(L("影片"))
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(3)
                                        }
                                        Text("\(photo.senderName) · \(photo.locationDesc)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("照片/影片回報"))
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("完成")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            #endif
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(image: $selectedImage, videoURL: $selectedVideoURL,
                                 videoThumbnail: $videoThumbnail, isVideo: $isVideo)
            }
            .onChange(of: selectedItems) { _, newItems in
                guard let item = newItems.first else { return }
                // 判斷是影片還是照片
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                    // 影片
                    Task {
                        if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                            selectedVideoURL = movie.url
                            videoThumbnail = generateThumbnail(for: movie.url)
                            selectedImage = nil
                            isVideo = true
                        }
                    }
                } else {
                    // 照片
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            selectedImage = img
                            selectedVideoURL = nil
                            videoThumbnail = nil
                            isVideo = false
                        }
                    }
                }
            }
            .alert(L("回報"), isPresented: $showAlert) {
                Button(L("確定")) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Helper

    private func gpsText(_ loc: CLLocation) -> String {
        String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
    }

    private func generateThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 512, height: 512)
        if let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }

    // MARK: - 上傳

    private func uploadMedia() {
        let host = serverHost.contains(":") ? "[\(serverHost)]" : serverHost
        guard let url = URL(string: "http://\(host):8014/photo") else {
            alertMessage = "無法建立上傳網址（host: \(serverHost)）"
            showAlert = true
            return
        }

        var mediaData: Data
        var filename: String
        var mimeType: String
        var mediaType: String

        if isVideo, let videoURL = selectedVideoURL {
            guard let data = try? Data(contentsOf: videoURL) else {
                alertMessage = L("無法讀取影片檔案")
                showAlert = true
                return
            }
            // 限制影片大小 50MB
            if data.count > 50 * 1024 * 1024 {
                alertMessage = L("影片太大（超過 50MB），請選擇較短的影片")
                showAlert = true
                return
            }
            mediaData = data
            filename = "video.mp4"
            mimeType = "video/mp4"
            mediaType = "video"
        } else if let image = selectedImage, let jpegData = image.jpegData(compressionQuality: 0.8) {
            mediaData = jpegData
            filename = "photo.jpg"
            mimeType = "image/jpeg"
            mediaType = "photo"
        } else {
            return
        }

        isUploading = true
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // 影片可能較大

        let lat = locationMgr.lastLocation?.coordinate.latitude ?? 0
        let lon = locationMgr.lastLocation?.coordinate.longitude ?? 0

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("device_id", vm.nodeStatus.nodeID)
        appendField("sender_name", vm.nodeStatus.nodeID)
        appendField("lat", "\(lat)")
        appendField("lon", "\(lon)")
        appendField("location_desc", locationDesc)
        appendField("caption", caption)
        appendField("timestamp", ISO8601DateFormatter().string(from: Date()))
        appendField("media_type", mediaType)

        // 檔案
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(mediaData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isUploading = false
                if let error {
                    let desc = error.localizedDescription
                    if desc.contains("timed out") {
                        alertMessage = "上傳逾時（\(self.serverHost):8014）：請確認 Mac HQ 已啟動且伺服器運行中"
                    } else if desc.contains("Could not connect") || desc.contains("Connection refused") {
                        alertMessage = "無法連線（\(self.serverHost):8014）：Mac HQ 照片伺服器未啟動"
                    } else {
                        alertMessage = "上傳失敗：\(desc)"
                    }
                    showAlert = true
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    alertMessage = "伺服器錯誤（HTTP \(code)）\(body.isEmpty ? "" : "：\(body.prefix(200))")"
                    showAlert = true
                    return
                }

                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let photoId = json["photo_id"] as? String ?? UUID().uuidString
                    let thumbURL = json["thumbnail_url"] as? String ?? ""
                    let fullURL = json["full_url"] as? String ?? ""
                    let report = PhotoReport(
                        id: photoId,
                        senderName: vm.nodeStatus.nodeID,
                        lat: lat, lon: lon,
                        locationDesc: locationDesc,
                        caption: caption,
                        thumbnailURL: thumbURL,
                        fullURL: fullURL,
                        timestamp: Date(),
                        mediaType: mediaType
                    )
                    if !vm.photoReports.contains(where: { $0.id == report.id }) {
                        vm.photoReports.insert(report, at: 0)
                    }
                }

                alertMessage = isVideo ? L("影片回報已送出！") : L("照片回報已送出！")
                showAlert = true
                selectedImage = nil
                selectedVideoURL = nil
                videoThumbnail = nil
                selectedItems = []
                isVideo = false
                caption = ""
                locationDesc = ""
            }
        }.resume()
    }
}

// MARK: - 影片 Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("video_\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

// MARK: - 相機選擇器（支援照片＋影片）

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Binding var videoThumbnail: UIImage?
    @Binding var isVideo: Bool
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let mediaType = info[.mediaType] as? String,
               mediaType == UTType.movie.identifier,
               let url = info[.mediaURL] as? URL {
                // 影片
                parent.videoURL = url
                parent.image = nil
                parent.isVideo = true
                // 產生縮圖
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 512, height: 512)
                if let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                    parent.videoThumbnail = UIImage(cgImage: cgImage)
                }
            } else if let img = info[.originalImage] as? UIImage {
                // 照片
                parent.image = img
                parent.videoURL = nil
                parent.videoThumbnail = nil
                parent.isVideo = false
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#else
// macOS fallback
struct PhotoReportView: View {
    @ObservedObject var vm: LinkGuardViewModel
    var body: some View {
        Text(L("照片回報功能僅支援 iOS"))
            .foregroundColor(.secondary)
    }
}
#endif

// MARK: - GPS

private class PhotoLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}
