import Foundation
import linphonesw
import AVFoundation

struct CallInfo: Identifiable {
    let id = UUID()
    let number: String
    let state: Call.State
    let incoming: Bool
}

struct RecentCall: Identifiable {
    let id = UUID()
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
    @Published var recents: [RecentCall] = []
    @Published var newVoicemails = 0
    @Published var oldVoicemails = 0

    private var core: Core!
    private var delegate: CoreDelegateStub!

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
        guard let c = try? Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil) else { return }
        core = c
        core.pushNotificationEnabled = false   // we use our own PushKit gateway, not Linphone's flexisip push
        core.callkitEnabled = true
        delegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] (_, call, state, _) in self?.callChanged(call, state) },
            onAccountRegistrationStateChanged: { [weak self] (_, _, state, msg) in self?.regChanged(state, msg) },
            onMessageWaitingIndicationChanged: { [weak self] (_, _, mwi) in
                let v = mwi.getSummary(contextClass: .Voice)
                DispatchQueue.main.async {
                    self?.newVoicemails = Int(v?.nbNew ?? 0)
                    self?.oldVoicemails = Int(v?.nbOld ?? 0)
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
            // Subscribe to message-waiting (MWI) NOTIFYs for the voicemail badge.
            try params.setMwiserveraddress(newValue: params.identityAddress)
            let account = try core.createAccount(params: params)
            core.addAuthInfo(info: auth)
            try core.addAccount(account: account)
            core.defaultAccount = account
        } catch {
            registration = "Config error: \(error.localizedDescription)"
        }
    }

    private func regChanged(_ state: RegistrationState, _ msg: String) {
        DispatchQueue.main.async {
            self.registered = state == .Ok
            switch state {
            case .Ok: self.registration = "Registered"
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

    func audioSession(active: Bool) { core?.activateAudioSession(actived: active) }
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
                    let missed = incoming && call.log?.status == .Missed
                    self.recents.insert(RecentCall(number: number, date: Date(), incoming: incoming, missed: missed), at: 0)
                }
            default:
                self.activeCall = CallInfo(number: number, state: state, incoming: incoming)
            }
        }
    }
}
