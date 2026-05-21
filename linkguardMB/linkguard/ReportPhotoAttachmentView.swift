import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct ReportPhotoAttachmentView: View {
    @ObservedObject var vm: LinkGuardViewModel
    let reportType: String
    let reportTypeKey: String
    let context: String

    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var isUploading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var serverHost: String { vm.transcriptionServerHost }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("回報照片"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label(L("拍照"), systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    uploadSelectedPhoto()
                } label: {
                    if isUploading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(L("上傳照片"), systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImage == nil || isUploading)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(image: $selectedImage,
                             videoURL: .constant(nil),
                             videoThumbnail: .constant(nil),
                             isVideo: .constant(false))
        }
        .alert(L("照片回報"), isPresented: $showAlert) {
            Button(L("確定"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func uploadSelectedPhoto() {
          guard let image = selectedImage,
              let jpegData = image.jpegData(compressionQuality: 0.8) else { return }

        let host = serverHost.contains(":") ? "[\(serverHost)]" : serverHost
        guard let url = URL(string: "http://\(host):8014/photo") else {
            alertMessage = L("無法建立上傳網址（host: %@）", serverHost)
            showAlert = true
            return
        }

        isUploading = true
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        let trimmedNickname = vm.userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        appendField("device_id", vm.nodeStatus.nodeID)
        appendField("sender_name", trimmedNickname.isEmpty ? vm.nodeStatus.nodeID : trimmedNickname)
        appendField("lat", "0")
        appendField("lon", "0")
        appendField("location_desc", reportTypeKey)
        appendField("caption", "[\(reportType)] \(context)")
        appendField("timestamp", ISO8601DateFormatter().string(from: Date()))
        appendField("media_type", "photo")

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"report_photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isUploading = false
                if let error {
                    alertMessage = L("上傳失敗：%@", error.localizedDescription)
                    showAlert = true
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    alertMessage = L("伺服器錯誤（HTTP %lld）：%@", code, String(raw.prefix(160)))
                    showAlert = true
                    return
                }
                alertMessage = L("照片已附加到回報並送出")
                showAlert = true
                selectedImage = nil
            }
        }.resume()
    }
}

#else
struct ReportPhotoAttachmentView: View {
    @ObservedObject var vm: LinkGuardViewModel
    let reportType: String
    let reportTypeKey: String
    let context: String

    var body: some View {
        Text(L("目前平台不支援拍照回報"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
#endif
