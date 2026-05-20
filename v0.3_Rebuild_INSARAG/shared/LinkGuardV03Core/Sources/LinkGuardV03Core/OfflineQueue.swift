import Foundation

public struct OfflineQueue: Codable, Sendable {
    public private(set) var entries: [OfflineQueueEntry]

    public init(entries: [OfflineQueueEntry] = []) {
        self.entries = entries.sorted(by: Self.sortEntries)
    }

    public mutating func enqueue(_ envelope: SyncEnvelope, queuedAt: Date) {
        guard entries.contains(where: { $0.envelope.idempotencyKey == envelope.idempotencyKey }) == false else {
            return
        }
        entries.append(OfflineQueueEntry(envelope: envelope, queuedAt: queuedAt))
        entries.sort(by: Self.sortEntries)
    }

    public mutating func markSending(messageID: LinkGuardID, at attemptTime: Date) {
        guard let entryIndex = entries.firstIndex(where: { $0.envelope.id == messageID }) else { return }
        entries[entryIndex].state = .sending
        entries[entryIndex].attempts += 1
        entries[entryIndex].lastAttemptAt = attemptTime
    }

    public mutating func markDelivered(messageID: LinkGuardID) {
        guard let entryIndex = entries.firstIndex(where: { $0.envelope.id == messageID }) else { return }
        entries[entryIndex].state = .delivered
    }

    public mutating func markFailed(messageID: LinkGuardID, error: String) {
        guard let entryIndex = entries.firstIndex(where: { $0.envelope.id == messageID }) else { return }
        entries[entryIndex].state = .failed
        entries[entryIndex].lastError = error
    }

    public mutating func removeDelivered() {
        entries.removeAll { $0.state == .delivered || $0.state == .superseded }
    }

    public var nextPending: OfflineQueueEntry? {
        entries.first { $0.state == .queued || $0.state == .failed }
    }

    private static func sortEntries(lhs: OfflineQueueEntry, rhs: OfflineQueueEntry) -> Bool {
        if lhs.envelope.priority != rhs.envelope.priority {
            return lhs.envelope.priority > rhs.envelope.priority
        }
        return lhs.queuedAt < rhs.queuedAt
    }
}
