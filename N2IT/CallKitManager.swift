import Foundation
import CallKit
import AVFoundation
import WebRTC

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
    /// Caller number of the push call CallKit is showing before its INVITE has arrived.
    private var pushCaller: String?
    /// Declined on the lock screen before the INVITE arrived: (caller from the push, until). The late INVITE is
    /// answered 603 without ringing, so the PBX carries on with the other phones or voicemail.
    private var declinedBeforeInvite: (caller: String, until: Date)?

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
    func reportPushIncoming(caller: String, number: String? = nil, completion: (() -> Void)? = nil) {
        guard uuid == nil else {
            // The INVITE got here first (app open and registered; the PBX pushes anyway). iOS still requires every VoIP
            // push to be reported as a call, or it may terminate the app: report a throwaway call and end it at once.
            let id = UUID()
            report(id, caller: caller) { [weak self] in
                self?.provider.reportCall(with: id, endedAt: nil, reason: .answeredElsewhere)
                completion?()
            }
            return
        }
        let id = UUID()
        uuid = id
        pushCaller = number ?? caller
        report(id, caller: caller, completion: completion)
        // If the INVITE never arrives (caller hung up, network), drop the fake call.
        let work = DispatchWorkItem { [weak self] in self?.endIfPending() }
        pendingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    /// A push while Do Not Disturb is on: iOS still requires it to be reported to CallKit, so report it and end it
    /// straight away. The SIP INVITE that follows is declined with 486 (SipManager), so the caller goes to voicemail.
    func reportPushDeclined(caller: String, completion: (() -> Void)? = nil) {
        let id = UUID()
        report(id, caller: caller) { [weak self] in
            self?.provider.reportCall(with: id, endedAt: nil, reason: .declinedElsewhere)
            completion?()
        }
    }

    /// Called when the SIP client sees the INVITE. Reuses the push's CallKit call if there is one.
    func sipIncoming(caller: String, name: String?) {
        pendingTimeout?.cancel()
        pushCaller = nil
        if uuid == nil {
            let id = UUID()
            uuid = id
            report(id, caller: caller, name: name, completion: nil)
            return
        }
        // Rung by a push first: the INVITE has the caller's name, the push may not.
        if let id = uuid {
            let u = CXCallUpdate()
            u.remoteHandle = CXHandle(type: .generic, value: caller)
            u.localizedCallerName = name ?? caller
            provider.reportCall(with: id, updated: u)
        }
        if answerWhenInvite {
            answerWhenInvite = false
            SipManager.shared.answerSip()
        }
    }

    private func report(_ id: UUID, caller: String, name: String? = nil, completion: (() -> Void)?) {
        let u = CXCallUpdate()
        u.remoteHandle = CXHandle(type: .generic, value: caller)
        u.localizedCallerName = name ?? SipManager.shared.name(for: caller) ?? caller
        u.hasVideo = false
        u.supportsHolding = true
        provider.reportNewIncomingCall(with: id, update: u) { _ in completion?() }
    }

    private func endIfPending() {
        pushCaller = nil
        guard let id = uuid, SipManager.shared.activeCall == nil else { return }
        provider.reportCall(with: id, endedAt: nil, reason: .remoteEnded)
        uuid = nil
    }

    func sipConnected() {
        if let id = uuid { provider.reportOutgoingCall(with: id, connectedAt: nil) }
    }

    func sipEnded() {
        pushCaller = nil
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

    /// The app's own Answer button. Goes through CallKit (so iOS hands us the audio); if CallKit refuses or has no call
    /// (0.3.0 test 2026-10-22: the button did nothing), answer the SIP call directly and say why in Last call problem.
    func requestAnswer() {
        guard let id = uuid else {
            SipManager.shared.problemNote("Answer: CallKit had no call, answered directly")
            configureAudio(); SipManager.shared.answerSip(); return
        }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: id))) { err in
            guard let err else { return }
            DispatchQueue.main.async {
                SipManager.shared.problemNote("Answer: CallKit refused (\(err.localizedDescription)), answered directly")
                self.configureAudio(); SipManager.shared.answerSip()
            }
        }
    }

    /// Call audio mode for WebRTC, set again for every call: something else (ringtone, another app) may have changed it
    /// since start-up, and with the wrong mode the call has no audio.
    func configureAudio() {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        try? rtc.setCategory(AVAudioSession.Category.playAndRecord, with: [.allowBluetooth])
        try? rtc.setMode(AVAudioSession.Mode.voiceChat)
    }
    func requestEnd() { if let id = uuid { controller.request(CXTransaction(action: CXEndCallAction(call: id)), completion: { _ in }) } }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        if SipManager.shared.hasIncomingSip { SipManager.shared.problemNote("iOS reset the call system: the ringing call was declined") }
        SipManager.shared.hangupSip()
        uuid = nil
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        configureAudio()
        SipManager.shared.invite(action.handle.value)
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        let u = CXCallUpdate()
        u.remoteHandle = action.handle
        u.localizedCallerName = SipManager.shared.name(for: action.handle.value)
        u.hasVideo = false
        u.supportsHolding = true   // lets iOS offer "Hold & Accept" when a GSM/WhatsApp call comes in
        provider.reportCall(with: action.callUUID, updated: u)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        configureAudio()
        if SipManager.shared.hasIncomingSip { SipManager.shared.answerSip() }
        else { answerWhenInvite = true }   // woken by push; INVITE still on its way
        action.fulfill()
    }

    /// The INVITE from `number` belongs to a push call the user already declined: true once (then forgotten).
    /// Matched by the caller's digits; a push without a number matches any INVITE in the 30 s.
    func takeDeclinedBeforeInvite(_ number: String) -> Bool {
        guard let d = declinedBeforeInvite else { return false }
        guard d.until > Date() else { declinedBeforeInvite = nil; return false }
        func key(_ n: String) -> String { let x = n.filter(\.isNumber); return x.count >= 9 ? String(x.suffix(9)) : x }
        guard key(d.caller).isEmpty || key(d.caller) == key(number) else { return false }
        declinedBeforeInvite = nil
        return true
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // Push call ended before its INVITE: nothing to send to the PBX yet; decline the INVITE when it comes
        if !SipManager.shared.hasLiveSip, let caller = pushCaller {
            declinedBeforeInvite = (caller, Date().addingTimeInterval(30))
            dlog("declined before the INVITE (caller \(caller)): its INVITE gets 603")
        }
        pushCaller = nil
        // A ringing call ended from the iOS call screen is declined (603): note it, so a decline nobody pressed shows up
        if SipManager.shared.hasIncomingSip { SipManager.shared.problemNote("Declined from the iOS call screen (603)") }
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

    /// Keys pressed on the iOS call screen's own keypad (lock screen, or when the user opened that screen).
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        action.digits.forEach { SipManager.shared.sendDigit($0) }
        action.fulfill()
    }

    /// iOS holds our call when the user takes another call ("Hold & Accept"), and unholds it from the call UI.
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        SipManager.shared.systemHold(action.isOnHold)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        SipManager.shared.audioSession(active: true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        SipManager.shared.audioSession(active: false)
    }
}
