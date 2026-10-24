import Foundation
import AVFoundation
import Network
import SwiftUI   // ScenePhase
import UIKit   // applicationState
import WebRTC

/// Where a call is; the names are the ones the screens have always used.
enum CallState {
    case IncomingReceived, OutgoingInit, OutgoingProgress, OutgoingRinging, OutgoingEarlyMedia
    case Connected, StreamsRunning, Pausing, Paused, Resuming, PausedByRemote, End, Error, Released
}

struct CallInfo: Identifiable {
    let id = UUID()
    let number: String
    let state: CallState
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

/// One audio device the user can pick; `id` is "iphone", "speaker", "headset" or "bt:<port uid>".
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

/// One call: its SIP dialog and its audio.
private final class SipCall {
    let incoming: Bool
    let callId: String
    let number: String
    let name: String?
    var state: CallState
    let localTag = String(UUID().uuidString.prefix(10))
    /// Outgoing: our INVITE (kept for CANCEL, replaced by the password retry). Incoming: the PBX's INVITE.
    var invite: SipMsg?
    var dialog: Dialog?
    var media: CallMedia?
    var answered = false
    var answering = false
    /// Answered on another phone of the extension (the PBX's CANCEL says so): not a missed call.
    var elsewhere = false
    var gotProvisional = false
    var earlyMedia = false
    /// Hang up asked for before the PBX answered anything: CANCEL as soon as it does.
    var hangupWanted = false
    var localHold = false
    var remoteHold = false
    var reinviting = false
    /// Blind or attended transfer sent (REFER): hang up once the PBX says it worked.
    var transferring = false
    /// Rung from a conference (Add participant): moved into the room as soon as they answer.
    var autoMerge = false
    /// Incoming: our answer SDP, made while it rings (nil = could not be made); `prepareDone` once that finished.
    var prepared: String?
    var prepareDone = false

    init(incoming: Bool, callId: String, number: String, name: String?) {
        self.incoming = incoming; self.callId = callId; self.number = number; self.name = name
        state = incoming ? .IncomingReceived : .OutgoingInit
    }
}

private let endedStates: Set<CallState> = [.End, .Error, .Released]

final class SipManager: ObservableObject, SipUaEvents {
    static let shared = SipManager()

    @Published var registration = "Not registered"
    @Published var registered = false
    /// The PBX refused the saved extension/password (not during a sign-in check): the app goes back to the sign-in screen.
    @Published var loginRefused = false
    @Published var activeCall: CallInfo?
    @Published var muted = false
    @Published var audioRoutes: [AudioOption] = []
    @Published var audioRoute: AudioOption?   // what iOS plays the call through right now
    @Published var recents: [RecentCall] = [] { didSet { saveRecents() } }
    @Published var newVoicemails = 0
    @Published var hasVoicemail = false
    /// A short message for the call screen (e.g. the second call could not be placed); cleared by the screen.
    @Published var notice: String?
    /// The last call problem in WebRTC's own words (Settings shows it with Copy), for the tester to send to N2IT.
    @Published var lastProblem: String?
    /// Test builds: live state of the call's audio connection, shown small on the call screen.
    @Published var audioDiag: String?
    /// Tester tools (Last call problem, the call screen's audio line): hidden from clients (owner 2026-10-22); 7 taps on
    /// the version number in Settings turn them on or off on this phone.
    @Published var tester = UserDefaults.standard.bool(forKey: "tester") {
        didSet { UserDefaults.standard.set(tester, forKey: "tester") }
    }

    /// "0.3.0", from MARKETING_VERSION in project.yml.
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    private var ua: SipUa!
    private var calls: [SipCall] = []

    private func saveRecents() {
        if let d = try? JSONEncoder().encode(Array(recents.prefix(100))) { UserDefaults.standard.set(d, forKey: "recents") }
    }

