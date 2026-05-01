import Foundation
import Network
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Mac HQ 照片 HTTP 伺服器

/// 在 HQ Mac 上啟動 HTTP 伺服器（port 8014），接收前線照片上傳
/// 解析 multipart/form-data，存縮圖本地，轉發到 Windows photo_server
class HQPhotoServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var lastError: String? = nil
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.linkguard.photoserver", qos: .userInitiated)

    /// 後台橋接器（照片轉發到 Windows）
    weak var backendBridge: HQBackendBridge?
    /// 收到照片的回呼（UI 更新 + TCP 廣播用）
    var onPhotoReceived: (([String: Any]) -> Void)?

    @Published var receivedCount = 0
    /// 背景執行緒安全計數器
    private var photoCounter = 0

    /// 跨平台照片儲存目錄
    private var photosDir: URL {
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        return base.appendingPathComponent("LinkGuardData/photos")
    }

    func start() {
        guard !isRunning, listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: 8014)
        } catch {
            let errorMsg = "[PhotoServer] Listener 建立失敗: \(error)"
            print(errorMsg)
            DispatchQueue.main.async { self.lastError = errorMsg }
            return
        }

        listener?.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .global())
            self?.receiveHTTPRequest(on: conn)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[PhotoServer] HTTP 伺服器啟動於 port 8014")
                DispatchQueue.main.async {
                    self?.isRunning = true
                    self?.lastError = nil
                }
            case .failed(let err):
                print("[PhotoServer] 失敗: \(err)")
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.lastError = err.localizedDescription
                }
            case .cancelled:
                print("[PhotoServer] 已停止")
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.lastError = nil
                }
            default: break
            }
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP 接收（支援大檔案分片讀取）

    private func receiveHTTPRequest(on conn: NWConnection) {
        accumulateData(conn: conn, accumulated: Data())
    }

    /// 遞迴累積 TCP 資料直到收滿 Content-Length 或連線結束
    private func accumulateData(conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 60 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            if let error {
                print("[PhotoServer] 接收錯誤: \(error)")
                conn.cancel()
                return
            }
            var all = accumulated
            if let data { all.append(data) }

            // 嘗試解析 Content-Length
            if let expectedTotal = self.parseExpectedLength(from: all) {
                if all.count >= expectedTotal || isComplete {
                    self.processHTTPRequest(data: all, conn: conn)
                } else {
                    self.accumulateData(conn: conn, accumulated: all)
                }
            } else if all.range(of: "\r\n\r\n".data(using: .utf8)!) != nil {
                // Header 已經接收完畢，但沒有 Content-Length (例如 GET 請求)，直接處理
                self.processHTTPRequest(data: all, conn: conn)
            } else if isComplete {
                // 連線已結束
                self.processHTTPRequest(data: all, conn: conn)
            } else if all.count > 60 * 1024 * 1024 {
                // 超過 20MB 安全上限
                self.sendHTTPResponse(conn: conn, status: 413, body: ["error": "Request too large"])
            } else {
                // 還沒收到完整 header，繼續讀
                self.accumulateData(conn: conn, accumulated: all)
            }
        }
    }

    /// 從已累積資料中解析 HTTP header 的 Content-Length，回傳預期總長度（header + body）
    private func parseExpectedLength(from data: Data) -> Int? {
        guard let headerEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) else { return nil }
        let headerStr = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        for line in headerStr.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                if let cl = Int(valStr) {
                    let headerSize = data.distance(from: data.startIndex, to: headerEnd.upperBound)
                    return headerSize + cl
                }
            }
        }
        return nil
    }

    // MARK: - HTTP 解析

    private func processHTTPRequest(data: Data, conn: NWConnection) {
        // 只取 HTTP Header 部分來解析字串，避免包含到二進位照片資料導致 UTF8 解析失敗
        guard let headerEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Invalid header"])
            return
        }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let str = String(data: headerData, encoding: .utf8) else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Invalid request string"])
            return
        }

        let lines = str.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "No request line"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Bad request"])
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        if method == "POST" && path == "/photo" {
            handlePhotoUpload(data: data, conn: conn)
        } else if method == "GET" && path.hasPrefix("/photos/") {
            handleGetPhoto(path: path, conn: conn)
        } else if method == "GET" && path == "/health" {
            sendHTTPResponse(conn: conn, status: 200, body: [
                "status": "ok",
                "service": "photo_server",
                "photos_received": receivedCount
            ])
        } else {
            sendHTTPResponse(conn: conn, status: 404, body: ["error": "Not found: \(path)"])
        }
    }

    // MARK: - /photo 端點

    /// 取得 Mac 本機 IP
    private func getLocalIP() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }

    private func handlePhotoUpload(data: Data, conn: NWConnection) {
        guard let parsed = parseMultipart(data: data) else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "無法解析 multipart 資料"])
            return
        }

        guard let photoData = parsed.fileData, !photoData.isEmpty else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "缺少照片檔案"])
            return
        }

        let deviceId = parsed.fields["device_id"] ?? "unknown"
        let senderName = parsed.fields["sender_name"] ?? deviceId
        let lat = parsed.fields["lat"] ?? "0"
        let lon = parsed.fields["lon"] ?? "0"
        let locationDesc = parsed.fields["location_desc"] ?? ""
        let caption = parsed.fields["caption"] ?? ""
        let timestamp = parsed.fields["timestamp"] ?? ISO8601DateFormatter().string(from: Date())
        let mediaType = parsed.fields["media_type"] ?? "photo"
        let isVideoUpload = mediaType == "video"

        photoCounter += 1
        let count = photoCounter
        DispatchQueue.main.async { self.receivedCount = count }
        let photoId = "PHOTO-\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"

        // 1. 本地儲存 + 縮圖
        let photosDir = self.photosDir
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let fileExt = isVideoUpload ? "mp4" : "jpg"
        let fullURL = photosDir.appendingPathComponent("\(photoId).\(fileExt)")
        let thumbURL = photosDir.appendingPathComponent("\(photoId)_thumb.jpg")
        try? photoData.write(to: fullURL)

        if isVideoUpload {
            // 影片：從第一幀產生縮圖
            #if os(macOS)
            let asset = AVURLAsset(url: fullURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 256, height: 256)
            if let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                if let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                    try? jpegData.write(to: thumbURL)
                }
            }
            #endif
            print("[PhotoServer] 影片已存本地: \(fullURL.lastPathComponent) (\(photoData.count / 1024)KB)")
        } else {
            // 照片：縮圖
            #if os(macOS)
            if let image = NSImage(data: photoData) {
                let thumbSize = NSSize(width: 256, height: 256)
                let thumbImage = NSImage(size: thumbSize)
                thumbImage.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: thumbSize),
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .copy, fraction: 1.0)
                thumbImage.unlockFocus()
                if let tiffData = thumbImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                    try? jpegData.write(to: thumbURL)
                }
            }
            #else
            if let image = UIImage(data: photoData) {
                let thumbSize = CGSize(width: 256, height: 256)
                let renderer = UIGraphicsImageRenderer(size: thumbSize)
                let jpegData = renderer.jpegData(withCompressionQuality: 0.7) { ctx in
                    image.draw(in: CGRect(origin: .zero, size: thumbSize))
                }
                try? jpegData.write(to: thumbURL)
            }
            #endif
            print("[PhotoServer] 照片已存本地: \(fullURL.lastPathComponent)")
        }

        // 2. 透過 TCP 廣播 photo_alert 通知
        let localIP = getLocalIP()
        let alertInfo: [String: Any] = [
            "photo_id": photoId,
            "device_id": deviceId,
            "sender_name": senderName,
            "lat": Double(lat) ?? 0,
            "lon": Double(lon) ?? 0,
            "location_desc": locationDesc,
            "caption": caption,
            "timestamp": timestamp,
            "media_type": mediaType,
            "thumbnail_url": "http://\(localIP):8014/photos/\(photoId)_thumb.jpg",
            "full_url": "http://\(localIP):8014/photos/\(photoId).\(fileExt)"
        ]
        DispatchQueue.main.async { [weak self] in
            self?.onPhotoReceived?(alertInfo)
        }

        // 3. 回應 iOS
        sendHTTPResponse(conn: conn, status: 200, body: [
            "photo_id": photoId,
            "thumbnail_url": "http://\(localIP):8014/photos/\(photoId)_thumb.jpg",
            "full_url": "http://\(localIP):8014/photos/\(photoId).\(fileExt)",
            "media_type": mediaType,
            "status": "ok"
        ])
        print("[PhotoServer] \(isVideoUpload ? "影片" : "照片")處理完成 [\(photoId)] from \(senderName)")
    }

    // MARK: - GET /photos/{filename}

    private func handleGetPhoto(path: String, conn: NWConnection) {
        let filename = String(path.dropFirst("/photos/".count))
        guard !filename.isEmpty, !filename.contains("..") else {
            sendHTTPResponse(conn: conn, status: 400, body: ["error": "Invalid filename"])
            return
        }
        let fileURL = photosDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let fileData = try? Data(contentsOf: fileURL) else {
            sendHTTPResponse(conn: conn, status: 404, body: ["error": "File not found"])
            return
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "mp4": contentType = "video/mp4"
        case "mov": contentType = "video/quicktime"
        case "png": contentType = "image/png"
        default: contentType = "image/jpeg"
        }
        sendBinaryResponse(conn: conn, data: fileData, contentType: contentType)
    }

    // MARK: - Multipart 解析

    struct MultipartData {
        var fields: [String: String] = [:]
        var fileData: Data?
        var fileName: String?
    }

    private func parseMultipart(data: Data) -> MultipartData? {
        guard let headerEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) else { return nil }
        let headerStr = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""

        var boundary = ""
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().contains("content-type:") && line.contains("boundary=") {
                if let b = line.components(separatedBy: "boundary=").last {
                    boundary = b.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        guard !boundary.isEmpty else { return nil }

        let bodyData = data[headerEnd.upperBound...]
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let parts = splitData(bodyData, separator: boundaryData)

        var result = MultipartData()

        for part in parts {
            guard part.count > 4 else { continue }
            guard let partHeaderEnd = part.range(of: "\r\n\r\n".data(using: .utf8)!) else { continue }
            let partHeader = String(data: part[part.startIndex..<partHeaderEnd.lowerBound], encoding: .utf8) ?? ""
            var partBody = part[partHeaderEnd.upperBound...]

            if partBody.count >= 2 && partBody.suffix(2) == "\r\n".data(using: .utf8)! {
                partBody = partBody.dropLast(2)
            }

            if partHeader.contains("filename=") {
                result.fileData = Data(partBody)
                if let fnMatch = partHeader.range(of: "filename=\"") {
                    let afterQuote = partHeader[fnMatch.upperBound...]
                    if let endQuote = afterQuote.firstIndex(of: "\"") {
                        result.fileName = String(afterQuote[..<endQuote])
                    }
                }
            } else if let nameMatch = partHeader.range(of: "name=\"") {
                let afterQuote = partHeader[nameMatch.upperBound...]
                if let endQuote = afterQuote.firstIndex(of: "\"") {
                    let fieldName = String(afterQuote[..<endQuote])
                    result.fields[fieldName] = String(data: partBody, encoding: .utf8) ?? ""
                }
            }
        }

        return result
    }

    private func splitData(_ data: Data.SubSequence, separator: Data) -> [Data] {
        var result: [Data] = []
        var searchRange = data.startIndex..<data.endIndex

        while let range = data.range(of: separator, in: searchRange) {
            let chunk = data[searchRange.lowerBound..<range.lowerBound]
            if !chunk.isEmpty { result.append(Data(chunk)) }
            searchRange = range.upperBound..<data.endIndex
        }

        let remaining = data[searchRange]
        if remaining.count > 4 {
            result.append(Data(remaining))
        }

        return result
    }

    // MARK: - HTTP 回應

    private func sendHTTPResponse(conn: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? "{}".data(using: .utf8)!
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(jsonData.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(jsonData)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    /// 回傳圖片二進位
    private func sendImageResponse(conn: NWConnection, data: Data) {
        sendBinaryResponse(conn: conn, data: data, contentType: "image/jpeg")
    }

    private func sendBinaryResponse(conn: NWConnection, data: Data, contentType: String) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(data.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(data)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
