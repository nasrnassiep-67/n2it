import Foundation
import linphonesw
import AVFoundation

struct CallInfo: Identifiable {
    let id = UUID()
    let number: String
    let state: Call.State
    let incoming: Bool
    /// Caller ID name from the PBX, or the contact's name; nil when unknown.
    var name: String? = nil
}

/// Where the call is heard and spoken: the iPhone itself, its loudspeaker, Bluetooth (car kit, headset) or a wired headset.
enum AudioRoute: Int, Comparable {
    case iPhone, speaker, bluetooth, headset
    static func < (a: AudioRoute, b: AudioRoute) -> Bool { a.rawValue < b.rawValue }
    var icon: String {
        switch self {
        case .iPhone: return "iphone"
        case .speaker: return "speaker.wave.3.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .headset: return "headphones"
        }
    }
}

/// One audio device the user can pick; `id` is Linphone's AudioDevice id.
struct AudioOption: Identifiable, Equatable {
    let id: String
    let route: AudioRoute
    let name: String
}

struct RecentCall: Identifiable, Codable {
    var id = UUID()
    let number: String
    let date: Date
    let incoming: Bool
    let missed: Bool
    var name: String? = nil
}

final class SipManager: ObservableObject {
    static let shared = SipManager()

    @Published var registration = "Not registered"
    @Published var registered = false
    @Published var activeCall: CallInfo?
    @Published var muted = false
    @Published var audioRoutes: [AudioOption] = []
    @Published var audioRoute: AudioOption?   // what iOS plays the call through right now
    @Published var recents: [RecentCall] = [] { didSet { saveRecents() } }
    @Published var newVoicemails = 0
    @Published var hasVoicemail = false

    /// "0.2.2", from MARKETING_VERSION in project.yml.
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    private var core: Core!
    private var delegate: CoreDelegateStub!

    private func saveRecents() {
        if let d = try? JSONEncoder().encode(Array(recents.prefix(100))) { UserDefaults.standard.set(d, forKey: "recents") }
    }

    /// Another saved account becomes active (`Account.activate` already stored it): only it registers and rings.
    func switchAccount(to acc: Account, from previous: Account) {
        if previous.isConfigured && !previous.sameAs(acc) { PushManager.shared.unregister(previous) }
        resetShown()
        registration = "Registering…"
        configure(acc)
        PushManager.shared.uploadToken()
    }

    /// Log out of `acc` and forget it on this phone. Logging out of the active account switches to the next one.
    /// Returns false when no account is left (back to the sign-in screen).
    func logOut(_ acc: Account) -> Bool {
        let active = Account.load()
        PushManager.shared.unregister(acc)
        guard let next = Account.remove(acc) else {
            core?.clearAccounts()
            core?.clearAllAuthInfo()
            resetShown()
            return false
        }
        if active.sameAs(acc) {
            resetShown()
            registration = "Registering…"
            configure(next)
            PushManager.shared.uploadToken()
        }
        return true
    }

