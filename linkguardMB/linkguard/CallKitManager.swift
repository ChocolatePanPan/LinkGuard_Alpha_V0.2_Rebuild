import Foundation

#if os(iOS) && canImport(CallKit)
import AVFoundation
import CallKit

@MainActor
final class CallKitManager: NSObject {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onSetMuted: ((String, Bool) -> Void)?
    var onAudioSessionActivated: ((AVAudioSession) -> Void)?
    var onAudioSessionDeactivated: ((AVAudioSession) -> Void)?

    private let provider: CXProvider
    private let controller = CXCallController()
    private var uuidByCallID: [String: UUID] = [:]
    private var callIDByUUID: [UUID: String] = [:]
    private var outgoingCallIDs: Set<String> = []

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "LinkGuard")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(_ invite: CallInvite, completion: ((Bool) -> Void)? = nil) {
        let callUUID = uuid(for: invite.callID)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: invite.initiatorName)
        update.localizedCallerName = invite.initiatorName
        update.hasVideo = false
        update.supportsDTMF = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: callUUID, update: update) { error in
            if let error {
                print("[CallKit] report incoming failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion?(error == nil)
            }
        }
    }

    func startOutgoingCall(_ invite: CallInvite, calleeName: String) {
        let callUUID = uuid(for: invite.callID)
        outgoingCallIDs.insert(invite.callID)

        let handle = CXHandle(type: .generic, value: calleeName)
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = false

        controller.request(CXTransaction(action: action)) { [weak self] error in
            if let error {
                print("[CallKit] start outgoing failed: \(error.localizedDescription)")
                return
            }
            Task { @MainActor in
                self?.provider.reportOutgoingCall(with: callUUID, startedConnectingAt: Date())
            }
        }
    }

    func answerIncomingCall(callID: String, completion: ((Bool) -> Void)? = nil) {
        let callUUID = uuid(for: callID)
        let action = CXAnswerCallAction(call: callUUID)
        controller.request(CXTransaction(action: action)) { error in
            if let error {
                print("[CallKit] answer call failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion?(error == nil)
            }
        }
    }

    func reportConnected(callID: String) {
        guard outgoingCallIDs.contains(callID),
              let callUUID = uuidByCallID[callID] else { return }
        provider.reportOutgoingCall(with: callUUID, connectedAt: Date())
    }

    func reportEnded(callID: String, status: CallStatus) {
        guard let callUUID = uuidByCallID[callID] else { return }
        provider.reportCall(with: callUUID, endedAt: Date(), reason: endedReason(for: status))
        forget(callID: callID)
    }

    func invalidate() {
        provider.invalidate()
        reset()
    }

    private func uuid(for callID: String) -> UUID {
        if let existing = uuidByCallID[callID] { return existing }
        let callUUID = UUID(uuidString: callID) ?? UUID()
        uuidByCallID[callID] = callUUID
        callIDByUUID[callUUID] = callID
        return callUUID
    }

    private func callID(for callUUID: UUID) -> String? {
        callIDByUUID[callUUID]
    }

    private func endedReason(for status: CallStatus) -> CXCallEndedReason {
        switch status {
        case .missed:
            return .unanswered
        case .declined:
            return .declinedElsewhere
        case .active, .ringing, .ended:
            return .remoteEnded
        }
    }

    private func forget(callID: String) {
        guard let callUUID = uuidByCallID[callID] else { return }
        uuidByCallID.removeValue(forKey: callID)
        callIDByUUID.removeValue(forKey: callUUID)
        outgoingCallIDs.remove(callID)
    }

    private func reset() {
        uuidByCallID.removeAll()
        callIDByUUID.removeAll()
        outgoingCallIDs.removeAll()
    }
}

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.reset()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            guard let callID = self.callID(for: action.callUUID) else {
                action.fail()
                return
            }
            self.onAnswer?(callID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            guard let callID = self.callID(for: action.callUUID) else {
                action.fulfill()
                return
            }
            self.onEnd?(callID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            guard let callID = self.callID(for: action.callUUID) else {
                action.fail()
                return
            }
            self.onSetMuted?(callID, action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.onAudioSessionActivated?(audioSession)
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.onAudioSessionDeactivated?(audioSession)
        }
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fail()
    }
}
#endif