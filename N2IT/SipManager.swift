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
            onAccountRegistrationStateChanged: { [weak self] (_, _, state, msg) in self?.regChanged(state, msg) },
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
            }
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
        mwiSub?.addCustomHeader(headerName: "Accept", headerValue: "application/simple-message-summary")
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
    func hangupSip() { try? core.currentCall?.terminate() }
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
                CallKitManager.shared.sipEnded()
                self.activeCall = nil
                self.speaker = false
                self.muted = false
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
        }
    }
}