    // MARK: Accounts

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
            ua.stop()
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
        ua = SipUa(events: self)
        // Shows on the PBX (registrations, logs) instead of "Unknown"; Android sends "N2IT Phone Android/<version>".
        ua.userAgent = "N2IT Phone iOS/\(SipManager.appVersion)"
        _ = Rtc.factory   // manual audio mode is set up before any call
        updateRoutes()
        // Also catches changes made outside the app: Control Centre, the iOS call screen, a car kit connecting.
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.updateRoutes()
        }
        watchNetwork()
        let savedDnd = UserDefaults.standard.double(forKey: "dndUntil")
        setDnd(savedDnd > 0 ? Date(timeIntervalSince1970: savedDnd) : nil)   // survives restarts; clears itself if expired
        configure(Account.load())
        PushManager.shared.start()
    }

    /// Wi-Fi <-> mobile data: the old connection is dead; reconnect at once so calls keep ringing.
    private let monitor = NWPathMonitor()
    private var lastInterface: NWInterface.InterfaceType?
    private func watchNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let iface = path.availableInterfaces.first?.type
                let changed = self.lastInterface != nil && iface != nil && iface != self.lastInterface
                if iface != nil { self.lastInterface = iface }
                if changed, path.status == .satisfied { self.ua.reconnectNow() }
            }
        }
        monitor.start(queue: .global(qos: .utility))
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

    // MARK: Do Not Disturb

    /// DND is always timed, at most 2 weeks (owner 2026-10-07). Per phone, not per account.
    static let maxDnd: TimeInterval = 14 * 24 * 3600
    /// End of DND, or nil when off.
    @Published private(set) var dndUntil: Date?
    private var dndTimer: Timer?

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

    // MARK: Registration

    /// Register `acc` over the secure WebSocket at wss://<company>.voip.n2it.co.za/wss (port 443, as the desktop app).
    /// The account's port, transport and SRTP settings were for Linphone and are not used.
    func configure(_ acc: Account) {
        guard !acc.user.isEmpty else { return }
        ua.start(user: acc.user, password: acc.password, domain: acc.domain)
    }

    /// The PBX's answer to the latest registration, for the sign-in check.
    enum RegOutcome { case ok, failed(code: Int, reason: String) }
    private var outcomeWaiters: [(RegOutcome) -> Void] = []

    /// Sign-in check: registers `acc` and waits for the PBX's answer, so a wrong extension or password is said at once
    /// instead of the app opening with a red "Failed: Forbidden". nil = no answer within `timeout` (wrong company code,
    /// no internet). After a refusal the caller stops it (`stopRegistering`) or puts the previous account back: retrying
    /// a wrong password every minute gets the phone's whole network banned by the PBX (fail2ban).
    @MainActor
    func verify(_ acc: Account, timeout: TimeInterval = 12) async -> RegOutcome? {
        await withCheckedContinuation { (k: CheckedContinuation<RegOutcome?, Never>) in
            var done = false
            let finish: (RegOutcome?) -> Void = { r in if !done { done = true; k.resume(returning: r) } }
            outcomeWaiters.append { finish($0) }
            later(timeout) { finish(nil) }
            configure(acc)
        }
    }

    func stopRegistering() { ua.stop() }

    /// Sign in / Add account / Save: nil when the PBX accepted `acc`, else what to tell the user. After a refusal the
    /// account that worked before (`previous`) registers again, or registering stops; nothing is saved by this.
    @MainActor
    func signInProblem(_ acc: Account, previous: Account?) async -> String? {
        let outcome = await verify(acc)
        let message: String
        switch outcome {
        case .ok?: return nil
        case .failed(let code, _)? where [401, 403, 407].contains(code):
            message = "Wrong extension or password. Check them and try again."
        case .failed(404, _)?:
            message = "Extension not found at \(acc.domain)."
        case .failed(let code, let reason)? where ![408, 503].contains(code):
            message = "The PBX refused the sign-in (\(code) \(reason))."
        default:
            message = "No answer from \(acc.domain). Check the company code and your internet connection."
        }
        if let previous, previous.isConfigured { configure(previous) } else { stopRegistering() }
        return message
    }

    func onRegistration(_ state: SipUa.RegState, _ code: Int, _ reason: String) {
        let checking = !outcomeWaiters.isEmpty
        registered = state == .ok
        if state == .failed && !checking && [401, 403, 407].contains(code) { stopRegistering(); loginRefused = true }
        switch state {
        case .ok: registration = "Registered"; subscribeVoicemail()
        case .progress: registration = reason.isEmpty ? "Registering…" : reason
        case .failed: registration = "Failed: \(reason)"
        case .none: registration = "Not registered"
        }
        if state == .ok || state == .failed {
            let w = outcomeWaiters; outcomeWaiters = []
            w.forEach { $0(state == .ok ? .ok : .failed(code: code, reason: reason)) }
        }
    }

    func onTransportDown() {
        // Calls cannot be controlled without the connection; their audio may still flow and the PBX keeps them up.
        mwiTimer?.cancel()
    }

    // MARK: Voicemail lamp: SUBSCRIBE message-summary; the PBX NOTIFYs "Messages-Waiting: yes" / "Voice-Message: 2/0"
    private var mwiTimer: DispatchWorkItem?
    private var mwiCallId = ""
    private var mwiCseq = 0
    private func subscribeVoicemail() {
        mwiTimer?.cancel()
        if mwiCallId.isEmpty { mwiCallId = ua.token(22) }
        mwiCseq += 1
        let sub = SipMsg("SUBSCRIBE \(ua.aor) SIP/2.0").add("Via", ua.via()).add("Max-Forwards", "70")
            .add("To", "<\(ua.aor)>").add("From", "<\(ua.aor)>;tag=\(ua.token(10))").add("Call-ID", mwiCallId)
            .add("CSeq", "\(mwiCseq) SUBSCRIBE").add("Contact", ua.contact).add("Event", "message-summary")
            .add("Accept", "application/simple-message-summary").add("Expires", "3600").add("User-Agent", ua.userAgent)
        ua.request(sub, onRetry: { [weak self] in self?.mwiCseq = $0.cseq }) { [weak self] res in
            if (200...299).contains(res.status) { self?.mwiTimer = later(3000) { [weak self] in self?.subscribeVoicemail() } }
        }
    }

    // MARK: Requests from the PBX
    func onRequest(_ req: SipMsg) {
        let c = calls.first { $0.callId == req.callId && !endedStates.contains($0.state) }
        switch req.method {
        case "INVITE":
            if let c { offerFromPbx(c, req) }
            else if req.toTag != nil { ua.reply(req, 481, "Call/Transaction Does Not Exist") }
            else { incoming(req) }
        case "ACK": break
        case "CANCEL":
            ua.reply(req, 200, "OK")
            guard let c, !c.answered else { return }
            if let inv = c.invite { ua.reply(inv, 487, "Request Terminated", toTag: c.localTag) }
            // Answered on another phone of the extension: the PBX says "Call completed elsewhere" (cause 200)
            let why = req.h("Reason") ?? ""
            c.elsewhere = why.contains("cause=200") || why.lowercased().contains("elsewhere")
            end(c)
        case "BYE":
            ua.reply(req, 200, "OK")
            if let c { end(c) }
        case "UPDATE":
            if let c, req.hasSdp { offerFromPbx(c, req) } else { ua.reply(req, 200, "OK", extra: [("Contact", ua.contact)]) }
        case "NOTIFY": ua.reply(req, 200, "OK"); notify(req)
        case "OPTIONS": ua.reply(req, 200, "OK", extra: [("Allow", SipUa.allow), ("Accept", "application/sdp")])
        case "INFO", "MESSAGE": ua.reply(req, 200, "OK")
        default: ua.reply(req, 501, "Not Implemented")
        }
    }

    private func notify(_ req: SipMsg) {
        let event = (req.h("Event") ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if event.lowercased() == "message-summary" {
            let text = req.body
            let waiting = text.range(of: "Messages-Waiting:\\s*yes", options: [.regularExpression, .caseInsensitive]) != nil
            var count = 0
            if let r = text.range(of: "Voice-Message:\\s*\\d+", options: [.regularExpression, .caseInsensitive]) {
                count = Int(text[r].filter(\.isNumber)) ?? 0
            }
            newVoicemails = count
            hasVoicemail = waiting || count > 0
            return
        }
        guard event.lowercased() == "refer", let c = calls.first(where: { $0.callId == req.callId && $0.transferring }) else { return }
        // How the transfer is going: "SIP/2.0 200 OK" when the other side answered
        guard let r = req.body.range(of: "SIP/2.0\\s+\\d{3}", options: .regularExpression),
              let code = Int(req.body[r].suffix(3)) else { return }
        if (200...299).contains(code) { hangupCall(c) }
        else if code >= 300 { c.transferring = false; notice = "Transfer failed (\(code))" }
    }

    private func incoming(_ req: SipMsg) {
        let from = req.h("From")
        let number = SipMsg.userOf(SipMsg.uriOf(from)).isEmpty ? "Unknown" : SipMsg.userOf(SipMsg.uriOf(from))
        let pbxName = SipMsg.nameOf(from).flatMap { $0 != number ? $0 : nil }
        let name = pbxName ?? self.name(for: number)
        checkDnd()
        if dndActive {
            // DND: refuse as busy; the PBX sends the caller to voicemail (or says there is none).
            // Other phones on the same extension (e.g. a desk phone) keep ringing.
            ua.reply(req, 486, "Busy Here", toTag: ua.token(10))
            addRecent(number, incoming: true, missed: true, name: name)
            return
        }
        if CallKitManager.shared.takeDeclinedBeforeInvite(number) {
            ua.reply(req, 603, "Decline", toTag: ua.token(10))
            addRecent(number, incoming: true, missed: true, name: name)
            return
        }
        guard req.hasSdp else { ua.reply(req, 488, "Not Acceptable Here", toTag: ua.token(10)); return }
        let c = SipCall(incoming: true, callId: req.callId, number: number, name: name)
        c.invite = req
        c.dialog = Dialog(callId: req.callId, localTag: c.localTag, remoteTag: req.fromTag ?? "", localUri: SipMsg.uriOf(req.h("To")),
                          remoteUri: SipMsg.uriOf(from),
                          remoteTarget: SipMsg.uriOf(req.h("Contact")).isEmpty ? SipMsg.uriOf(from) : SipMsg.uriOf(req.h("Contact")),
                          routes: req.all("Record-Route").flatMap { $0.split(separator: ",") }.map { $0.trimmingCharacters(in: .whitespaces) },
                          localCseq: 1)
        calls.append(c)
        ua.reply(req, 180, "Ringing", toTag: c.localTag, extra: [("Contact", ua.contact)])
        // Make the answer while it rings (2026-10-22: about 2 s of silence after Answer while WebRTC gathered its
        // addresses). No audio flows before Answer: CallKit only hands over the audio session then.
        if let media = newMedia(c) {
            media.answer(req.body) { [weak self] sdp in
                guard let self, !endedStates.contains(c.state) else { return }
                c.prepared = sdp; c.prepareDone = true
                if c.answering { self.sendAnswer(c) }
            }
        }
        CallKitManager.shared.sipIncoming(caller: number, name: name)
        publish()
    }

    /// The PBX's offer inside a call (its re-INVITE or UPDATE): hold by them, music on hold, a transfer on its side.
    private func offerFromPbx(_ c: SipCall, _ req: SipMsg) {
        guard let media = c.media, req.hasSdp else {
            ua.reply(req, req.hasSdp ? 491 : 488, req.hasSdp ? "Request Pending" : "Not Acceptable Here", toTag: c.localTag); return
        }
        if c.reinviting { ua.reply(req, 491, "Request Pending", toTag: c.localTag); return }
        if let ct = req.h("Contact") { c.dialog?.remoteTarget = SipMsg.uriOf(ct) }
        let heldByThem = req.body.range(of: "a=(sendonly|inactive)", options: .regularExpression) != nil || req.body.contains("c=IN IP4 0.0.0.0")
        media.answer(req.body) { [weak self] sdp in
            guard let self, !endedStates.contains(c.state) else { return }
            guard let sdp else {
                self.ua.reply(req, 488, "Not Acceptable Here", toTag: c.localTag)
                self.problem("PBX re-offer refused: \(media.lastError ?? "unknown")", req.body); return
            }
            self.ua.reply(req, 200, "OK", toTag: c.localTag, extra: [("Contact", self.ua.contact), ("Allow", SipUa.allow)], body: sdp)
            c.remoteHold = heldByThem
            if !c.localHold { self.setState(c, heldByThem ? .PausedByRemote : .StreamsRunning) }
        }
    }

    // MARK: State shown to the screens

    private func liveCalls(except: SipCall? = nil) -> [SipCall] { calls.filter { $0 !== except && !endedStates.contains($0.state) } }
    /// The call in front of the user: the one not on hold.
    private func currentCall() -> SipCall? { liveCalls().first { $0.state != .IncomingReceived && !$0.localHold } }
    private func ringingCall() -> SipCall? { liveCalls().first { $0.state == .IncomingReceived && !$0.answering } }

    @Published var onHold = false
    @Published var consulting = false
    @Published var inConference = false
    @Published var participants: [String] = []

    /// Mirror the calls into UI state: one call, or a held call plus a consult call.
    private func publish() {
        if let conf = confCall, !endedStates.contains(conf.state) {
            let others = liveCalls().filter { $0 !== conf && !$0.transferring }
            let ringing = others.map { ($0.name ?? $0.number) + ($0.answered ? " (on hold)" : " (ringing)") }
            let people = confPeople.map { $0.label } + ringing
            activeCall = CallInfo(number: people.joined(separator: ", "), state: conf.state, incoming: false, name: nil)
            inConference = true; participants = people
            onHold = conf.localHold
            consulting = others.contains { $0.answered && !$0.autoMerge }
            return
        }
        inConference = false; participants = []
        let all = liveCalls()
        let live = all.count > 1 ? all.filter { !$0.transferring } : all
        guard let c = currentCall() ?? ringingCall() ?? live.first else {
            activeCall = nil; onHold = false; consulting = false; return
        }
        activeCall = CallInfo(number: c.number, state: c.state, incoming: c.incoming, name: c.name)
        onHold = c.state == .Paused || c.state == .Pausing
        consulting = live.count > 1
    }

    private func setState(_ c: SipCall, _ s: CallState) {
        c.state = s
        if s == .StreamsRunning && !c.incoming { CallKitManager.shared.sipConnected() }
        if s == .StreamsRunning {
            if c === confCall && !pendingMerge.isEmpty { let list = pendingMerge; pendingMerge = []; moveIntoRoom(list) }
            if c.autoMerge && confCall != nil { c.autoMerge = false; moveIntoRoom([c]) }
        }
        publish()
    }

    // MARK: Calls

    // UI entry points go through CallKit; CallKitManager calls the *Sip methods below.
    func call(_ number: String) { if !number.isEmpty { CallKitManager.shared.startCall(number) } }
    func answer() { CallKitManager.shared.requestAnswer() }
    func hangup() { CallKitManager.shared.requestEnd() }

    /// "082 123-4567", "(012) 345 6789" → digits; a typed SIP address (with @) is only trimmed.
    private func cleanNumber(_ number: String) -> String {
        let n = number.trimmingCharacters(in: .whitespaces)
        return n.contains("@") ? n.filter { !$0.isWhitespace } : n.filter { "+0123456789*#".contains($0) }
    }

    /// Rings `number`; false when it could not be dialled (not connected, or not a valid number).
    @discardableResult
    func invite(_ number: String) -> Bool { startCall(number) != nil }

    private func startCall(_ number: String) -> SipCall? {
        let n = cleanNumber(number)
        notice = nil
        guard !n.isEmpty, ua.connected else { notice = "Not connected to the PBX"; return nil }
        let target = n.contains("@") ? "sip:\(n)" : "sip:\(n)@\(ua.domain)"
        let c = SipCall(incoming: false, callId: ua.token(22), number: SipMsg.userOf(target), name: name(for: SipMsg.userOf(target)))
        calls.append(c)
        muted = muted && liveCalls().count > 1
        setState(c, .OutgoingInit)
        guard let media = newMedia(c) else { fail(c, "No audio"); return c }
        media.offer { [weak self] sdp in
            guard let self, !endedStates.contains(c.state) else { return }
            guard let sdp, !c.hangupWanted else {
                if sdp == nil { self.problem("Call failed: \(media.lastError ?? "no audio")", nil) }
                self.fail(c, sdp == nil ? "No audio" : nil); return
            }
            let inv = SipMsg("INVITE \(target) SIP/2.0").add("Via", self.ua.via()).add("Max-Forwards", "70")
                .add("To", "<\(target)>").add("From", "<\(self.ua.aor)>;tag=\(c.localTag)").add("Call-ID", c.callId)
                .add("CSeq", "1 INVITE").add("Contact", self.ua.contact).add("Allow", SipUa.allow)
                .add("Supported", "replaces, outbound").add("User-Agent", self.ua.userAgent).add("Content-Type", "application/sdp")
            inv.body = sdp
            c.invite = inv
            self.ua.request(inv, onRetry: { c.invite = $0 }) { [weak self] res in self?.inviteAnswered(c, target, res) }
        }
        return c
    }

    private func newMedia(_ c: SipCall) -> CallMedia? {
        let m = CallMedia(noiseFilter: backgroundFilter) { [weak self] in
            // The audio connection failed for good (network gone): end the call instead of leaving it silent
            guard let self, !endedStates.contains(c.state) else { return }
            self.notice = "Call audio lost"; self.hangupCall(c)
        }
        c.media = m
        m?.setMuted(muted)
        m?.onDiag = { [weak self] line in if !endedStates.contains(c.state) { self?.audioDiag = line } }
        m?.startDiag()
        return m
    }

    /// "Filter out background voices": WebRTC's noise suppression on the microphone; read when a call's audio starts.
    var backgroundFilter: Bool {
        get { UserDefaults.standard.object(forKey: "gate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gate") }
    }

    private func inviteAnswered(_ c: SipCall, _ target: String, _ res: SipMsg) {
        if endedStates.contains(c.state) {
            if (200...299).contains(res.status) {
                dialogFrom(c, target, res); ack(c, res)
                if let d = c.dialog { ua.request(ua.inDialog(d, "BYE")) { _ in } }
            }
            return
        }
        if res.status < 200 {
            if res.status > 100 {
                c.gotProvisional = true
                if c.hangupWanted { if let inv = c.invite { ua.cancel(inv) }; return }
            }
            if res.hasSdp {
                c.media?.remoteAnswer(res.body, provisional: true) { [weak self] ok in
                    guard let self else { return }
                    if !ok { self.problem("Early media refused: \(c.media?.lastError ?? "unknown")", res.body) }
                    if ok && !endedStates.contains(c.state) && !c.answered { c.earlyMedia = true; self.setState(c, .OutgoingEarlyMedia) }
                }
            } else if res.status == 180 {
                if !c.earlyMedia { setState(c, .OutgoingRinging) }
            } else if res.status == 100 || (res.status > 100 && c.state == .OutgoingInit) {
                setState(c, .OutgoingProgress)
            }
        } else if res.status < 300 {
            dialogFrom(c, target, res)
            ack(c, res)
            c.answered = true
            if res.hasSdp {
                c.media?.remoteAnswer(res.body, provisional: false) { [weak self] ok in
                    if !ok { self?.problem("Answer from PBX refused: \(c.media?.lastError ?? "unknown")", res.body) }
                }
            }
            setState(c, .Connected)
            setState(c, .StreamsRunning)
            if c.hangupWanted { hangupCall(c) }
        } else {
            switch res.status {
            case 486, 600: fail(c, "Busy")
            case 480: fail(c, "Not available")
            case 404, 484: fail(c, "Number not found")
            case 487: fail(c, nil)
            case 403: fail(c, "Not allowed")
            case 408: fail(c, "No answer")
            case 488: fail(c, "Audio not accepted")
            case 503: fail(c, res.reason.isEmpty ? "Not connected" : res.reason)
            default: fail(c, "\(res.status) \(res.reason)".trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private func dialogFrom(_ c: SipCall, _ target: String, _ res: SipMsg) {
        if c.dialog != nil { return }
        let to = SipMsg.uriOf(res.h("To"))
        let contact = SipMsg.uriOf(res.h("Contact"))
        c.dialog = Dialog(callId: c.callId, localTag: c.localTag, remoteTag: res.toTag ?? "", localUri: ua.aor,
                          remoteUri: to.isEmpty ? target : to, remoteTarget: contact.isEmpty ? target : contact,
                          routes: res.all("Record-Route").flatMap { $0.split(separator: ",") }.map { $0.trimmingCharacters(in: .whitespaces) }.reversed(),
                          localCseq: c.invite?.cseq ?? 1)
    }

    private func ack(_ c: SipCall, _ res: SipMsg) { if let d = c.dialog { ua.send(ua.inDialog(d, "ACK", cseq: res.cseq)) } }

    /// The call could not be made: say why (busy, rejected…) on the call screen instead of it just vanishing.
    private func fail(_ c: SipCall, _ why: String?) {
        if let why { notice = "Call failed: \(why)" }
        c.state = .Error
        end(c)
    }

    var hasIncomingSip: Bool { ringingCall() != nil }
    /// Any SIP call (ringing or up); false while CallKit shows a push call whose INVITE has not arrived.
    var hasLiveSip: Bool { !liveCalls().isEmpty }

    func answerSip() {
        guard let c = ringingCall(), let req = c.invite else { return }
        c.answering = true
        muted = muted && !liveCalls().filter({ $0 !== c && $0.state != .IncomingReceived }).isEmpty
        c.media?.setMuted(muted)
        setState(c, .Connected)
        if c.media == nil { ua.reply(req, 488, "Not Acceptable Here", toTag: c.localTag); end(c); return }
        if c.prepareDone { sendAnswer(c) }   // otherwise sent the moment the answer is ready
    }

    /// The answer made while it rang goes to the PBX: the call connects at once.
    private func sendAnswer(_ c: SipCall) {
        guard let req = c.invite, !c.answered, !endedStates.contains(c.state) else { return }
        guard let sdp = c.prepared else {
            ua.reply(req, 488, "Not Acceptable Here", toTag: c.localTag)
            problem("Answer failed: \(c.media?.lastError ?? "no audio")", req.body)
            end(c); return
        }
        ua.reply(req, 200, "OK", toTag: c.localTag,
                 extra: [("Contact", ua.contact), ("Allow", SipUa.allow), ("Supported", "replaces, outbound")], body: sdp)
        c.answered = true; c.answering = false
        setState(c, .StreamsRunning)
    }

    /// Ends the call in front of the user (or declines the ringing one).
    func hangupSip() {
        guard let c = currentCall() ?? liveCalls().first else { return }
        if c.state == .IncomingReceived && !c.answering { decline(c) } else { hangupCall(c) }
    }

    /// Decline the ringing call: the PBX carries on (other phones of the extension, voicemail).
    private func decline(_ c: SipCall) {
        if let inv = c.invite { ua.reply(inv, 603, "Decline", toTag: c.localTag) }
        end(c)
    }

    private func hangupCall(_ c: SipCall) {
        if endedStates.contains(c.state) { return }
        if c.answered { if let d = c.dialog { ua.request(ua.inDialog(d, "BYE")) { _ in } } }
        else if c.incoming { if let inv = c.invite { ua.reply(inv, 603, "Decline", toTag: c.localTag) } }
        else if c.gotProvisional { if let inv = c.invite { ua.cancel(inv) } }
        else {
            // Nothing heard from the PBX yet: CANCEL (or BYE) as soon as it answers
            c.hangupWanted = true
            if c.invite != nil { return }
        }
        end(c)
    }

    private func end(_ c: SipCall) {
        if c.state != .Error { c.state = .End }
        c.media?.close(); c.media = nil
        calls.removeAll { $0 === c }
        addRecent(c.number, incoming: c.incoming, missed: c.incoming && !c.answered && !c.elsewhere, name: c.name)
        userHeld.removeAll { $0 === c }
        consultHoldDone(c)
        if c === confCall {
            confCall = nil; confRoom = nil; confPeople = []; pendingMerge = []
            liveCalls().forEach { $0.autoMerge = false }
        }
        if c.autoMerge { confCall?.media?.setMuted(muted) }
        // Another call may still be up (held caller after a consult)
        if liveCalls().isEmpty {
            CallKitManager.shared.sipEnded()
            activeCall = nil; onHold = false; consulting = false; muted = false
            wantedRoute = nil; audioDiag = nil
        } else { publish() }
    }

    private func addRecent(_ number: String, incoming: Bool, missed: Bool, name: String?) {
        recents.insert(RecentCall(number: number, date: Date(), incoming: incoming, missed: missed, name: name), at: 0)
    }

    private func problem(_ what: String, _ sdp: String?) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        lastProblem = "N2IT Phone \(SipManager.appVersion), \(f.string(from: Date()))\n\(what)" + (sdp.map { "\n--- SDP from PBX ---\n\($0)" } ?? "")
        notice = what
    }

    /// Re-register after a VoIP push woke the app. iOS kills the socket while the app is suspended, so connect afresh.
    /// A VoIP push or the app coming back on screen. After suspension the socket is probably dead: reconnect. But the
    /// PBX also pushes when the app is open and registered, and reconnecting then cut the socket the INVITE was
    /// arriving on (0.3.0 test 2026-10-22: in-app Answer did nothing, a 603 nobody pressed): with a call up, or the app
    /// on screen with a live connection, only re-register on the same socket.
    func wake() {
        dlog("wake(): live calls \(liveCalls().count), app state \(UIApplication.shared.applicationState.rawValue), connected \(ua.connected)")
        if !liveCalls().isEmpty || (UIApplication.shared.applicationState == .active && ua.connected) { ua.refreshNow() }
        else { ua.reconnectNow() }
    }

    /// Test builds: a line for Settings > Last call problem (what CallKit or iOS did to a call).
    func problemNote(_ what: String) { problem(what, nil) }

    /// iOS suspends the app soon after it leaves the screen (or the phone locks), and the connection to the PBX dies
    /// with it. Re-register straight away whenever the app is back on screen.
    func appPhase(_ phase: ScenePhase) {
        if phase == .active {
            checkDnd()
            wake()
        }
    }

    func setMuted(_ m: Bool) {
        muted = m
        liveCalls().forEach { $0.media?.setMuted(m) }
    }
    func toggleMute() { setMuted(!muted) }
    func sendDigit(_ d: Character) { currentCall()?.media?.sendDigit(d) }

    // MARK: Hold and transfer

    /// Calls the user held themselves; `systemHold(false)` leaves these on hold.
    private var userHeld: [SipCall] = []

    /// Hold: re-INVITE with our audio "sendonly"; the PBX plays music on hold to the other side.
    private func setHold(_ c: SipCall, _ held: Bool, done: @escaping (Bool) -> Void = { _ in }) {
        guard let d = c.dialog, let media = c.media, c.answered, !c.reinviting, c.localHold != held else { done(false); return }
        c.reinviting = true
        c.localHold = held
        setState(c, held ? .Pausing : .Resuming)
        media.setHold(held)
        media.offer { [weak self] sdp in
            guard let self else { return }
            if endedStates.contains(c.state) { c.reinviting = false; done(false); return }
            guard let sdp else { c.reinviting = false; self.undoHold(c, held); done(false); return }
            let req = self.ua.inDialog(d, "INVITE").add("Allow", SipUa.allow).add("Content-Type", "application/sdp")
            req.body = sdp
            self.ua.request(req, onRetry: { d.localCseq = $0.cseq }) { [weak self] res in
                guard let self, res.status >= 200 else { return }
                c.reinviting = false
                if endedStates.contains(c.state) { return }
                if res.status < 300 {
                    self.ua.send(self.ua.inDialog(d, "ACK", cseq: res.cseq))
                    if res.hasSdp { media.remoteAnswer(res.body, provisional: false) }
                    self.setState(c, held ? .Paused : (c.remoteHold ? .PausedByRemote : .StreamsRunning))
                    done(true)
                } else if res.status == 491 {
                    // Both sides changed the call at once: try again shortly (RFC 3261 says 2.1-4 s)
                    c.localHold = !held
                    later(2.5) { self.setHold(c, held, done: done) }
                } else { self.undoHold(c, held); done(false) }
            }
        }
    }
    private func undoHold(_ c: SipCall, _ held: Bool) {
        c.localHold = !held; c.media?.setHold(!held)
        setState(c, !held ? .Paused : .StreamsRunning)
        notice = held ? "Could not put the call on hold" : "Could not take the call off hold"
    }

    func toggleHold() {
        if let c = liveCalls().first(where: { $0.localHold }) { userHeld.removeAll { $0 === c }; setHold(c, false) }
        else if let c = currentCall() { userHeld.append(c); setHold(c, true) }
    }

    /// CallKit hold/unhold, e.g. the user took a GSM or WhatsApp call with "Hold & Accept". Holding makes the
    /// PBX play hold music; resuming restarts the audio streams.
    func systemHold(_ on: Bool) {
        for c in liveCalls() {
            if on, c.answered, !c.localHold { setHold(c, true) }
            if !on, c.localHold, !userHeld.contains(where: { $0 === c }) { setHold(c, false) }
        }
    }

    /// Blind transfer: hand the current call to `number` and drop out once the PBX has taken it.
    func blindTransfer(_ number: String) {
        guard let c = currentCall() ?? liveCalls().first(where: { $0.answered }) else { return }
        let n = cleanNumber(number)
        if n.isEmpty { notice = "Not a valid number"; return }
        refer(c, "<\(n.contains("@") ? "sip:\(n)" : "sip:\(n)@\(ua.domain)")>")
    }

    private func refer(_ c: SipCall, _ referTo: String) {
        guard let d = c.dialog else { return }
        c.transferring = true
        let req = ua.inDialog(d, "REFER").add("Refer-To", referTo).add("Referred-By", "<\(ua.aor)>")
        ua.request(req, onRetry: { d.localCseq = $0.cseq }) { [weak self] res in
            guard let self, res.status >= 200 else { return }
            if res.status >= 300 { c.transferring = false; self.notice = "Transfer refused (\(res.status))"; return }
            // Accepted: the PBX reports progress in NOTIFYs; if none comes, drop out anyway after 10 s
            later(10) { if c.transferring { self.hangupCall(c) } }
        }
    }

    /// Attended transfer, step 1: put the caller on hold and ring `number`. The second call is placed once the hold has
    /// gone through; if it cannot be placed the caller is taken off hold again and the screen says why.
    func consult(_ number: String) {
        let n = cleanNumber(number)
        if n.isEmpty { notice = "Not a valid number"; return }
        guard let c = currentCall(), !c.localHold else { placeConsult(n, nil); return }
        pendingConsult = (n, c)
        consultFallback = later(3) { [weak self] in   // the hold never confirmed: dial anyway
            if let (n, held) = self?.pendingConsult { self?.pendingConsult = nil; self?.placeConsult(n, held) }
        }
        userHeld.append(c)
        setHold(c, true) { [weak self] _ in self?.consultHoldDone(c) }
    }
    private var pendingConsult: (String, SipCall)?
    private var consultFallback: DispatchWorkItem?
    /// The held call reached Paused (or ended).
    private func consultHoldDone(_ call: SipCall) {
        guard let (n, held) = pendingConsult, held === call else { return }
        pendingConsult = nil; consultFallback?.cancel()
        if endedStates.contains(call.state) { return }
        placeConsult(n, held)
    }
    private func placeConsult(_ n: String, _ held: SipCall?) {
        if invite(n) { return }
        notice = "Could not call \(n)"
        if let held, held.localHold { userHeld.removeAll { $0 === held }; setHold(held, false) }
    }

    // MARK: 3-way calls: a conference room on the PBX (port of Android 0.3.1)
    // FusionPBX's global "nb-conference" dialplan: *30 + 2-7 digits joins room <digits>@<company domain> (every tenant
    // has it). Merge = we join a new random room, then transfer each person into it (REFER); the PBX mixes the audio.
    private var confCall: SipCall?
    private var confRoom: String?
    private var confPeople: [(id: String, label: String)] = []
    private var pendingMerge: [SipCall] = []

    /// Add participant: in a conference, ring `number` with the room left as it is (holding it would play hold music
    /// to everyone; only our microphone is muted there) and move them in when they answer. Otherwise hold the call and
    /// ring `number` (a consult), then Merge calls.
    func addParticipant(_ number: String) {
        guard let conf = confCall else { consult(number); return }
        guard let c = startCall(number) else { notice = "Could not call \(cleanNumber(number))"; return }
        c.autoMerge = true
        conf.media?.setMuted(true)
        publish()
    }

    /// Merge calls: everyone who has answered joins one conference with us.
    func merge() {
        let answered = liveCalls().filter { $0.answered && $0 !== confCall && !$0.transferring }
        if confCall != nil { moveIntoRoom(answered); return }
        guard answered.count >= 2 else { notice = "Wait for them to answer, then merge"; return }
        let room = "*30" + String((0..<7).map { _ in "0123456789".randomElement()! })
        guard let c = startCall(room) else { notice = "Could not start the conference"; return }
        confRoom = room; confCall = c
        pendingMerge = answered
        publish()
    }

    private func moveIntoRoom(_ list: [SipCall]) {
        guard let room = confRoom else { return }
        for c in list where !endedStates.contains(c.state) && c.answered {
            confPeople.removeAll { $0.id == c.callId }
            confPeople.append((c.callId, c.name ?? c.number))
            refer(c, "<sip:\(room)@\(ua.domain)>")
        }
        // Back to the room: unmute there, and off hold if a consult had put it on hold
        if let conf = confCall {
            conf.media?.setMuted(muted)
            if conf.localHold { userHeld.removeAll { $0 === conf }; setHold(conf, false) }
        }
        publish()
    }

    /// Attended transfer, step 2: connect the held caller to the consulted party (REFER with Replaces); the PBX joins
    /// them and drops us.
    func completeTransfer() {
        guard let held = liveCalls().first(where: { $0.localHold }), let other = liveCalls().first(where: { $0 !== held }) else { return }
        guard other.answered, let d = other.dialog else { notice = "Wait for them to answer, or use Transfer"; return }
        let safe = CharacterSet.alphanumerics
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: safe) ?? s }
        let replaces = "\(enc(d.callId))%3Bto-tag%3D\(enc(d.remoteTag))%3Bfrom-tag%3D\(enc(d.localTag))"
        refer(held, "<\(d.remoteUri)?Replaces=\(replaces)>")
        other.transferring = true   // the PBX ends this one too; drop it ourselves if it does not
        later(10) { [weak self] in if !endedStates.contains(other.state) && other.transferring && endedStates.contains(held.state) { self?.hangupCall(other) } }
    }

    // MARK: Audio route

    /// Route picked for the calls in progress: the default when the first call starts, then the user's choice.
    /// Cleared when the last call ends, so each new call starts on the default route again.
    private var wantedRoute: String?

    /// CallKit gave us the audio session (didActivate) or took it back. With WebRTC's manual audio mode this is what
    /// starts and stops the microphone and speaker; getting it wrong gives "answered but no audio".
    func audioSession(active: Bool) {
        let rtc = RTCAudioSession.sharedInstance()
        let session = AVAudioSession.sharedInstance()
        if active {
            rtc.audioSessionDidActivate(session)
            rtc.isAudioEnabled = true
            updateRoutes()
            if wantedRoute == nil { wantedRoute = defaultRoute() }
            applyRoute()
        } else {
            rtc.isAudioEnabled = false
            rtc.audioSessionDidDeactivate(session)
        }
    }

    private func updateRoutes() {
        let s = AVAudioSession.sharedInstance()
        let before = Set(audioRoutes.filter { $0.route == .bluetooth }.map(\.id))
        var list = [AudioOption(id: "iphone", route: .iPhone, name: "iPhone"), AudioOption(id: "speaker", route: .speaker, name: "Speaker")]
        for p in s.availableInputs ?? [] {
            switch p.portType {
            case .bluetoothHFP, .bluetoothLE, .carAudio: list.append(AudioOption(id: "bt:\(p.uid)", route: .bluetooth, name: p.portName))
            case .headsetMic, .usbAudio: if !list.contains(where: { $0.route == .headset }) { list.append(AudioOption(id: "headset", route: .headset, name: "Headset")) }
            default: break
            }
        }
        for o in s.currentRoute.outputs where o.portType == .headphones && !list.contains(where: { $0.route == .headset }) {
            list.append(AudioOption(id: "headset", route: .headset, name: "Headset"))
        }
        audioRoutes = list.sorted { $0.route < $1.route }
        // Bluetooth that connects during a call takes it over, as it does for a phone call.
        if wantedRoute != nil, let bt = audioRoutes.first(where: { $0.route == .bluetooth && !before.contains($0.id) }) { setAudioRoute(bt.id) }
        readCurrentRoute()
    }

    private func readCurrentRoute() {
        guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else { audioRoute = nil; return }
        let route: AudioRoute?
        switch out.portType {
        case .builtInReceiver: route = .iPhone
        case .builtInSpeaker: route = .speaker
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio: route = .bluetooth
        case .headphones, .usbAudio, .headsetMic: route = .headset
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

    private func applyRoute() {
        guard let id = wantedRoute, let opt = audioRoutes.first(where: { $0.id == id }) else { return }
        let s = AVAudioSession.sharedInstance()
        let inputs = s.availableInputs ?? []
        do {
            switch opt.route {
            case .speaker:
                try s.setPreferredInput(inputs.first { $0.portType == .builtInMic })
                try s.overrideOutputAudioPort(.speaker)
            case .iPhone:
                try s.overrideOutputAudioPort(.none)
                try s.setPreferredInput(inputs.first { $0.portType == .builtInMic })
            case .bluetooth:
                try s.overrideOutputAudioPort(.none)
                try s.setPreferredInput(inputs.first { "bt:\($0.uid)" == id })
            case .headset:
                try s.overrideOutputAudioPort(.none)
                try s.setPreferredInput(inputs.first { $0.portType == .headsetMic || $0.portType == .usbAudio })
            }
        } catch { /* the session is not active yet: applied again in didActivate */ }
        readCurrentRoute()
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
}
