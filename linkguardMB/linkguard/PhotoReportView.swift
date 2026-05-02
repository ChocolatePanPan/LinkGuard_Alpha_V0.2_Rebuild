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
        NavigationStack {
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
            .navigationTitle(L("照片/影片回報"))
            #if os(iOS)
            .toolbarVisibility(.hidden, for: .navigationBar)
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
            .safeAreaInset(edge: .top) {
                topTitleBar
            }
            .safeAreaInset(edge: .bottom) {
                uploadBar
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                requestCameraInterfaceOrientations(.allButUpsideDown)
            }) {
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

// MARK: - 自訂相機控制器（AVCaptureVideoPreviewLayer）

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Binding var videoThumbnail: UIImage?
    @Binding var isVideo: Bool
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PhotoReportCameraViewController {
        let controller = PhotoReportCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PhotoReportCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PhotoReportCameraViewControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) { self.parent = parent }

        func cameraViewControllerDidCancel(_ controller: PhotoReportCameraViewController) {
            parent.dismiss()
        }

        func cameraViewController(_ controller: PhotoReportCameraViewController, didCapturePhoto image: UIImage) {
            parent.image = image.normalizedForPhotoReport()
            parent.videoURL = nil
            parent.videoThumbnail = nil
            parent.isVideo = false
            parent.dismiss()
        }

        func cameraViewController(_ controller: PhotoReportCameraViewController, didCaptureVideo url: URL) {
            parent.videoURL = url
            parent.videoThumbnail = thumbnail(for: url)
            parent.image = nil
            parent.isVideo = true
            parent.dismiss()
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
        lockPreviewOrientation()
        CATransaction.commit()
        updateControlsLayout(isLandscape: view.bounds.width > view.bounds.height, animated: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        updateControlsLayout(isLandscape: size.width > size.height, animated: true)
        coordinator.animate { [weak self] _ in
            self?.view.layoutIfNeeded()
            self?.controlsView.applyControlRotation(self?.currentControlRotationAngle() ?? 0, animated: true)
        } completion: { [weak self] _ in
            self?.updatePreviewFrameWithoutAnimation()
        }
    }

    private func setupPreviewLayer() {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
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
        lockPreviewOrientation()
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
        session.beginConfiguration()
        let changed = installCameraInput(position: nextPosition)
        session.commitConfiguration()
        if changed {
            updatePreviewMirroring()
            controlsView.setFlashAvailable(activeDevice?.hasFlash == true)
            controlsView.setCameraSwitchAvailable(canSwitchCamera)
            if activeDevice?.hasFlash != true {
                flashMode = .off
                controlsView.setFlashMode(flashMode)
            }
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
        switch currentInterfaceOrientation() {
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
        switch currentInterfaceOrientation() {
        case .landscapeLeft:
            return .pi / 2
        case .landscapeRight:
            return -.pi / 2
        default:
            return 0
        }
    }

    private func updateForCurrentOrientation(animated: Bool) {
        updateControlsLayout(isLandscape: view.bounds.width > view.bounds.height, animated: animated)
        controlsView.applyControlRotation(currentControlRotationAngle(), animated: animated)
    }

    private func updateControlsLayout(isLandscape: Bool, animated: Bool) {
        guard isLandscape != isLandscapeLayout else { return }
        isLandscapeLayout = isLandscape
        controlsView.setLandscapeLayout(isLandscape)

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
        } else {
            view.layoutIfNeeded()
        }
    }

    private func updatePreviewFrameWithoutAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        lockPreviewOrientation()
        CATransaction.commit()
    }

    private func lockPreviewOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported
        else { return }
        connection.videoOrientation = .portrait
    }

    private func updatePreviewMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = activeDevice?.position == .front
    }

    @objc private func deviceOrientationDidChange() {
        updateForCurrentOrientation(animated: true)
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
    var onCapture: (() -> Void)?
    var onModeChanged: ((PhotoReportCaptureMode) -> Void)?
    var onFlipCamera: (() -> Void)?
    var onFlashChanged: (() -> Void)?

    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let flashButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .custom)
    private let flipButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: [L("照片"), L("影片")])
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var captureMode: PhotoReportCaptureMode = .photo
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var isCameraSwitchAvailable = true
    private var isRecording = false
    private var isLandscapeLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func setLandscapeLayout(_ isLandscape: Bool) {
        guard isLandscape != isLandscapeLayout || portraitConstraints.allSatisfy({ !$0.isActive }) && landscapeConstraints.allSatisfy({ !$0.isActive }) else { return }
        isLandscapeLayout = isLandscape
        NSLayoutConstraint.deactivate(isLandscape ? portraitConstraints : landscapeConstraints)
        NSLayoutConstraint.activate(isLandscape ? landscapeConstraints : portraitConstraints)
        panel.layer.cornerRadius = isLandscape ? 0 : 22
        setNeedsLayout()
    }

    func applyControlRotation(_ angle: CGFloat, animated: Bool) {
        let changes = {
            let transform = CGAffineTransform(rotationAngle: angle)
            self.captureButton.transform = transform
            self.flipButton.transform = transform
            self.flashButton.transform = transform
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes)
        } else {
            changes()
        }
    }

    func setCaptureMode(_ mode: PhotoReportCaptureMode) {
        captureMode = mode
        modeControl.selectedSegmentIndex = mode == .video ? 1 : 0
        updateCaptureButton()
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        modeControl.isEnabled = !recording
        flipButton.isEnabled = !recording && isCameraSwitchAvailable
        flashButton.isEnabled = !recording && flashButton.alpha == 1
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
        modeControl.isEnabled = enabled
        captureButton.alpha = enabled ? 1 : 0.35
        flipButton.alpha = isCameraSwitchAvailable ? 1 : 0.35
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        captureButton.layer.cornerRadius = captureButton.bounds.width / 2
    }

    private func setupViews() {
        isOpaque = false
        backgroundColor = .clear
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isUserInteractionEnabled = false
        panel.clipsToBounds = true
        panel.layer.cornerRadius = 22
        addSubview(panel)

        [flashButton, captureButton, flipButton, modeControl].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        configureIconButton(flashButton, image: flashImage(for: flashMode))
        configureIconButton(flipButton, image: UIImage(systemName: "camera.rotate.fill"))

        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)

        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor(NV.green)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)

        createLayoutConstraints()
        setLandscapeLayout(false)
        updateCaptureButton()
    }

    private func configureIconButton(_ button: UIButton, image: UIImage?) {
        var config = UIButton.Configuration.filled()
        config.image = image
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
        config.cornerStyle = .capsule
        button.configuration = config
        button.tintColor = .white
    }

    private func createLayoutConstraints() {
        let safe = safeAreaLayoutGuide
        let captureSize: CGFloat = 72
        let smallButtonSize: CGFloat = 50

        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: captureSize),
            captureButton.heightAnchor.constraint(equalTo: captureButton.widthAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: smallButtonSize),
            flashButton.heightAnchor.constraint(equalTo: flashButton.widthAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: smallButtonSize),
            flipButton.heightAnchor.constraint(equalTo: flipButton.widthAnchor),
            modeControl.heightAnchor.constraint(equalToConstant: 34)
        ])

        portraitConstraints = [
            modeControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 12),
            modeControl.widthAnchor.constraint(equalToConstant: 220),
            captureButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: content.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            flashButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            flashButton.leadingAnchor.constraint(equalTo: content.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            flipButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            flipButton.trailingAnchor.constraint(equalTo: content.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ]

        landscapeConstraints = [
            flashButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            flashButton.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 56),
            captureButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            captureButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            flipButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            flipButton.bottomAnchor.constraint(equalTo: modeControl.topAnchor, constant: -18),
            modeControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            modeControl.bottomAnchor.constraint(equalTo: content.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            modeControl.widthAnchor.constraint(equalToConstant: 104)
        ]
    }

    private func updateCaptureButton() {
        if isRecording {
            captureButton.backgroundColor = UIColor(NV.danger)
        } else if captureMode == .video {
            captureButton.backgroundColor = UIColor(NV.danger).withAlphaComponent(0.9)
        } else {
            captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        }
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.heightAnchor.constraint(equalToConstant: 158),
            modeControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
    private func updateFlashButton() {
            captureButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),
        flashButton.configuration = config
            flashButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 32),

            flipButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -32)
        switch mode {
        case .auto:
            return UIImage(systemName: "bolt.badge.a.fill") ?? UIImage(systemName: "bolt.fill")
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: 132),
            flashButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            flashButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 72),
        default:
            captureButton.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
        }
    }

            modeControl.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),
            modeControl.widthAnchor.constraint(equalToConstant: 108)
    }


    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        [panel, flashButton, captureButton, flipButton, modeControl].contains { view in
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            return view.point(inside: convert(point, to: view), with: event)
        }
    }
    @objc private func modeChanged() {
        let mode: PhotoReportCaptureMode = modeControl.selectedSegmentIndex == 1 ? .video : .photo
        captureMode = mode
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
