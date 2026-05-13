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

public enum OfflineSyncTrigger: String, Codable, CaseIterable, Sendable {
    case appLaunch
    case connectivityRecovered
    case backgroundRefresh
    case manualRetry
}

public struct BackgroundSyncPolicy: Codable, Hashable, Sendable {
    public var batchLimit: Int
    public var allowsDegradedNetwork: Bool
    public var minimumRetryInterval: TimeInterval

    public init(batchLimit: Int = 25, allowsDegradedNetwork: Bool = true, minimumRetryInterval: TimeInterval = 15) {
        self.batchLimit = batchLimit
        self.allowsDegradedNetwork = allowsDegradedNetwork
        self.minimumRetryInterval = minimumRetryInterval
    }

    public func allowsSync(connectivity: ConnectivityState, trigger: OfflineSyncTrigger) -> Bool {
        switch connectivity {
        case .online:
            return true
        case .degraded:
            return allowsDegradedNetwork || trigger == .manualRetry
        case .offline:
            return false
        }
    }
}

public struct OfflineSyncResult: Codable, Hashable, Sendable {
    public var attempted: Bool
    public var trigger: OfflineSyncTrigger
    public var connectivity: ConnectivityState
    public var deliveredEnvelopeIDs: [LinkGuardID]
    public var failedEnvelopeIDs: [LinkGuardID]
    public var remainingPendingCount: Int
    public var completedAt: Date

    public init(
        attempted: Bool,
        trigger: OfflineSyncTrigger,
        connectivity: ConnectivityState,
        deliveredEnvelopeIDs: [LinkGuardID] = [],
        failedEnvelopeIDs: [LinkGuardID] = [],
        remainingPendingCount: Int,
        completedAt: Date
    ) {
        self.attempted = attempted
        self.trigger = trigger
        self.connectivity = connectivity
        self.deliveredEnvelopeIDs = deliveredEnvelopeIDs
        self.failedEnvelopeIDs = failedEnvelopeIDs
        self.remainingPendingCount = remainingPendingCount
        self.completedAt = completedAt
    }
}

public enum LocalOperationCacheStoreError: Error, Equatable, Sendable {
    case cacheFileMissing(URL)
}

public struct FileBackedLocalOperationCacheStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load(default defaultCache: LocalOperationCache = LocalOperationCache()) throws -> LocalOperationCache {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultCache
        }
        let data = try Data(contentsOf: fileURL)
        return try LocalOperationCache.decoded(from: data)
    }

    @discardableResult
    public func save(_ cache: LocalOperationCache, at date: Date) throws -> LocalOperationCache {
        var cacheToSave = cache
        cacheToSave.save(at: date)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try cacheToSave.encoded().write(to: fileURL, options: [.atomic])
        return cacheToSave
    }
}

public struct OfflineSyncCoordinator<Transport: SyncTransportClient>: Sendable {
    public var store: FileBackedLocalOperationCacheStore
    public var transport: Transport
    public var device: DeviceIdentity
    public var policy: BackgroundSyncPolicy

    public init(
        store: FileBackedLocalOperationCacheStore,
        transport: Transport,
        device: DeviceIdentity,
        policy: BackgroundSyncPolicy = BackgroundSyncPolicy()
    ) {
        self.store = store
        self.transport = transport
        self.device = device
        self.policy = policy
    }

    public func recoverAndSync(connectivity: ConnectivityState, trigger: OfflineSyncTrigger, now: Date) async throws -> OfflineSyncResult {
        try await flushPending(connectivity: connectivity, trigger: trigger, now: now)
    }

    public func plan(connectivity: ConnectivityState, trigger: OfflineSyncTrigger, now: Date) throws -> OfflineSyncPlan {
        var cache = try store.load()
        cache.markConnectivity(connectivity)
        let retryInterval = trigger == .manualRetry ? 0 : policy.minimumRetryInterval
        var plan = cache.makeSyncPlan(limit: policy.batchLimit, now: now, minimumRetryInterval: retryInterval)
        if policy.allowsSync(connectivity: connectivity, trigger: trigger) == false {
            plan.shouldAttemptSync = false
            plan.reason = "sync not allowed for \(connectivity.rawValue) connectivity"
        }
        return plan
    }

