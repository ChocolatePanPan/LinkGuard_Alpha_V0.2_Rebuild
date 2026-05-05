import SwiftUI
import PhotosUI
import CoreLocation
import Combine
import AVKit
import AVFoundation
#if canImport(UIKit)
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
#endif

// MARK: - 照片/影片回報頁面

#if canImport(UIKit)
struct PhotoReportView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    private var isCompactLandscape: Bool { verticalSizeClass == .compact }
    private var previewMaxHeight: CGFloat { isCompactLandscape ? 160 : 280 }
    private var emptyPreviewMinHeight: CGFloat { isCompactLandscape ? 110 : 180 }
    private var titleVerticalPadding: CGFloat { isCompactLandscape ? 6 : 8 }
    private var uploadBarVerticalPadding: CGFloat { isCompactLandscape ? 8 : 12 }
    private var isUploadDisabled: Bool { (selectedImage == nil && selectedVideoURL == nil) || isUploading }

    var body: some View {
        Group {
            if isCompactLandscape {
                landscapeContent
            } else {
                Form {
                        // 預覽
                        Section {
                            if isVideo, let thumb = videoThumbnail {
                                ZStack {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: previewMaxHeight)
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
                                    .frame(maxHeight: previewMaxHeight)
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
                                .frame(maxWidth: .infinity, minHeight: emptyPreviewMinHeight)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                        // 來源
                        Section(L("來源")) {
                            sourceButtons
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

                        // 已上傳列表
                        if !vm.photoReports.isEmpty {
                            Section(L("已回報")) {
                                ForEach(vm.photoReports) { photo in
                                    photoReportRow(photo)
                                }
                            }
                        }
                    }
                }
        }
        .outerNavigationTitle(L("照片/影片回報"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("完成")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        #endif
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            uploadBar
        }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                requestCameraInterfaceOrientations(.allButUpsideDown)
            }) {
                CameraPickerView(image: $selectedImage, videoURL: $selectedVideoURL,
                                 videoThumbnail: $videoThumbnail, isVideo: $isVideo)
                    .background(Color.black)
                    .ignoresSafeArea()
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
                            selectedImage = img.normalizedForPhotoReport()
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

    private var landscapeContent: some View {
        GeometryReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        landscapePanel(L("預覽")) {
                            mediaPreviewContent
                        }
                        landscapePanel(L("來源")) {
                            sourceButtons
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 12) {
                        landscapePanel(L("說明")) {
                            VStack(spacing: 10) {
                                TextField(L("位置描述（如：B區3F走廊）"), text: $locationDesc)
                                TextField(L("照片/影片說明"), text: $caption)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                        landscapePanel("GPS") {
                            gpsRow
                        }
                        landscapePanel(L("伺服器")) {
                            serverRow
                        }
                        if !vm.photoReports.isEmpty {
                            landscapePanel(L("已回報")) {
                                VStack(spacing: 8) {
                                    ForEach(vm.photoReports) { photo in
                                        photoReportRow(photo)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func landscapePanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var mediaPreviewContent: some View {
        if isVideo, let thumb = videoThumbnail {
            ZStack {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(radius: 4)
            }
        } else if let img = selectedImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 190)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text(L("選擇或拍攝照片/影片"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
    }

    private var sourceButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                cameraButton
                albumPickerButton
            }

            VStack(spacing: 10) {
                cameraButton
                albumPickerButton
            }
        }
    }

    private var cameraButton: some View {
        Button {
            openCamera()
        } label: {
            Label(L("拍照/錄影"), systemImage: "camera")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private var albumPickerButton: some View {
        PhotosPicker(selection: $selectedItems,
                     maxSelectionCount: 1,
                     matching: .any(of: [.images, .videos])) {
            Label(L("相簿"), systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
    }

    private func openCamera() {
        requestCameraInterfaceOrientations(.allButUpsideDown)
        showCamera = true
    }

    private func requestCameraInterfaceOrientations(_ orientations: UIInterfaceOrientationMask) {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                print("[PhotoReport] Orientation request failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    @ViewBuilder
    private var gpsRow: some View {
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

    private var serverRow: some View {
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

    private func photoReportRow(_ photo: PhotoReport) -> some View {
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var topTitleBar: some View {
        HStack {
            Text(L("照片/影片回報"))
                .font(.title2).bold()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, titleVerticalPadding)
    }

    private var uploadBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                uploadMedia()
            } label: {
                uploadButtonLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.green)
            .disabled(isUploadDisabled)
            .padding(.horizontal, 16)
            .padding(.vertical, uploadBarVerticalPadding)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var uploadButtonLabel: some View {
        if isUploading {
            HStack {
                ProgressView()
                Text(L("上傳中…"))
            }
        } else {
            Label(isVideo ? L("上傳影片回報") : L("上傳照片回報"),
                  systemImage: "arrow.up.circle.fill")
                .bold()
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

    private func videoUploadInfo(for url: URL) -> (filename: String, mimeType: String) {
        let fileExtension = normalizedVideoExtension(for: url)
        let mimeType: String
        switch fileExtension {
        case "mov":
            mimeType = "video/quicktime"
        case "m4v":
            mimeType = "video/x-m4v"
        default:
            mimeType = "video/mp4"
        }
        return ("video.\(fileExtension)", mimeType)
    }

    private func normalizedVideoExtension(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v":
            return url.pathExtension.lowercased()
        default:
            return "mov"
        }
    }

    // MARK: - 上傳

    private func uploadMedia() {
        let host = serverHost.contains(":") ? "[\(serverHost)]" : serverHost
        guard let url = URL(string: "http://\(host):8014/photo") else {
            alertMessage = L("無法建立上傳網址（host: %@）", serverHost)
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
            let uploadInfo = videoUploadInfo(for: videoURL)
            filename = uploadInfo.filename
            mimeType = uploadInfo.mimeType
            mediaType = "video"
        } else if let image = selectedImage?.normalizedForPhotoReport(), let jpegData = image.jpegData(compressionQuality: 0.8) {
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
        let trimmedNickname = vm.userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        appendField("sender_name", trimmedNickname.isEmpty ? vm.nodeStatus.nodeID : trimmedNickname)
        if !trimmedNickname.isEmpty {
            appendField("nickname", trimmedNickname)
        }
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
                        alertMessage = L("上傳逾時（%@）：請確認 Mac HQ 已啟動且伺服器運行中", "\(self.serverHost):8014")
                    } else if desc.contains("Could not connect") || desc.contains("Connection refused") {
                        alertMessage = L("無法連線（%@）：Mac HQ 照片伺服器未啟動", "\(self.serverHost):8014")
                    } else {
                        alertMessage = L("上傳失敗：%@", desc)
                    }
                    showAlert = true
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : L("：%@", String(body.prefix(200)))
                    alertMessage = L("伺服器錯誤（HTTP %lld）%@", code, detail)
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
            let originalExtension = received.file.pathExtension.lowercased()
            let fileExtension: String
            switch originalExtension {
            case "mov", "mp4", "m4v":
                fileExtension = originalExtension
            default:
                fileExtension = "mov"
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("video_\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

// MARK: - iOS 原生相機

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Binding var videoThumbnail: UIImage?
    @Binding var isVideo: Bool
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        picker.allowsEditing = false
        picker.videoQuality = .typeHigh

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
            if picker.mediaTypes.contains(UTType.movie.identifier) {
                picker.cameraCaptureMode = .photo
            }
        } else {
            picker.sourceType = .photoLibrary
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? [UTType.image.identifier, UTType.movie.identifier]
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let mediaType = info[.mediaType] as? String
            if mediaType == UTType.movie.identifier,
               let url = info[.mediaURL] as? URL {
                let persistedURL = persistVideo(from: url)
                parent.videoURL = persistedURL
                parent.videoThumbnail = thumbnail(for: persistedURL)
                parent.image = nil
                parent.isVideo = true
            } else if let image = info[.originalImage] as? UIImage {
                parent.image = image.normalizedForPhotoReport()
                parent.videoURL = nil
                parent.videoThumbnail = nil
                parent.isVideo = false
            }
            parent.dismiss()
        }

        private func persistVideo(from url: URL) -> URL {
            let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera_video_\(UUID().uuidString).\(fileExtension)")
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                return destination
            } catch {
                return url
            }
        }

        private func thumbnail(for url: URL) -> UIImage? {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }
}

protocol PhotoReportCameraViewControllerDelegate: AnyObject {
    func cameraViewControllerDidCancel(_ controller: PhotoReportCameraViewController)
    func cameraViewController(_ controller: PhotoReportCameraViewController, didCapturePhoto image: UIImage)
    func cameraViewController(_ controller: PhotoReportCameraViewController, didCaptureVideo url: URL)
}

private enum PhotoReportCaptureMode {
    case photo
    case video
}

final class PhotoReportCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    weak var delegate: PhotoReportCameraViewControllerDelegate?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let controlsView = PhotoReportCameraControlsView()
    private let cancelButton = UIButton(type: .system)
    private let unavailableLabel = UILabel()

    private var activeInput: AVCaptureDeviceInput?
    private var activeDevice: AVCaptureDevice?
    private var captureMode: PhotoReportCaptureMode = .photo
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var isLandscapeLayout = false

    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewLayer()
        setupControls()
        setupUnavailableLabel()
        configureSession()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceOrientationDidChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if activeInput != nil, !session.isRunning {
            session.startRunning()
        }
        updatePreviewMirroring()
        updateForCurrentOrientation(animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        updatePreviewOrientation()
        CATransaction.commit()
        updateForCurrentOrientation(animated: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.controlsView.setLandscapeLayout(size.width > size.height)
                self.applyControlRotation(self.currentControlRotationAngle(), animated: false)
                self.view.layoutIfNeeded()
                self.updatePreviewFrameWithoutAnimation()
            }
            CATransaction.commit()
        } completion: { [weak self] _ in
            self?.updatePreviewFrameWithoutAnimation()
            self?.updateForCurrentOrientation(animated: false)
        }
    }

    private func setupPreviewLayer() {
        previewLayer.backgroundColor = UIColor.black.cgColor
        previewLayer.masksToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        previewLayer.setAffineTransform(.identity)
        previewLayer.transform = CATransform3DIdentity
        view.layer.addSublayer(previewLayer)
    }

    private func setupControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        setupCancelButton()

        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        controlsView.onCapture = { [weak self] in
            self?.captureCurrentMode()
        }
        controlsView.onModeChanged = { [weak self] mode in
            self?.setCaptureMode(mode)
        }
        controlsView.onFlipCamera = { [weak self] in
            self?.flipCamera()
        }
        controlsView.onFlashChanged = { [weak self] in
            self?.cycleFlashMode()
        }
    }

    private func setupCancelButton() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark")
        config.title = L("取消")
        config.imagePadding = 6
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        cancelButton.configuration = config
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.widthAnchor.constraint(equalToConstant: 88),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupUnavailableLabel() {
        unavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        unavailableLabel.text = L("此裝置無法使用相機")
        unavailableLabel.textColor = .white
        unavailableLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        unavailableLabel.textAlignment = .center
        unavailableLabel.isHidden = true
        view.addSubview(unavailableLabel)
        NSLayoutConstraint.activate([
            unavailableLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unavailableLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            unavailableLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard installCameraInput(position: .back) else {
            session.commitConfiguration()
            unavailableLabel.isHidden = false
            controlsView.setCaptureEnabled(false)
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        updatePreviewOrientation()
        updatePreviewMirroring()
        controlsView.setFlashAvailable(activeDevice?.hasFlash == true)
        controlsView.setCameraSwitchAvailable(canSwitchCamera)
    }

    @discardableResult
    private func installCameraInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = cameraDevice(position: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        let previousInput = activeInput
        if let activeInput {
            session.removeInput(activeInput)
        }

        guard session.canAddInput(input) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            return false
        }

        session.addInput(input)
        activeInput = input
        activeDevice = device
        return true
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private var canSwitchCamera: Bool {
        cameraDevice(position: .front) != nil && cameraDevice(position: .back) != nil
    }

    private func setCaptureMode(_ mode: PhotoReportCaptureMode) {
        guard !movieOutput.isRecording else { return }
        captureMode = mode
        controlsView.setCaptureMode(mode)
    }

    private func captureCurrentMode() {
        switch captureMode {
        case .photo:
            capturePhoto()
        case .video:
            toggleVideoRecording()
        }
    }

    private func capturePhoto() {
        guard activeInput != nil else { return }
        let settings = AVCapturePhotoSettings()
        if activeDevice?.hasFlash == true {
            settings.flashMode = flashMode
        }
        applyCaptureOrientation(to: photoOutput.connection(with: .video))
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func toggleVideoRecording() {
        guard activeInput != nil else { return }
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            controlsView.setRecording(false)
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo_report_video_\(UUID().uuidString).mov")
        if let connection = movieOutput.connection(with: .video) {
            applyCaptureOrientation(to: connection)
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        controlsView.setRecording(true)
    }

    private func flipCamera() {
        guard !movieOutput.isRecording, canSwitchCamera, let currentPosition = activeDevice?.position else { return }
        let nextPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        var changed = false
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            session.beginConfiguration()
            changed = installCameraInput(position: nextPosition)
            session.commitConfiguration()
            if changed {
                updatePreviewOrientation()
                updatePreviewMirroring()
                controlsView.setFlashAvailable(activeDevice?.hasFlash == true)
                controlsView.setCameraSwitchAvailable(canSwitchCamera)
                if activeDevice?.hasFlash != true {
                    flashMode = .off
                    controlsView.setFlashMode(flashMode)
                }
                controlsView.layoutIfNeeded()
            }
            CATransaction.commit()
        }
    }

    private func cycleFlashMode() {
        guard activeDevice?.hasFlash == true else { return }
        switch flashMode {
        case .off:
            flashMode = .auto
        case .auto:
            flashMode = .on
        default:
            flashMode = .off
        }
        controlsView.setFlashMode(flashMode)
    }

    private func applyCaptureOrientation(to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = currentVideoOrientation()
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        videoOrientation(for: currentInterfaceOrientation())
    }

    private func videoOrientation(for interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch interfaceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    private func previewRotationAngle(for interfaceOrientation: UIInterfaceOrientation) -> CGFloat {
        switch interfaceOrientation {
        case .landscapeLeft, .landscapeRight:
            return 0
        case .portraitUpsideDown:
            return 270
        default:
            return 90
        }
    }

    private func previewVideoOrientation(for interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch interfaceOrientation {
        case .landscapeLeft, .landscapeRight:
            return .portrait
        case .portraitUpsideDown:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let orientation = view.window?.windowScene?.interfaceOrientation,
           orientation != .unknown {
            return orientation
        }
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return view.bounds.width > view.bounds.height ? .landscapeRight : .portrait
        }
    }

    private func currentControlRotationAngle() -> CGFloat {
        0
    }

    private func updateForCurrentOrientation(animated: Bool) {
        controlsView.setLandscapeLayout(view.bounds.width > view.bounds.height)
        updatePreviewOrientation()
        applyControlRotation(currentControlRotationAngle(), animated: animated)
    }

    private func applyControlRotation(_ angle: CGFloat, animated: Bool) {
        let changes = {
            self.cancelButton.transform = CGAffineTransform(rotationAngle: angle)
        }
        controlsView.applyControlRotation(angle, animated: animated)
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes)
        } else {
            changes()
        }
    }

    private func updatePreviewFrameWithoutAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        updatePreviewOrientation()
        CATransaction.commit()
    }

    private func updatePreviewOrientation() {
        previewLayer.setAffineTransform(.identity)
        previewLayer.transform = CATransform3DIdentity
        guard let connection = previewLayer.connection else { return }
        let interfaceOrientation = currentInterfaceOrientation()
        if #available(iOS 17.0, *) {
            let rotationAngle = previewRotationAngle(for: interfaceOrientation)
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
                return
            }
        }
        guard connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = previewVideoOrientation(for: interfaceOrientation)
    }

    private func updatePreviewMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = activeDevice?.position == .front
        CATransaction.commit()
    }

    @objc private func deviceOrientationDidChange() {
        updateForCurrentOrientation(animated: false)
    }

    @objc private func cancelTapped() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            controlsView.setRecording(false)
        }
        delegate?.cameraViewControllerDidCancel(self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }
        delegate?.cameraViewController(self, didCapturePhoto: image)
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        controlsView.setRecording(false)
        guard error == nil else { return }
        delegate?.cameraViewController(self, didCaptureVideo: outputFileURL)
    }
}

private final class PhotoReportCameraControlsView: UIView {
    private static let cameraYellow = UIColor(red: 1, green: 214.0 / 255.0, blue: 10.0 / 255.0, alpha: 1)
    private static let captureInnerReadySize: CGFloat = 54
    private static let captureInnerRecordingSize: CGFloat = 34

    var onCapture: (() -> Void)?
    var onModeChanged: ((PhotoReportCaptureMode) -> Void)?
    var onFlipCamera: (() -> Void)?
    var onFlashChanged: (() -> Void)?

    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let flashButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .custom)
    private let captureInnerCircle = UIView()
    private let flipButton = UIButton(type: .system)
    private let modeSelector = UIStackView()
    private let photoModeButton = UIButton(type: .system)
    private let videoModeButton = UIButton(type: .system)
    private let photoModeDot = UIView()
    private let videoModeDot = UIView()
    private let actionStack = UIStackView()
    private let recordingDurationLabel = UILabel()
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var captureMode: PhotoReportCaptureMode = .photo
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var isCameraSwitchAvailable = true
    private var isRecording = false
    private var isLandscapeLayout = false
    private var captureInnerSizeConstraint: NSLayoutConstraint?
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    deinit {
        recordingTimer?.invalidate()
    }

    func setLandscapeLayout(_ isLandscape: Bool) {
        guard isLandscape != isLandscapeLayout || portraitConstraints.allSatisfy({ !$0.isActive }) && landscapeConstraints.allSatisfy({ !$0.isActive }) else { return }
        isLandscapeLayout = isLandscape
        NSLayoutConstraint.deactivate(isLandscape ? portraitConstraints : landscapeConstraints)
        actionStack.axis = isLandscape ? .vertical : .horizontal
        actionStack.alignment = .center
        actionStack.distribution = .fill
        actionStack.spacing = isLandscape ? 24 : 52
        modeSelector.spacing = isLandscape ? 14 : 28
        NSLayoutConstraint.activate(isLandscape ? landscapeConstraints : portraitConstraints)
        panel.layer.cornerRadius = 0
        setNeedsLayout()
    }

    func applyControlRotation(_ angle: CGFloat, animated: Bool) {
        let changes = {
            let transform = CGAffineTransform(rotationAngle: angle)
            self.captureButton.transform = transform
            self.flipButton.transform = transform
            self.flashButton.transform = transform
            self.modeSelector.transform = transform
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes)
        } else {
            changes()
        }
    }

    func setCaptureMode(_ mode: PhotoReportCaptureMode) {
        captureMode = mode
        updateModeSelector()
        updateCaptureButton()
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        photoModeButton.isEnabled = !recording
        videoModeButton.isEnabled = !recording
        flipButton.isEnabled = !recording && isCameraSwitchAvailable
        flashButton.isEnabled = !recording && flashButton.alpha == 1
        if recording {
            startRecordingTimer()
        } else {
            stopRecordingTimer()
        }
        updateCaptureButton()
    }

    func setFlashAvailable(_ available: Bool) {
        flashButton.isEnabled = available
        flashButton.alpha = available ? 1 : 0.35
        if !available {
            flashMode = .off
        }
        updateFlashButton()
    }

    func setCameraSwitchAvailable(_ available: Bool) {
        isCameraSwitchAvailable = available
        flipButton.isEnabled = available && !isRecording
        flipButton.alpha = available ? 1 : 0.35
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
        updateFlashButton()
    }

    func setCaptureEnabled(_ enabled: Bool) {
        captureButton.isEnabled = enabled
        flipButton.isEnabled = enabled && isCameraSwitchAvailable
        flashButton.isEnabled = enabled && flashButton.alpha == 1
        photoModeButton.isEnabled = enabled
        videoModeButton.isEnabled = enabled
        captureButton.alpha = enabled ? 1 : 0.35
        flipButton.alpha = isCameraSwitchAvailable ? 1 : 0.35
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        captureButton.layer.cornerRadius = captureButton.bounds.width / 2
        captureInnerCircle.layer.cornerRadius = captureInnerCircle.bounds.width / 2
    }

    private func setupViews() {
        isOpaque = false
        backgroundColor = .clear
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isUserInteractionEnabled = false
        panel.clipsToBounds = true
        panel.layer.cornerRadius = 22
        panel.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        addSubview(panel)

        [flashButton, captureButton, flipButton, modeSelector, actionStack, recordingDurationLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.distribution = .fill
        actionStack.spacing = 52
        [flashButton, captureButton, flipButton].forEach { actionStack.addArrangedSubview($0) }
        addSubview(actionStack)
        addSubview(modeSelector)
        addSubview(recordingDurationLabel)

        setupModeSelector()
        setupRecordingDurationLabel()

        configureIconButton(flashButton, image: flashImage(for: flashMode))
        configureIconButton(flipButton, image: UIImage(systemName: "camera.rotate.fill"))

        captureButton.backgroundColor = .clear
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.clipsToBounds = false
        captureInnerCircle.translatesAutoresizingMaskIntoConstraints = false
        captureInnerCircle.isUserInteractionEnabled = false
        captureButton.addSubview(captureInnerCircle)
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        captureButton.addTarget(self, action: #selector(captureTouchDown), for: .touchDown)
        captureButton.addTarget(self, action: #selector(captureTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)

        createLayoutConstraints()
        setLandscapeLayout(false)
        updateCaptureButton()
    }

    private func configureIconButton(_ button: UIButton, image: UIImage?) {
        var config = UIButton.Configuration.filled()
        config.image = image
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        config.cornerStyle = .capsule
        button.configuration = config
        button.tintColor = .white
    }

    private func setupModeSelector() {
        modeSelector.axis = .horizontal
        modeSelector.alignment = .center
        modeSelector.distribution = .equalCentering
        modeSelector.spacing = 28

        let photoItem = makeModeItem(button: photoModeButton, dot: photoModeDot, title: L("照片"))
        let videoItem = makeModeItem(button: videoModeButton, dot: videoModeDot, title: L("影片"))
        [photoItem, videoItem].forEach { modeSelector.addArrangedSubview($0) }

        photoModeButton.addTarget(self, action: #selector(photoModeTapped), for: .touchUpInside)
        videoModeButton.addTarget(self, action: #selector(videoModeTapped), for: .touchUpInside)
        updateModeSelector()
    }

    private func makeModeItem(button: UIButton, dot: UIView, title: String) -> UIStackView {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        button.backgroundColor = .clear

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = Self.cameraYellow
        dot.layer.cornerRadius = 2.5
        dot.isHidden = true
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 5),
            dot.heightAnchor.constraint(equalTo: dot.widthAnchor)
        ])

        let item = UIStackView(arrangedSubviews: [button, dot])
        item.axis = .vertical
        item.alignment = .center
        item.spacing = 3
        return item
    }

    private func updateModeSelector() {
        let isPhoto = captureMode == .photo
        photoModeButton.setTitleColor(isPhoto ? Self.cameraYellow : UIColor.white.withAlphaComponent(0.86), for: .normal)
        videoModeButton.setTitleColor(isPhoto ? UIColor.white.withAlphaComponent(0.86) : Self.cameraYellow, for: .normal)
        photoModeDot.isHidden = !isPhoto
        videoModeDot.isHidden = isPhoto
    }

    private func setupRecordingDurationLabel() {
        recordingDurationLabel.text = "00:00"
        recordingDurationLabel.textColor = .white
        recordingDurationLabel.textAlignment = .center
        recordingDurationLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        recordingDurationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        recordingDurationLabel.layer.cornerRadius = 16
        recordingDurationLabel.clipsToBounds = true
        recordingDurationLabel.alpha = 0
        recordingDurationLabel.isHidden = true
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingStartDate = Date()
        updateRecordingDurationLabel()
        recordingDurationLabel.isHidden = false
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.recordingDurationLabel.alpha = 1
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateRecordingDurationLabel()
        }
        recordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartDate = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.recordingDurationLabel.alpha = 0
        } completion: { _ in
            self.recordingDurationLabel.isHidden = true
            self.recordingDurationLabel.text = "00:00"
        }
    }

    private func updateRecordingDurationLabel() {
        guard let recordingStartDate else {
            recordingDurationLabel.text = "00:00"
            return
        }
        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(recordingStartDate)))
        recordingDurationLabel.text = String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    private func createLayoutConstraints() {
        let safe = safeAreaLayoutGuide
        let captureSize: CGFloat = 72
        let smallButtonSize: CGFloat = 50
        let landscapeStackCenterY = actionStack.centerYAnchor.constraint(equalTo: safe.centerYAnchor)
        landscapeStackCenterY.priority = .defaultHigh
        let captureInnerSizeConstraint = captureInnerCircle.widthAnchor.constraint(equalToConstant: Self.captureInnerReadySize)
        self.captureInnerSizeConstraint = captureInnerSizeConstraint

        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: captureSize),
            captureButton.heightAnchor.constraint(equalTo: captureButton.widthAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: smallButtonSize),
            flashButton.heightAnchor.constraint(equalTo: flashButton.widthAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: smallButtonSize),
            flipButton.heightAnchor.constraint(equalTo: flipButton.widthAnchor),
            modeSelector.heightAnchor.constraint(equalToConstant: 42),
            captureInnerSizeConstraint,
            captureInnerCircle.heightAnchor.constraint(equalTo: captureInnerCircle.widthAnchor),
            captureInnerCircle.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            captureInnerCircle.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            recordingDurationLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            recordingDurationLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 14),
            recordingDurationLabel.heightAnchor.constraint(equalToConstant: 32),
            recordingDurationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])

        portraitConstraints = [
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.heightAnchor.constraint(equalToConstant: 190),
            actionStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            actionStack.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -24),
            actionStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),
            modeSelector.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            modeSelector.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -16),
            modeSelector.widthAnchor.constraint(equalToConstant: 220),
            modeSelector.topAnchor.constraint(greaterThanOrEqualTo: panel.topAnchor, constant: 12)
        ]

        landscapeConstraints = [
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: 132),
            actionStack.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            actionStack.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 44),
            actionStack.bottomAnchor.constraint(lessThanOrEqualTo: modeSelector.topAnchor, constant: -18),
            landscapeStackCenterY,
            modeSelector.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            modeSelector.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),
            modeSelector.widthAnchor.constraint(equalToConstant: 112)
        ]
    }

    private func updateCaptureButton() {
        let targetInnerSize = isRecording ? Self.captureInnerRecordingSize : Self.captureInnerReadySize
        captureInnerSizeConstraint?.constant = targetInnerSize
        if isRecording {
            captureInnerCircle.backgroundColor = UIColor(NV.danger)
        } else if captureMode == .video {
            captureInnerCircle.backgroundColor = UIColor(NV.danger).withAlphaComponent(0.95)
        } else {
            captureInnerCircle.backgroundColor = .white
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.captureInnerCircle.superview?.layoutIfNeeded()
            self.captureInnerCircle.layer.cornerRadius = targetInnerSize / 2
        }
    }

    private func updateFlashButton() {
        var config = flashButton.configuration
        config?.image = flashImage(for: flashMode)
        config?.baseForegroundColor = flashMode == .off ? .white : Self.cameraYellow
        flashButton.configuration = config
    }

    private func flashImage(for mode: AVCaptureDevice.FlashMode) -> UIImage? {
        switch mode {
        case .auto:
            return UIImage(systemName: "bolt.badge.a.fill") ?? UIImage(systemName: "bolt.fill")
        case .on:
            return UIImage(systemName: "bolt.fill")
        default:
            return UIImage(systemName: "bolt.slash.fill")
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        [panel, flashButton, captureButton, flipButton, modeSelector].contains { view in
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            return view.point(inside: convert(point, to: view), with: event)
        }
    }

    @objc private func captureTapped() {
        onCapture?()
    }

    @objc private func captureTouchDown() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.captureInnerCircle.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }

    @objc private func captureTouchUp() {
        UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.5, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.captureInnerCircle.transform = .identity
        }
    }

    @objc private func photoModeTapped() {
        selectMode(.photo)
    }

    @objc private func videoModeTapped() {
        selectMode(.video)
    }

    private func selectMode(_ mode: PhotoReportCaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode
        updateModeSelector()
        updateCaptureButton()
        onModeChanged?(mode)
    }

    @objc private func flipTapped() {
        onFlipCamera?()
    }

    @objc private func flashTapped() {
        onFlashChanged?()
    }
}

private extension UIImage {
    func normalizedForPhotoReport() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
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
