import Foundation
import CallKit
import AVFoundation
import linphonesw

/// Bridges calls to iOS CallKit so incoming calls ring on the lock screen,
/// and so the audio session stays alive in the background.
final class CallKitManager: NSObject, CXProviderDelegate {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let controller = CXCallController()

    /// UUID of the single call CallKit currently knows about.
    private(set) var uuid: UUID?
    /// Answer tapped on the lock screen before the SIP INVITE arrived.
    private var answerWhenInvite = false
    private var pendingTimeout: DispatchWorkItem?

    private override init() {
        let cfg = CXProviderConfiguration()
        cfg.supportsVideo = false
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.generic, .phoneNumber]
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: Reporting

    /// Called from a VoIP push. Must report to CallKit immediately or iOS kills the app.
    func reportPushIncoming(caller: String, completion: (() -> Void)? = nil) {
        guard uuid == nil else { completion?(); return }
        let id = UUID()
        uuid = id
        report(id, caller: caller, completion: completion)
        // If the INVITE never arrives (caller hung up, network), drop the fake call.
        let work = DispatchWorkItem { [weak self] in self?.endIfPending() }
        pendingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    /// Called when Linphone sees the INVITE. Reuses the push's CallKit call if there is one.
    func sipIncoming(caller: String) {
        pendingTimeout?.cancel()
        if uuid == nil {
            let id = UUID()
            uuid = id
            report(id, caller: caller, completion: nil)
        } else if answerWhenInvite {
            answerWhenInvite = false
            SipManager.shared.answerSip()
        }
    }

    private func report(_ id: UUID, caller: String, completion: (() -> Void)?) {
        let u = CXCallUpdate()
        u.remoteHandle = CXHandle(type: .generic, value: caller)
        u.localizedCallerName = caller
        u.hasVideo = false
        provider.reportNewIncomingCall(with: id, update: u) { _ in completion?() }
    }

    private func endIfPending() {
        guard let id = uuid, SipManager.shared.activeCall == nil else { return }
        provider.reportCall(with: id, endedAt: nil, reason: .remoteEnded)
        uuid = nil
    }

    func sipConnected() {
        if let id = uuid { provider.reportOutgoingCall(with: id, connectedAt: nil) }
    }

    func sipEnded() {
        pendingTimeout?.cancel()
        answerWhenInvite = false
        guard let id = uuid else { return }
        provider.reportCall(with: id, endedAt: nil, reason: .remoteEnded)
        uuid = nil
    }

    // MARK: Requests from the app UI

    func startCall(_ number: String) {
        let id = UUID()
        uuid = id
        let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: number))
        controller.request(CXTransaction(action: action)) { [weak self] err in
            if err != nil { self?.uuid = nil }
        }
    }

    func requestAnswer() { if let id = uuid { controller.request(CXTransaction(action: CXAnswerCallAction(call: id)), completion: { _ in }) } }
    func requestEnd() { if let id = uuid { controller.request(CXTransaction(action: CXEndCallAction(call: id)), completion: { _ in }) } }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        SipManager.shared.hangupSip()
        uuid = nil
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        SipManager.shared.invite(action.handle.value)
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if SipManager.shared.hasIncomingSip { SipManager.shared.answerSip() }
        else { answerWhenInvite = true }   // woken by push; INVITE still on its way
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        SipManager.shared.hangupSip()
        pendingTimeout?.cancel()
        answerWhenInvite = false
        uuid = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        SipManager.shared.setMuted(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        SipManager.shared.audioSession(active: true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        SipManager.shared.audioSession(active: false)
    }
}
