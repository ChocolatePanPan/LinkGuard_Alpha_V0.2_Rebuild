import Foundation

public struct SyncTransportBatch: Codable, Sendable {
    public var device: DeviceIdentity
    public var generatedAt: Date
    public var envelopes: [SyncEnvelope]

    public init(device: DeviceIdentity, generatedAt: Date, envelopes: [SyncEnvelope]) {
        self.device = device
        self.generatedAt = generatedAt
        self.envelopes = envelopes
    }
}

public struct SyncTransportReceipt: Codable, Hashable, Sendable {
    public var envelopeID: LinkGuardID
    public var accepted: Bool
    public var receivedAt: Date?
    public var error: String?

    public init(envelopeID: LinkGuardID, accepted: Bool, receivedAt: Date? = nil, error: String? = nil) {
        self.envelopeID = envelopeID
        self.accepted = accepted
        self.receivedAt = receivedAt
        self.error = error
    }
}

public struct SyncTransportResponse: Codable, Sendable {
    public var receipts: [SyncTransportReceipt]

    public init(receipts: [SyncTransportReceipt]) {
        self.receipts = receipts
    }
}

public enum SyncTransportError: Error, Equatable, Sendable {
    case invalidHTTPStatus(Int)
    case emptyBatch
}

public protocol SyncTransportClient: Sendable {
    func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse
}

public struct HTTPEnvelopeTransport: SyncTransportClient, Sendable {
    public var endpointURL: URL
    public var bearerToken: String?
    public var timeout: TimeInterval

    public init(endpointURL: URL, bearerToken: String? = nil, timeout: TimeInterval = 10) {
        self.endpointURL = endpointURL
        self.bearerToken = bearerToken
        self.timeout = timeout
    }

    public func makeBatch(envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) throws -> SyncTransportBatch {
        guard envelopes.isEmpty == false else { throw SyncTransportError.emptyBatch }
        return SyncTransportBatch(device: device, generatedAt: date, envelopes: envelopes)
    }

    public func makeRequest(for batch: SyncTransportBatch) throws -> URLRequest {
        var request = URLRequest(url: endpointURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(batch.device.id.rawValue, forHTTPHeaderField: "X-LinkGuard-Device-ID")
        request.setValue(batch.device.appID.rawValue, forHTTPHeaderField: "X-LinkGuard-App-ID")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try LinkGuardJSON.encode(batch)
        return request
    }

    public func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse {
        let batch = try makeBatch(envelopes: envelopes, from: device, at: date)
        let request = try makeRequest(for: batch)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncTransportError.invalidHTTPStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SyncTransportError.invalidHTTPStatus(httpResponse.statusCode)
        }
        return try LinkGuardJSON.decode(SyncTransportResponse.self, from: data)
    }
}