    /// What was shown belongs to the previous account.
    private func resetShown() {
        recents = []
        registered = false
        registration = "Not registered"
        newVoicemails = 0; hasVoicemail = false
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: "recents"),
           let r = try? JSONDecoder().decode([RecentCall].self, from: d) { recents = r }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        guard let c = try? Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil) else { return }
        core = c
        core.pushNotificationEnabled = false   // we use our own PushKit gateway, not Linphone's flexisip push
        core.callkitEnabled = true
        // Shows on the PBX (registrations, logs) instead of "Unknown"; Android sends "N2IT Phone Android/<version>".
        core.setUserAgent(name: "N2IT Phone iOS", version: SipManager.appVersion)
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
            onAudioDevicesListUpdated: { [weak self] _ in DispatchQueue.main.async { self?.updateRoutes() } },
            onAccountRegistrationStateChanged: { [weak self] (_, _, state, msg) in self?.regChanged(state, msg) }
        )
        core.addDelegate(delegate: delegate)
        try? core.start()
        updateRoutes()
        // Also catches changes made outside the app: Control Centre, the iOS call screen, a car kit connecting.
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.readCurrentRoute()
        }
        let savedDnd = UserDefaults.standard.double(forKey: "dndUntil")
        setDnd(savedDnd > 0 ? Date(timeIntervalSince1970: savedDnd) : nil)   // survives restarts; clears itself if expired
        configure(Account.load())
        PushManager.shared.start()
    }

    // MARK: Caller names

    /// Contact names by number (company contacts from the PBX and the phone's own), filled by ContactsStore.
    private var knownNames: [String: String] = [:]

    /// Digits only; long numbers by their last 9 digits so "+27 82 123 4567" and "082 123 4567" match.
    private static func numberKey(_ n: String) -> String {
        let d = n.filter(\.isNumber)
        return d.count >= 9 ? String(d.suffix(9)) : d
    }

    func learnNames(_ contacts: [PhoneContact]) {
        for c in contacts where !c.name.isEmpty {
            for n in c.numbers { let k = Self.numberKey(n); if !k.isEmpty && knownNames[k] == nil { knownNames[k] = c.name } }
        }
    }

    func name(for number: String) -> String? { knownNames[Self.numberKey(number)] }

    /// The caller ID name the PBX sends (the extension's name for internal calls), else the contact's name.
    private func name(of call: Call) -> String? {
        let number = call.remoteAddress?.username ?? ""
        if let d = call.remoteAddress?.displayName?.trimmingCharacters(in: .whitespaces), !d.isEmpty, d != number { return d }
        return name(for: number)
    }

    // MARK: Do Not Disturb

    /// DND is always timed, at most 2 weeks (owner 2026-10-07). Per phone, not per account.
    static let maxDnd: TimeInterval = 14 * 24 * 3600
    /// End of DND, or nil when off.
    @Published private(set) var dndUntil: Date?
    private var dndTimer: Timer?
    /// Calls refused because of DND; they go in Recents as missed.
    private var dndRefused: [Call] = []

    var dndActive: Bool { (dndUntil ?? .distantPast) > Date() }

    /// Turn DND on until `until` (capped at 2 weeks from now), or off with nil or a time already past.
    func setDnd(_ until: Date?) {
        let now = Date()
        let u = until.map { min($0, now.addingTimeInterval(Self.maxDnd)) }.flatMap { $0 > now ? $0 : nil }
        UserDefaults.standard.set(u?.timeIntervalSince1970 ?? 0, forKey: "dndUntil")
        dndUntil = u
        dndTimer?.invalidate()
        if let u {
            dndTimer = Timer.scheduledTimer(withTimeInterval: u.timeIntervalSince(now), repeats: false) { [weak self] _ in
                self?.checkDnd()
            }
        }
    }

    /// Ends an expired DND. Timers don't run while the app is suspended, so this also runs on resume and on each call.
    func checkDnd() { if dndUntil != nil && !dndActive { setDnd(nil) } }

    // MARK: Account

    func configure(_ acc: Account) {
        guard let core, !acc.user.isEmpty else { return }
        core.clearAccounts()
        core.clearAllAuthInfo()
        var step = "auth"
        do {
            let auth = try Factory.Instance.createAuthInfo(username: acc.user, userid: "", passwd: acc.password,
                                                           ha1: "", realm: "", domain: acc.domain)
            step = "account params"
            let params = try core.createAccountParams()
            step = "identity"
            try params.setIdentityaddress(newValue: Factory.Instance.createAddress(addr: "sip:\(acc.user)@\(acc.domain)"))
            step = "server address"
            let server = try Factory.Instance.createAddress(addr: "sip:\(acc.domain):\(acc.port)")
            step = "transport"
            try server.setTransport(newValue: acc.transport.linphone)
            try params.setServeraddress(newValue: server)
            step = "media encryption"
            try core.setMediaencryption(newValue: acc.srtp ? .SRTP : .None)
            core.mediaEncryptionMandatory = false  // optional SRTP: still call peers that do not offer it
            params.registerEnabled = true
            // Re-register every 10 min (default 1 h) and keep the connection alive: a mobile network drops an idle
            // connection after a few minutes, and the PBX can only reach the phone over a live one (same as Android).
            params.expires = 600
            core.keepAliveEnabled = true
            step = "create account"
            let account = try core.createAccount(params: params)
            core.addAuthInfo(info: auth)
            step = "add account"
            try core.addAccount(account: account)
            core.defaultAccount = account
        } catch {
            registration = "Config error (\(step)): \(error)"
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

    func audioSession(active: Bool) {
        core?.activateAudioSession(activated: active)
        guard active else { return }
        updateRoutes()
        if wantedRoute == nil { wantedRoute = defaultRoute() }
        routePending = true
        applyRoute()
    }
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

    // MARK: Audio route

    /// Device picked for the calls in progress: the default when the first call starts, then the user's choice.
    /// Cleared when the last call ends, so each new call starts on the default route again.
    private var wantedRoute: String?
    /// Set when the audio session starts; the route is applied once more when the streams are up.
    private var routePending = false

    private func routeOf(_ d: AudioDevice) -> AudioRoute? {
        switch d.type {
        case .Earpiece: return .iPhone
        case .Microphone: return d.hasCapability(capability: .CapabilityPlay) ? .iPhone : nil   // some iOS versions list the receiver this way
        case .Speaker: return .speaker
        case .Bluetooth: return .bluetooth   // hands-free profile (car kits, headsets); A2DP is music-only
        case .Headset, .Headphones: return .headset
        default: return nil
        }
    }

    /// Bluetooth and headsets use their own microphone when they have one; otherwise the iPhone's.
    private func recorder(for d: AudioDevice) -> AudioDevice? {
        if routeOf(d) == .bluetooth || routeOf(d) == .headset, d.hasCapability(capability: .CapabilityRecord) { return d }
        let mics = core.audioDevices.filter { $0.hasCapability(capability: .CapabilityRecord) }
        return mics.first { $0.type == .Microphone } ?? mics.first { $0.type == .Earpiece }
    }

    private func updateRoutes() {
        guard let core else { return }
        let before = Set(audioRoutes.filter { $0.route == .bluetooth }.map(\.id))
        var seen = Set<String>()
        let devices = core.audioDevices.sorted { $0.type == .Earpiece && $1.type != .Earpiece }   // prefer the real receiver
        audioRoutes = devices.compactMap { d -> AudioOption? in
            guard let r = routeOf(d), d.hasCapability(capability: .CapabilityPlay),
                  seen.insert(r == .bluetooth ? d.id : "\(r)").inserted else { return nil }
            let name: String
            switch r {
            case .iPhone: name = "iPhone"
            case .speaker: name = "Speaker"
            case .bluetooth: name = d.deviceName
            case .headset: name = "Headset"
            }
            return AudioOption(id: d.id, route: r, name: name)
        }.sorted { $0.route < $1.route }
        // Bluetooth that connects during a call takes it over, as it does for a phone call.
        if wantedRoute != nil, let bt = audioRoutes.first(where: { $0.route == .bluetooth && !before.contains($0.id) }) {
            setAudioRoute(bt.id)
        }
        readCurrentRoute()
    }

    private func readCurrentRoute() {
        guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else { audioRoute = nil; return }
        let route: AudioRoute?
        switch out.portType {
        case .builtInReceiver: route = .iPhone
        case .builtInSpeaker: route = .speaker
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio: route = .bluetooth
        case .headphones, .usbAudio: route = .headset
        default: route = nil
        }
        audioRoute = audioRoutes.first { $0.route == route && (route != .bluetooth || $0.name == out.portName) }
            ?? audioRoutes.first { $0.route == route }
    }

    private func defaultRoute() -> String? {
        for r in [AudioRoute.bluetooth, .headset, .iPhone] {
            if let o = audioRoutes.first(where: { $0.route == r }) { return o.id }
        }
        return nil
    }

    /// Point every live call (and a conference) at the chosen device, both ways: speaker and microphone.
    private func applyRoute() {
        guard let core, let id = wantedRoute, let out = core.audioDevices.first(where: { $0.id == id }) else { return }
        let mic = recorder(for: out)
        // A running call keeps its own devices; the core setting only applies to calls started afterwards.
        core.outputAudioDevice = out; if let mic { core.inputAudioDevice = mic }
        for c in liveCalls() { c.outputAudioDevice = out; if let mic { c.inputAudioDevice = mic } }
        if let conf = conference { conf.outputAudioDevice = out; if let mic { conf.inputAudioDevice = mic } }
    }

    func setAudioRoute(_ id: String) {
        guard audioRoutes.contains(where: { $0.id == id }) else { return }
        wantedRoute = id
        applyRoute()
    }

    /// The audio button with only the iPhone and its loudspeaker to choose from.
    func toggleSpeaker() {
        let target: AudioRoute = audioRoute?.route == .speaker ? .iPhone : .speaker
        if let o = audioRoutes.first(where: { $0.route == target }) { setAudioRoute(o.id) }
    }

    private func callChanged(_ call: Call, _ state: Call.State) {
        DispatchQueue.main.async {
            let number = call.remoteAddress?.username ?? "Unknown"
            let incoming = call.dir == .Incoming
            let name = self.name(of: call)
            switch state {
            case .IncomingReceived:
                self.checkDnd()
                if self.dndActive {
                    // DND: refuse as busy; the PBX sends the caller to voicemail (or says there is none).
                    // Other phones on the same extension (e.g. a desk phone) keep ringing.
                    self.dndRefused.append(call)
                    try? call.decline(reason: .Busy)
                    return
                }
                CallKitManager.shared.sipIncoming(caller: number, name: name)
                self.activeCall = CallInfo(number: number, state: state, incoming: true, name: name)
            case .End, .Error, .Released:
                self.userHeld.removeAll { $0 === call }
                // Another call may still be up (held caller after a consult, or the rest of a conference).
                let refused = self.dndRefused.contains { $0 === call }
                if refused {
                    // Never shown: leave the call screen and CallKit as they are.
                    if state == .Released { self.dndRefused.removeAll { $0 === call } }
                } else if let other = self.core.currentCall ?? self.liveCalls(except: call).first {
                    self.activeCall = CallInfo(number: other.remoteAddress?.username ?? "Unknown", state: other.state,
                                               incoming: other.dir == .Incoming, name: self.name(of: other))
                } else {
                    CallKitManager.shared.sipEnded()
                    self.activeCall = nil
                    self.wantedRoute = nil
                    self.routePending = false
                    self.muted = false
                }
                if state == .End || state == .Error {
                    let missed = incoming && (call.callLog?.status == .Missed || refused)
                    self.recents.insert(RecentCall(number: number, date: Date(), incoming: incoming, missed: missed, name: name), at: 0)
                }
            case .StreamsRunning:
                if !incoming { CallKitManager.shared.sipConnected() }
                if self.routePending { self.routePending = false; self.applyRoute() }
                self.activeCall = CallInfo(number: number, state: state, incoming: incoming, name: name)
            default:
                self.activeCall = CallInfo(number: number, state: state, incoming: incoming, name: name)
            }
            let live = self.liveCalls()
            let members = live.filter { $0.conference != nil }
            self.inConference = !members.isEmpty
            self.participants = members.map { self.name(of: $0) ?? $0.remoteAddress?.username ?? "Unknown" }
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
