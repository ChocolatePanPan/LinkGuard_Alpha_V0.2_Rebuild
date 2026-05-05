import SwiftUI
import PhotosUI
import CoreLocation
import Combine

// MARK: - GPS 定位

private final class MWPhotoLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

// MARK: - 照片報告 Tab

struct MWPhotoTab: View {
    @StateObject private var locationMgr = MWPhotoLocationManager()

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var title = ""
    @State private var locationDesc = ""
    @State private var serverHost = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadMessage = ""
    @State private var showResult = false

    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // ── 伺服器設定 ──
                    VStack(alignment: .leading, spacing: 10) {
                        Label("上傳目標", systemImage: "server.rack")
                            .font(.headline)
                        HStack(spacing: 10) {
                            Circle()
                                .fill(serverHost.isEmpty ? MWTheme.amber : MWTheme.green)
                                .frame(width: 8, height: 8)
                            TextField("HQ 伺服器 IP（如 192.168.1.100）", text: $serverHost)
                                .font(.system(.subheadline, design: .monospaced))
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                                .textContentType(.URL)
                        }
                        .padding(12)
                        .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .mwPhotoPanel()

                    // ── 基本資訊 ──
                    VStack(alignment: .leading, spacing: 12) {
                        Label("照片資訊", systemImage: "info.circle")
                            .font(.headline)

                        HStack {
                            Image(systemName: "text.bubble").foregroundStyle(MWTheme.cyan).frame(width: 24)
                            TextField("標題 / 事件描述", text: $title)
                        }
                        .frame(minHeight: MWTouch.minH)
                        .padding(12)
                        .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(MWTheme.amber).frame(width: 24)
                            TextField("位置描述（例：A棟 2F 樓梯口）", text: $locationDesc)
                        }
                        .frame(minHeight: MWTouch.minH)
                        .padding(12)
                        .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))

                        if let loc = locationMgr.location {
                            HStack {
                                Image(systemName: "location.fill").foregroundStyle(MWTheme.green).frame(width: 24)
                                Text(String(format: "GPS：%.5f, %.5f  精度±%.0fm",
                                             loc.coordinate.latitude, loc.coordinate.longitude,
                                             loc.horizontalAccuracy))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: MWTouch.minH)
                        }
                    }
                    .mwPhotoPanel()

                    // ── 選圖 ──
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("照片（\(selectedImages.count) 張）", systemImage: "photo.stack")
                                .font(.headline)
                            Spacer()
                            PhotosPicker(selection: $pickerItems,
                                         maxSelectionCount: 10,
                                         matching: .images) {
                                Label("選取", systemImage: "plus.circle.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MWTheme.green)
                            }
                            .onChange(of: pickerItems) { _, items in
                                loadImages(from: items)
                            }
                        }

                        if !selectedImages.isEmpty {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: hSizeClass == .regular ? 180 : 140), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, img in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: hSizeClass == .regular ? 160 : 130)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 10))

                                        Button {
                                            selectedImages.remove(at: idx)
                                            if idx < pickerItems.count { pickerItems.remove(at: idx) }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white)
                                                .shadow(radius: 2)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                    }
                                }
                            }
                        } else {
                            // 空狀態
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(MWTheme.green.opacity(0.4))
                                Text("點擊「選取」從相簿選擇照片")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                        }
                    }
                    .mwPhotoPanel()

                    // ── 上傳進度 ──
                    if isUploading {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("上傳中…", systemImage: "arrow.up.circle")
                                .font(.headline)
                            ProgressView(value: uploadProgress)
                                .tint(MWTheme.green)
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .mwPhotoPanel()
                    }

                    // ── 送出按鈕 ──
                    Button {
                        Task { await uploadPhotos() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("上傳至 HQ", systemImage: "arrow.up.doc.fill")
                                .font(.title3.bold())
                            Spacer()
                        }
                        .frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canUpload ? MWTheme.green : .secondary)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .disabled(!canUpload)
                }
                .padding(16)
            }
            .background(MWTheme.bg.ignoresSafeArea())
            .navigationTitle("照片報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清除") { clearAll() }
                        .foregroundStyle(MWTheme.amber)
                        .disabled(selectedImages.isEmpty && title.isEmpty)
                }
            }
            .alert("上傳結果", isPresented: $showResult) {
                Button("確認") { }
            } message: {
                Text(uploadMessage)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canUpload: Bool {
        !selectedImages.isEmpty && !isUploading && !serverHost.isEmpty && !title.isEmpty
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        selectedImages = []
        Task {
            var imgs: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    imgs.append(img)
                }
            }
            await MainActor.run { selectedImages = imgs }
        }
    }

    private func uploadPhotos() async {
        guard canUpload else { return }
        isUploading = true
        uploadProgress = 0

        var uploaded = 0
        var failed = 0
        let total = selectedImages.count

        for (idx, img) in selectedImages.enumerated() {
            guard let data = img.jpegData(compressionQuality: 0.82) else { failed += 1; continue }

            let lat = locationMgr.location?.coordinate.latitude ?? 0
            let lon = locationMgr.location?.coordinate.longitude ?? 0

            var form = MultipartFormData()
            form.append(data, name: "file", fileName: "photo_\(idx + 1).jpg", mimeType: "image/jpeg")
            form.append(title.data(using: .utf8) ?? Data(), name: "title")
            form.append(locationDesc.data(using: .utf8) ?? Data(), name: "location")
            form.append("\(lat)".data(using: .utf8) ?? Data(), name: "lat")
            form.append("\(lon)".data(using: .utf8) ?? Data(), name: "lon")

            guard let url = URL(string: "http://\(serverHost):8003/upload") else { failed += 1; continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = form.finalize()
            req.timeoutInterval = 60

            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if (resp as? HTTPURLResponse)?.statusCode == 200 { uploaded += 1 } else { failed += 1 }
            } catch {
                failed += 1
            }

            let progress = Double(idx + 1) / Double(total)
            await MainActor.run { uploadProgress = progress }
        }

        await MainActor.run {
            isUploading = false
            uploadMessage = failed == 0
                ? "成功上傳 \(uploaded) 張照片至 HQ。"
                : "上傳完成：成功 \(uploaded) 張，失敗 \(failed) 張。"
            showResult = true
        }
    }

    private func clearAll() {
        selectedImages = []
        pickerItems = []
        title = ""
        locationDesc = ""
    }
}

// MARK: - Multipart 工具

private struct MultipartFormData {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    mutating func append(_ data: Data, name: String, fileName: String? = nil, mimeType: String? = nil) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        var disposition = "Content-Disposition: form-data; name=\"\(name)\""
        if let fn = fileName { disposition += "; filename=\"\(fn)\"" }
        body.append("\(disposition)\r\n".data(using: .utf8)!)
        if let mime = mimeType { body.append("Content-Type: \(mime)\r\n".data(using: .utf8)!) }
        body.append("\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    func finalize() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return result
    }
}

// MARK: - Panel modifier

private extension View {
    func mwPhotoPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MWTheme.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
    }
}
