import Foundation

public enum ConnectivityState: String, Codable, CaseIterable, Sendable {
    case online
    case degraded
    case offline
}

public struct OfflineSyncPlan: Codable, Hashable, Sendable {
    public var connectivity: ConnectivityState
    public var shouldAttemptSync: Bool
    public var pendingEnvelopeIDs: [LinkGuardID]
    public var reason: String

    public init(connectivity: ConnectivityState, shouldAttemptSync: Bool, pendingEnvelopeIDs: [LinkGuardID], reason: String) {
        self.connectivity = connectivity
        self.shouldAttemptSync = shouldAttemptSync
        self.pendingEnvelopeIDs = pendingEnvelopeIDs
        self.reason = reason
    }
}

public struct LocalOperationCache: Codable, Sendable {
    public private(set) var snapshot: OperationSnapshot
    public private(set) var outboundQueue: OfflineQueue
    public private(set) var connectivity: ConnectivityState
    public private(set) var lastSavedAt: Date?
    public private(set) var lastSyncAt: Date?

    public init(
        snapshot: OperationSnapshot = OperationSnapshot(),
        outboundQueue: OfflineQueue = OfflineQueue(),
        connectivity: ConnectivityState = .offline,
        lastSavedAt: Date? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.outboundQueue = outboundQueue
        self.connectivity = connectivity
        self.lastSavedAt = lastSavedAt
        self.lastSyncAt = lastSyncAt
    }

    public var pendingCount: Int {
        outboundQueue.entries.filter { $0.state == .queued || $0.state == .failed }.count
    }

    public mutating func markConnectivity(_ connectivity: ConnectivityState) {
        self.connectivity = connectivity
    }

    public mutating func save(at date: Date) {
        lastSavedAt = date
    }

    public mutating func applyInbound(_ envelope: SyncEnvelope) throws {
        try snapshot.apply(envelope)
    }

    public mutating func queue(_ envelope: SyncEnvelope, at queuedAt: Date) {
        outboundQueue.enqueue(envelope, queuedAt: queuedAt)
        lastSavedAt = queuedAt
    }

    public mutating func markDelivered(_ messageID: LinkGuardID, at syncDate: Date) {
        outboundQueue.markDelivered(messageID: messageID)
        outboundQueue.removeDelivered()
        lastSyncAt = syncDate
        lastSavedAt = syncDate
    }

    public func pendingEnvelopes(limit: Int? = nil) -> [SyncEnvelope] {
        let entries = outboundQueue.entries.filter { $0.state == .queued || $0.state == .failed }
        return Array(entries.prefix(limit ?? Int.max).map(\.envelope))
    }

    public func makeSyncPlan(limit: Int? = nil) -> OfflineSyncPlan {
        let pendingIDs = pendingEnvelopes(limit: limit).map(\.id)
        switch connectivity {
        case .online:
            return OfflineSyncPlan(
                connectivity: connectivity,
                shouldAttemptSync: pendingIDs.isEmpty == false,
                pendingEnvelopeIDs: pendingIDs,
                reason: pendingIDs.isEmpty ? "no pending envelopes" : "online with pending envelopes"
            )
        case .degraded:
            return OfflineSyncPlan(
                connectivity: connectivity,
                shouldAttemptSync: pendingIDs.isEmpty == false,
                pendingEnvelopeIDs: pendingIDs,
                reason: pendingIDs.isEmpty ? "degraded network with empty queue" : "degraded network; sync critical queue first"
            )
        case .offline:
            return OfflineSyncPlan(
                connectivity: connectivity,
                shouldAttemptSync: false,
                pendingEnvelopeIDs: pendingIDs,
                reason: "offline"
            )
        }
    }

    public func encoded() throws -> Data {
        try LinkGuardJSON.encode(self)
    }

    public static func decoded(from data: Data) throws -> LocalOperationCache {
        try LinkGuardJSON.decode(LocalOperationCache.self, from: data)
    }
}