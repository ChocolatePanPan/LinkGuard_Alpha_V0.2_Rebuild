import Foundation
import LinkGuardV03Core
import Network

public struct MacSyncReceiverConfiguration: Codable, Hashable, Sendable {
    public var port: UInt16
    public var maxRequestBytes: Int

    public init(port: UInt16 = MacSyncReceiver.defaultPort, maxRequestBytes: Int = 1_048_576) {
        self.port = port
        self.maxRequestBytes = maxRequestBytes
    }
}

struct MacSyncHTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

struct MacSyncHTTPResponse: Equatable, Sendable {
    var statusCode: Int
    var contentType: String
    var body: Data

    init(statusCode: Int, body: Data, contentType: String = "application/json") {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
    }

    func encoded() -> Data {
        let header = [
            "HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}

enum MacSyncHTTPError: Error, Equatable, Sendable {
    case invalidHeader
    case invalidRequestLine
    case invalidContentLength
    case incompleteBody
    case requestTooLarge
}

enum MacSyncHTTPCodec {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func expectedTotalLength(from data: Data) throws -> Int? {
        guard let headerEnd = data.range(of: headerTerminator) else { return nil }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { throw MacSyncHTTPError.invalidHeader }
        for line in header.components(separatedBy: "\r\n") {
            guard line.lowercased().hasPrefix("content-length:") else { continue }
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            guard let contentLength = Int(value), contentLength >= 0 else { throw MacSyncHTTPError.invalidContentLength }
            let headerLength = data.distance(from: data.startIndex, to: headerEnd.upperBound)
            return headerLength + contentLength
        }
        return nil
    }

    static func parseRequest(_ data: Data) throws -> MacSyncHTTPRequest {
        guard let headerEnd = data.range(of: headerTerminator) else { throw MacSyncHTTPError.invalidHeader }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { throw MacSyncHTTPError.invalidHeader }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw MacSyncHTTPError.invalidRequestLine }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { throw MacSyncHTTPError.invalidRequestLine }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separatorIndex]).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEnd.upperBound
        let body = bodyStart < data.endIndex ? Data(data[bodyStart..<data.endIndex]) : Data()
        if let contentLengthText = headers["content-length"], let contentLength = Int(contentLengthText), body.count < contentLength {
            throw MacSyncHTTPError.incompleteBody
        }

        return MacSyncHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }
}

enum MacSyncHTTPResponder {
    static func response(
        for requestData: Data,
        receivedAt: Date,
        batchHandler: ((SyncTransportBatch, Date) -> SyncTransportResponse)?
    ) -> MacSyncHTTPResponse {
        do {
            let request = try MacSyncHTTPCodec.parseRequest(requestData)
            let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
            if request.method == "GET", path == "/health" {
                return jsonResponse(statusCode: 200, body: MacSyncHealthResponse(status: "ok", service: "linkguard_sync_receiver"))
            }

            guard request.method == "POST", path == "/sync" else {
                return jsonResponse(statusCode: path == "/sync" ? 405 : 404, body: MacSyncErrorResponse(error: "unsupported route"))
            }

            guard let batchHandler else {
                return jsonResponse(statusCode: 503, body: MacSyncErrorResponse(error: "sync receiver is not configured"))
            }

            let batch = try LinkGuardJSON.decode(SyncTransportBatch.self, from: request.body)
            let response = batchHandler(batch, receivedAt)
            return jsonResponse(statusCode: 200, body: response)
        } catch MacSyncHTTPError.requestTooLarge {
            return jsonResponse(statusCode: 413, body: MacSyncErrorResponse(error: "request too large"))
        } catch {
            return jsonResponse(statusCode: 400, body: MacSyncErrorResponse(error: String(describing: error)))
        }
    }

    static func jsonResponse<Body: Encodable>(statusCode: Int, body: Body) -> MacSyncHTTPResponse {
        do {
            return MacSyncHTTPResponse(statusCode: statusCode, body: try LinkGuardJSON.encode(body))
        } catch {
            let fallback = Data("{\"error\":\"response encoding failed\"}".utf8)
            return MacSyncHTTPResponse(statusCode: 500, body: fallback)
        }
    }
}

private struct MacSyncHealthResponse: Codable, Hashable, Sendable {
    var status: String
    var service: String
}

private struct MacSyncErrorResponse: Codable, Hashable, Sendable {
    var error: String
}

@MainActor
public final class MacSyncReceiver: ObservableObject {
    public nonisolated static let defaultPort: UInt16 = 8080

    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var port: UInt16 = MacSyncReceiver.defaultPort

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.linkguard.v03.mac-sync-receiver", qos: .userInitiated)
    private var configuration = MacSyncReceiverConfiguration()
    private var batchHandler: ((SyncTransportBatch, Date) -> SyncTransportResponse)?

    public init() {}

    public func start(
        configuration: MacSyncReceiverConfiguration = MacSyncReceiverConfiguration(),
        batchHandler: @escaping (SyncTransportBatch, Date) -> SyncTransportResponse
    ) {
        self.batchHandler = batchHandler
        guard listener == nil else { return }
        self.configuration = configuration
        self.port = configuration.port

        guard let nwPort = NWEndpoint.Port(rawValue: configuration.port) else {
            lastError = "invalid sync receiver port \(configuration.port)"
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: nwPort)
            self.listener = listener
            let receiverQueue = queue
            listener.newConnectionHandler = { [weak self, receiverQueue] connection in
                connection.start(queue: receiverQueue)
                Task { @MainActor [weak self] in
                    self?.receiveHTTPRequest(on: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener.start(queue: receiverQueue)
        } catch {
            listener = nil
            isRunning = false
            lastError = String(describing: error)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        batchHandler = nil
        isRunning = false
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            lastError = nil
        case .failed(let error):
            isRunning = false
            lastError = String(describing: error)
            listener?.cancel()
            listener = nil
        case .cancelled:
            isRunning = false
            listener = nil
        default:
            break
        }
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        accumulateData(on: connection, accumulated: Data())
    }

    private func accumulateData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: configuration.maxRequestBytes) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                if let error {
                    self.lastError = String(describing: error)
                    connection.cancel()
                    return
                }

                var requestData = accumulated
                if let data { requestData.append(data) }

                do {
                    if requestData.count > self.configuration.maxRequestBytes {
                        self.send(MacSyncHTTPResponder.jsonResponse(statusCode: 413, body: MacSyncErrorResponse(error: "request too large")), on: connection)
                    } else if let expectedLength = try MacSyncHTTPCodec.expectedTotalLength(from: requestData) {
                        if expectedLength > self.configuration.maxRequestBytes {
                            self.send(MacSyncHTTPResponder.jsonResponse(statusCode: 413, body: MacSyncErrorResponse(error: "request too large")), on: connection)
                        } else if requestData.count >= expectedLength || isComplete {
                            self.process(requestData, on: connection)
                        } else {
                            self.accumulateData(on: connection, accumulated: requestData)
                        }
                    } else if requestData.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                        self.process(requestData, on: connection)
                    } else {
                        self.accumulateData(on: connection, accumulated: requestData)
                    }
                } catch {
                    self.send(MacSyncHTTPResponder.jsonResponse(statusCode: 400, body: MacSyncErrorResponse(error: String(describing: error))), on: connection)
                }
            }
        }
    }

    private func process(_ requestData: Data, on connection: NWConnection) {
        let response = MacSyncHTTPResponder.response(for: requestData, receivedAt: Date(), batchHandler: batchHandler)
        send(response, on: connection)
    }

    private func send(_ response: MacSyncHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.encoded(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}