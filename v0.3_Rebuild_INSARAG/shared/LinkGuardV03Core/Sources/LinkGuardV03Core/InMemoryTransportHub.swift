import Foundation

public enum TransportDeliveryState: String, Codable, Sendable {
    case delivered
    case skippedByPolicy
    case sourceMissing
}

public struct TransportDeliveryReceipt: Codable, Hashable, Sendable {
    public var envelopeID: LinkGuardID
    public var recipientDeviceID: LinkGuardID
    public var recipientAppID: LinkGuardAppID
    public var state: TransportDeliveryState
    public var deliveredAt: Date

    public init(envelopeID: LinkGuardID, recipientDeviceID: LinkGuardID, recipientAppID: LinkGuardAppID, state: TransportDeliveryState, deliveredAt: Date) {
        self.envelopeID = envelopeID
        self.recipientDeviceID = recipientDeviceID
        self.recipientAppID = recipientAppID
        self.state = state
        self.deliveredAt = deliveredAt
    }
}

public final class InMemoryTransportHub {
    private var runtimesByDeviceID: [LinkGuardID: LinkGuardAppRuntime]

    public init(runtimes: [LinkGuardAppRuntime] = []) {
        self.runtimesByDeviceID = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.device.id, $0) })
    }

    public var registeredRuntimes: [LinkGuardAppRuntime] {
        runtimesByDeviceID.values.sorted { $0.device.appID.rawValue < $1.device.appID.rawValue }
    }

    public func register(_ runtime: LinkGuardAppRuntime) {
        runtimesByDeviceID[runtime.device.id] = runtime
    }

    public func runtime(for deviceID: LinkGuardID) -> LinkGuardAppRuntime? {
        runtimesByDeviceID[deviceID]
    }

    @discardableResult
    public func send<Payload: Encodable>(
        messageType: SyncMessageType,
        payload: Payload,
        from sourceDeviceID: LinkGuardID,
        priority: PriorityLevel? = nil,
        createdAt: Date,
        idempotencyKey: String? = nil,
        sourceRole: ICSPosition? = nil
    ) throws -> [TransportDeliveryReceipt] {
        guard var sourceRuntime = runtimesByDeviceID[sourceDeviceID] else {
            throw LinkGuardRuntimeError.deviceNotRegistered(sourceDeviceID)
        }

        let envelope = try sourceRuntime.makeEnvelope(
            messageType: messageType,
            payload: payload,
            priority: priority,
            createdAt: createdAt,
            idempotencyKey: idempotencyKey,
            sourceRole: sourceRole
        )
        sourceRuntime.queueOutbound(envelope, queuedAt: createdAt)
        runtimesByDeviceID[sourceDeviceID] = sourceRuntime
        return try transmit(envelope, from: sourceDeviceID, deliveredAt: createdAt)
    }

    @discardableResult
    public func queueOffline<Payload: Encodable>(
        messageType: SyncMessageType,
        payload: Payload,
        from sourceDeviceID: LinkGuardID,
        priority: PriorityLevel? = nil,
        createdAt: Date,
        idempotencyKey: String? = nil,
        sourceRole: ICSPosition? = nil
    ) throws -> SyncEnvelope {
        guard var sourceRuntime = runtimesByDeviceID[sourceDeviceID] else {
            throw LinkGuardRuntimeError.deviceNotRegistered(sourceDeviceID)
        }

        let envelope = try sourceRuntime.queueOffline(
            messageType: messageType,
            payload: payload,
            priority: priority,
            createdAt: createdAt,
            idempotencyKey: idempotencyKey,
            sourceRole: sourceRole
        )
        runtimesByDeviceID[sourceDeviceID] = sourceRuntime
        return envelope
    }

    @discardableResult
    public func flushQueuedOutbound(for sourceDeviceID: LinkGuardID, deliveredAt: Date, limit: Int? = nil) throws -> [TransportDeliveryReceipt] {
        guard var sourceRuntime = runtimesByDeviceID[sourceDeviceID] else {
            throw LinkGuardRuntimeError.deviceNotRegistered(sourceDeviceID)
        }

        let pendingEntries = sourceRuntime.outboundQueue.entries
            .filter { $0.state == .queued || $0.state == .failed }
            .prefix(limit ?? Int.max)
        var receipts: [TransportDeliveryReceipt] = []

        for entry in pendingEntries {
            sourceRuntime.markOutboundSending(entry.envelope.id, at: deliveredAt)
            runtimesByDeviceID[sourceDeviceID] = sourceRuntime
            do {
                receipts.append(contentsOf: try transmit(entry.envelope, from: sourceDeviceID, deliveredAt: deliveredAt))
                sourceRuntime = runtimesByDeviceID[sourceDeviceID] ?? sourceRuntime
            } catch {
                if var failedRuntime = runtimesByDeviceID[sourceDeviceID] {
                    failedRuntime.markOutboundFailed(entry.envelope.id, error: String(describing: error))
                    runtimesByDeviceID[sourceDeviceID] = failedRuntime
                }
                throw error
            }
        }

        return receipts
    }

    @discardableResult
    public func transmit(_ envelope: SyncEnvelope, from sourceDeviceID: LinkGuardID, deliveredAt: Date) throws -> [TransportDeliveryReceipt] {
        guard runtimesByDeviceID[sourceDeviceID] != nil else {
            throw LinkGuardRuntimeError.deviceNotRegistered(sourceDeviceID)
        }

        let route = TransportTopology.route(for: envelope)
        var receipts: [TransportDeliveryReceipt] = []

        for deviceID in runtimesByDeviceID.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var runtime = runtimesByDeviceID[deviceID] else { continue }
            guard route.allowedRecipientApps.contains(runtime.device.appID) else { continue }
            try runtime.receive(envelope)
            runtimesByDeviceID[deviceID] = runtime
            receipts.append(
                TransportDeliveryReceipt(
                    envelopeID: envelope.id,
                    recipientDeviceID: deviceID,
                    recipientAppID: runtime.device.appID,
                    state: .delivered,
                    deliveredAt: deliveredAt
                )
            )
        }

        if var sourceRuntime = runtimesByDeviceID[sourceDeviceID] {
            sourceRuntime.markOutboundDelivered(envelope.id)
            runtimesByDeviceID[sourceDeviceID] = sourceRuntime
        }

        return receipts
    }
}
