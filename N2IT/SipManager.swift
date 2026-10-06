import Foundation
import linphonesw
import AVFoundation

struct CallInfo: Identifiable {
    let id = UUID()
    let number: String
    let state: Call.State
    let incoming: Bool
}

struct RecentCall: Identifiable, Codable {
    var id = UUID()
    let number: String
    let date: Date
    let incoming: Bool
    let missed: Bool
}

final class SipManager: ObservableObject {
    static let shared = SipManager()

    @Published var registration = "Not registered"
    @Published var registered = false
    @Published var activeCall: CallInfo?
    @Published var muted = false
    @Published var speaker = false
    @Published var recents: [RecentCall] = [] { didSet { saveRecents() } }
    @Published var newVoicemails = 0
    @Published var hasVoicemail = false

    private var core: Core!
    private var delegate: CoreDelegateStub!

    private func saveRecents() {
        if let d = try? JSONEncoder().encode(Array(recents.prefix(100))) { UserDefaults.standard.set(d, forKey: "recents") }
    }

    /// Forget the account: unregister push, drop SIP account, clear stored data.
    func signOut() {
        PushManager.shared.unregister()
        core?.clearAccounts()
        core?.clearAllAuthInfo()
        Account.clear()
        recents = []
        registered = false
        registration = "Not registered"
        newVoicemails = 0; hasVoicemail = false
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: "recents"),
           let r = try? JSONDecoder().decode([RecentCall].self, from: d) { recents = r }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
        guard let c = try? Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil) else { return }
        core = c
        core.pushNotificationEnabled = false   // we use our own PushKit gateway, not Linphone's flexisip push
        core.callkitEnabled = true
        delegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] (_, call, state, _) in self?.callChanged(call, state) },
            onNotifyReceived: { [weak self] (_, _, name, body) in
                guard name.lowercased() == "message-summary", let text = body?.utf8Text else { return }
                let waiting = text.range(of: "Messages-Waiting:\\s*yes", options: [.regularExpression, .caseInsensitive]) != nil
                var count = 0
                if let r = text.range(of: "Voice-Message:\\s*\\d+", options: [.regularExpression, .caseInsensitive]) {
                    count = Int(text[r].filter(\.isNumber)) ?? 0
                }
                DispatchQueue.main.async {
                    self?.newVoicemails = count
                    self?.hasVoicemail = waiting || count > 0
                }
            },
            onAccountRegistrationStateChanged: { [weak self] (_, _, state, msg) in self?.regChanged(state, msg) }
        )
        core.addDelegate(delegate: delegate)
        try? core.start()
        configure(Account.load())
        PushManager.shared.start()
    }

    // MARK: Account

    func configure(_ acc: Account) {
        guard let core, !acc.user.isEmpty else { return }
        core.clearAccounts()
        core.clearAllAuthInfo()
        do {
            let auth = try Factory.Instance.createAuthInfo(username: acc.user, userid: "", passwd: acc.password,
                                                           ha1: "", realm: "", domain: acc.domain)
            let params = try core.createAccountParams()
            try params.setIdentityaddress(newValue: Factory.Instance.createAddress(addr: "sip:\(acc.user)@\(acc.domain)"))
            let server = try Factory.Instance.createAddress(addr: "sip:\(acc.domain):\(acc.port)")
            try server.setTransport(newValue: acc.transport.linphone)
            try params.setServeraddress(newValue: server)
            try core.setMediaencryption(newValue: acc.srtp ? .SRTP : .None)
            core.mediaEncryptionMandatory = acc.srtp
            params.registerEnabled = true
            let account = try core.createAccount(params: params)
            core.addAuthInfo(info: auth)
            try core.addAccount(account: account)
            core.defaultAccount = account
        } catch {
            registration = "Config error: \(error.localizedDescription)"
        }
    }

    private var mwiSub: Event?

    /// Manual SUBSCRIBE for voicemail (message-waiting) notifications.
    private func subscribeVoicemail() {
        guard let addr = core.defaultAccount?.params?.identityAddress else { return }
        mwiSub?.terminate()
        mwiSub = try? core.createSubscribe(resource: addr, event: "message-summary", expires: 3600)
        mwiSub?.addCustomHeader(name: "Accept", value: "application/simple-message-summary")
        try? mwiSub?.sendSubscribe(body: nil)
    }

    private func regChanged(_ state: RegistrationState, _ msg: String) {
        DispatchQueue.main.async {
            self.registered = state == .Ok
            switch state {
            case .Ok: self.registration = "Registered"; self.subscribeVoicemail()
            case .Progress: self.registration = "Registering…"
            case .Failed: self.registration = "Failed: \(msg)"
            default: self.registration = "Not registered"
            }
        }
    }

    // MARK: Calls

    // UI entry points go through CallKit; CallKitManager calls the *Sip methods below.
    func call(_ number: String) { if !number.isEmpty { CallKitManager.shared.startCall(number) } }
    func answer() { CallKitManager.shared.requestAnswer() }
    func hangup() { CallKitManager.shared.requestEnd() }

    func invite(_ number: String) {
        guard let core, let acc = core.defaultAccount else { return }
        let domain = acc.params?.identityAddress?.domain ?? ""
        _ = core.invite(url: number.contains("@") ? "sip:\(number)" : "sip:\(number)@\(domain)")
    }
    func answerSip() { try? core.currentCall?.accept() }
    /// Ends the call in front of the user; in a conference with nobody else ringing, ends it for everyone.
    func hangupSip() {
        if let c = core.currentCall, c.conference == nil { try? c.terminate(); return }
        if let conf = conference { _ = try? conf.terminate() } else { try? liveCalls().first?.terminate() }
    }
    var hasIncomingSip: Bool { core?.currentCall?.state == .IncomingReceived }

    /// Re-register after a VoIP push woke the app.
    func wake() { core?.refreshRegisters() }

    func audioSession(active: Bool) { core?.activateAudioSession(activated: active) }
    func setMuted(_ m: Bool) { core.micEnabled = !m; DispatchQueue.main.async { self.muted = m } }
    func sendDigit(_ d: Character) { try? core.currentCall?.sendDtmf(dtmf: CChar(d.asciiValue ?? 48)) }

    func toggleMute() {
        core.micEnabled.toggle()
        muted = !core.micEnabled
    }

    // MARK: Hold and transfer

    @Published var onHold = false
    @Published var consulting = false
    @Published var inConference = false
    @Published var participants: [String] = []

    private func liveCalls(except: Call? = nil) -> [Call] {
        (core?.calls ?? []).filter { $0 !== except && ![.End, .Error, .Released].contains($0.state) }
    }
    private var conference: Conference? { liveCalls().compactMap { $0.conference }.first }

    /// Add participant, step 1: in a conference, invite `number` straight in; otherwise hold the call and ring
    /// `number` (same as a consult), then `merge()` once they answer.
    func addParticipant(_ number: String) {
        guard let core, let domain = core.defaultAccount?.params?.identityAddress?.domain else { return }
        if let conf = conference {
            guard let target = try? Factory.Instance.createAddress(addr: number.contains("@") ? "sip:\(number)" : "sip:\(number)@\(domain)")
            else { return }
            _ = try? conf.addParticipant(URI: target)
        } else { consult(number) }
    }

    /// Add participant, step 2: join every call into one conference, mixed on this phone (no PBX bridge needed).
    func merge() {
        guard let core else { return }
        let calls = liveCalls()
        guard calls.count > 1 else { return }
        var conf = conference
        if conf == nil, let params = try? core.createConferenceParams(conference: nil) {
            params.videoEnabled = false
            params.localParticipantEnabled = true
            conf = try? core.createConferenceWithParams(params: params)
        }
        guard let conf else { return }
        for c in calls where c.conference == nil { _ = try? conf.addParticipant(call: c) }
    }

    func toggleHold() {
        guard let core else { return }
        if let c = core.calls.first(where: { $0.state == .Paused }) { userHeld.removeAll { $0 === c }; try? c.resume() }
        else if let c = core.currentCall { userHeld.append(c); try? c.pause() }
    }

    /// Calls the user held themselves; `systemHold(false)` leaves these on hold.
    private var userHeld: [Call] = []

    /// CallKit hold/unhold, e.g. the user took a GSM or WhatsApp call with "Hold & Accept". Holding makes the
    /// PBX play hold music; resuming restarts the audio streams.
    func systemHold(_ on: Bool) {
        if let conf = conference {
            _ = on ? try? conf.leave() : try? conf.enter()
            return
        }
        for c in liveCalls() {
            if on, c.state == .StreamsRunning { try? c.pause() }
            if !on, c.state == .Paused, !userHeld.contains(where: { $0 === c }) { try? c.resume() }
        }
    }

    /// Blind transfer: hand the current call to `number` and drop out.
    func blindTransfer(_ number: String) {
        guard let core, let call = core.currentCall ?? core.calls.first,
              let domain = core.defaultAccount?.params?.identityAddress?.domain,
              let target = try? Factory.Instance.createAddress(addr: number.contains("@") ? "sip:\(number)" : "sip:\(number)@\(domain)")
        else { return }
        try? call.transferTo(referTo: target)
    }

    /// Attended transfer, step 1: hold the caller and ring `number`.
    func consult(_ number: String) {
        try? core.currentCall?.pause()
        invite(number)
    }

    /// Attended transfer, step 2: connect the held caller to the consulted party.
    func completeTransfer() {
        guard let held = core.calls.first(where: { $0.state == .Paused }),
              let other = core.calls.first(where: { $0 !== held }) else { return }
        try? held.transferToAnother(dest: other)
    }

    func toggleSpeaker() {
        speaker.toggle()
        let wanted: AudioDevice.Kind = speaker ? .Speaker : .Earpiece
        if let dev = core.audioDevices.first(where: { $0.type == wanted }) {
            core.outputAudioDevice = dev
        }
    }

    private func callChanged(_ call: Call, _ state: Call.State) {
        DispatchQueue.main.async {
            let number = call.remoteAddress?.username ?? "Unknown"
            let incoming = call.dir == .Incoming
            switch state {
            case .IncomingReceived:
                CallKitManager.shared.sipIncoming(caller: number)
                self.activeCall = CallInfo(number: number, state: state, incoming: true)
            case .End, .Error, .Released:
                self.userHeld.removeAll { $0 === call }
                // Another call may still be up (held caller after a consult, or the rest of a conference).
                if let other = self.core.currentCall ?? self.liveCalls(except: call).first {
                    self.activeCall = CallInfo(number: other.remoteAddress?.username ?? "Unknown", state: other.state,
                                               incoming: other.dir == .Incoming)
                } else {
                    CallKitManager.shared.sipEnded()
                    self.activeCall = nil
                    self.speaker = false
                    self.muted = false
                }
                if state == .End || state == .Error {
                    let missed = incoming && call.callLog?.status == .Missed
                    self.recents.insert(RecentCall(number: number, date: Date(), incoming: incoming, missed: missed), at: 0)
                }
            case .StreamsRunning where !incoming:
                CallKitManager.shared.sipConnected()
                self.activeCall = CallInfo(number: number, state: state, incoming: incoming)
            default:
                self.activeCall = CallInfo(number: number, state: state, incoming: incoming)
            }
            let live = self.liveCalls()
            let members = live.filter { $0.conference != nil }
            self.inConference = !members.isEmpty
            self.participants = members.map { $0.remoteAddress?.username ?? "Unknown" }
            if self.inConference {
                self.activeCall = CallInfo(number: self.participants.joined(separator: ", "), state: .StreamsRunning, incoming: false)
                self.onHold = false
                self.consulting = live.contains { $0.conference == nil }
            } else {
                let shown = self.core.currentCall ?? live.first
                self.onHold = shown?.state == .Paused || shown?.state == .Pausing
                self.consulting = live.count > 1
            }
        }
    }
}