    public func flushPending(connectivity: ConnectivityState, trigger: OfflineSyncTrigger, now: Date) async throws -> OfflineSyncResult {
        var cache = try store.load()
        cache.markConnectivity(connectivity)
        let retryInterval = trigger == .manualRetry ? 0 : policy.minimumRetryInterval
        let plan = cache.makeSyncPlan(limit: policy.batchLimit, now: now, minimumRetryInterval: retryInterval)
        guard plan.shouldAttemptSync, policy.allowsSync(connectivity: connectivity, trigger: trigger) else {
            _ = try store.save(cache, at: now)
            return OfflineSyncResult(
                attempted: false,
                trigger: trigger,
                connectivity: connectivity,
                remainingPendingCount: cache.pendingCount,
                completedAt: now
            )
        }

        let envelopes = cache.pendingEnvelopes(limit: policy.batchLimit, now: now, minimumRetryInterval: retryInterval)
        for envelope in envelopes {
            cache.markSending(envelope.id, at: now)
        }
        _ = try store.save(cache, at: now)

        do {
            let response = try await transport.deliver(envelopes, from: device, at: now)
            let receiptsByID = Dictionary(uniqueKeysWithValues: response.receipts.map { ($0.envelopeID, $0) })
            var deliveredIDs: [LinkGuardID] = []
            var failedIDs: [LinkGuardID] = []

            for envelope in envelopes {
                guard let receipt = receiptsByID[envelope.id], receipt.accepted else {
                    cache.markFailed(envelope.id, error: receiptsByID[envelope.id]?.error ?? "missing transport receipt", at: now)
                    failedIDs.append(envelope.id)
                    continue
                }
                cache.markDelivered(envelope.id, at: receipt.receivedAt ?? now)
                deliveredIDs.append(envelope.id)
            }

            _ = try store.save(cache, at: now)
            return OfflineSyncResult(
                attempted: true,
                trigger: trigger,
                connectivity: connectivity,
                deliveredEnvelopeIDs: deliveredIDs,
                failedEnvelopeIDs: failedIDs,
                remainingPendingCount: cache.pendingCount,
                completedAt: now
            )
        } catch {
            for envelope in envelopes {
                cache.markFailed(envelope.id, error: String(describing: error), at: now)
            }
            _ = try store.save(cache, at: now)
            throw error
        }
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

    public mutating func markSending(_ messageID: LinkGuardID, at attemptTime: Date) {
        outboundQueue.markSending(messageID: messageID, at: attemptTime)
        lastSavedAt = attemptTime
    }

    public mutating func markFailed(_ messageID: LinkGuardID, error: String, at failedAt: Date) {
        outboundQueue.markFailed(messageID: messageID, error: error)
        lastSavedAt = failedAt
    }

    public func pendingEnvelopes(limit: Int? = nil, now: Date? = nil, minimumRetryInterval: TimeInterval = 0) -> [SyncEnvelope] {
        let entries = outboundQueue.entries.filter { entry in
            isPending(entry) && isRetryEligible(entry, now: now, minimumRetryInterval: minimumRetryInterval)
        }
        return Array(entries.prefix(limit ?? Int.max).map(\.envelope))
    }

    public func makeSyncPlan(limit: Int? = nil, now: Date? = nil, minimumRetryInterval: TimeInterval = 0) -> OfflineSyncPlan {
        let pendingIDs = pendingEnvelopes(limit: limit, now: now, minimumRetryInterval: minimumRetryInterval).map(\.id)
        let hasBlockedRetry = pendingIDs.isEmpty && outboundQueue.entries.contains { entry in
            isPending(entry) && isRetryEligible(entry, now: now, minimumRetryInterval: minimumRetryInterval) == false
        }
        switch connectivity {
        case .online:
            return OfflineSyncPlan(
                connectivity: connectivity,
                shouldAttemptSync: pendingIDs.isEmpty == false,
                pendingEnvelopeIDs: pendingIDs,
                reason: pendingIDs.isEmpty ? (hasBlockedRetry ? "waiting for retry interval" : "no pending envelopes") : "online with pending envelopes"
            )
        case .degraded:
            return OfflineSyncPlan(
                connectivity: connectivity,
                shouldAttemptSync: pendingIDs.isEmpty == false,
                pendingEnvelopeIDs: pendingIDs,
                reason: pendingIDs.isEmpty ? (hasBlockedRetry ? "degraded network waiting for retry interval" : "degraded network with empty queue") : "degraded network; sync critical queue first"
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

    private func isPending(_ entry: OfflineQueueEntry) -> Bool {
        entry.state == .queued || entry.state == .failed
    }

    private func isRetryEligible(_ entry: OfflineQueueEntry, now: Date?, minimumRetryInterval: TimeInterval) -> Bool {
        guard entry.state == .failed, minimumRetryInterval > 0, let now else { return true }
        guard let lastAttemptAt = entry.lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= minimumRetryInterval
    }
}