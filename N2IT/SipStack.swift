import Foundation
import CryptoKit

/*
 * N2IT's own SIP client over a secure WebSocket (RFC 7118), the same way the desktop app (JsSIP) and Android 0.3.0 talk
 * to FusionPBX: wss://<company>.voip.n2it.co.za/wss on port 443, which nginx passes to FreeSWITCH's WSS listener. Audio
 * is WebRTC (CallMedia.swift). It only does what the app needs: register, calls in and out, hold, transfer, voicemail lamp.
 * Port of Android's SipStack.kt. Replaces the Linphone SDK (AGPLv3; a closed-source licence is not affordable).
 * Everything runs on the main thread, so the call logic in SipManager needs no locks.
 */

/// Test builds: timestamped line on the Xcode / devicectl console (start lines only, never passwords).
func dlog(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    print("[N2IT \(f.string(from: Date()))] \(s)")
}

@discardableResult
func later(_ seconds: TimeInterval, _ block: @escaping () -> Void) -> DispatchWorkItem {
    let w = DispatchWorkItem(block: block)
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    return w
}

private func rx(_ pattern: String, _ s: String, group: Int = 1) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > group,
          let r = Range(m.range(at: group), in: s) else { return nil }
    return String(s[r])
}

/// One SIP request or response. Header names keep their case; lookups ignore case and know the compact forms.
final class SipMsg {
    var startLine: String
    var headers: [(String, String)]
    var body: String

    init(_ startLine: String, headers: [(String, String)] = [], body: String = "") {
        self.startLine = startLine; self.headers = headers; self.body = body
    }

    private var parts: [Substring] { startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false) }
    var isRequest: Bool { !startLine.hasPrefix("SIP/2.0") }
    var method: String { isRequest ? String(parts.first ?? "") : cseqMethod }
    var uri: String { parts.count > 1 ? String(parts[1]) : "" }
    var status: Int { isRequest ? 0 : (parts.count > 1 ? Int(parts[1]) ?? 0 : 0) }
    var reason: String { isRequest ? "" : (parts.count > 2 ? String(parts[2]) : "") }
    var cseq: Int { Int((h("CSeq") ?? "").trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") ?? 0 }
    var cseqMethod: String {
        let p = (h("CSeq") ?? "").trimmingCharacters(in: .whitespaces).split(separator: " ")
        return p.count > 1 ? String(p[1]) : ""
    }
    var callId: String { h("Call-ID") ?? "" }
    var fromTag: String? { Self.tagOf(h("From")) }
    var toTag: String? { Self.tagOf(h("To")) }
    var branch: String? { h("Via").flatMap { rx(";\\s*branch=([^;,\\s]+)", $0) } }
    var hasSdp: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (h("Content-Type") ?? "").lowercased().contains("sdp")
    }

    private static let compact = ["v": "Via", "f": "From", "t": "To", "i": "Call-ID", "m": "Contact", "l": "Content-Length",
                                  "c": "Content-Type", "k": "Supported", "o": "Event", "r": "Refer-To", "x": "Session-Expires",
                                  "u": "Allow-Events", "b": "Referred-By", "e": "Content-Encoding", "s": "Subject"]
    private static func full(_ n: String) -> String { compact[n.lowercased()] ?? n }

    func h(_ name: String) -> String? { all(name).first }
    func all(_ name: String) -> [String] {
        let n = Self.full(name).lowercased()
        return headers.filter { Self.full($0.0).lowercased() == n }.map { $0.1 }
    }
    @discardableResult func add(_ name: String, _ value: String) -> SipMsg { headers.append((name, value)); return self }
    @discardableResult func set(_ name: String, _ value: String) -> SipMsg { remove(name); headers.append((name, value)); return self }
    @discardableResult func remove(_ name: String) -> SipMsg {
        let n = Self.full(name).lowercased()
        headers.removeAll { Self.full($0.0).lowercased() == n }
        return self
    }

    func encode() -> String {
        var s = startLine + "\r\n"
        for (k, v) in headers where Self.full(k).lowercased() != "content-length" { s += "\(k): \(v)\r\n" }
        s += "Content-Length: \(body.utf8.count)\r\n\r\n" + body
        return s
    }

    static func tagOf(_ v: String?) -> String? { v.flatMap { rx(";\\s*tag=([^;>\\s,]+)", $0) } }
    /// "Nasr" <sip:1002@n2test.voip.n2it.co.za>;tag=x -> sip:1002@n2test.voip.n2it.co.za
    static func uriOf(_ v: String?) -> String {
        guard let s = v else { return "" }
        if let u = rx("<([^>]*)>", s) { return u }
        return s.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
    static func userOf(_ uri: String) -> String {
        var s = Substring(uri)
        if let i = s.firstIndex(of: ":") { s = s[s.index(after: i)...] }
        if let i = s.firstIndex(of: "@") { s = s[..<i] }
        if let i = s.firstIndex(of: ";") { s = s[..<i] }
        return String(s)
    }
    static func nameOf(_ v: String?) -> String? {
        guard let s = v, let i = s.firstIndex(of: "<") else { return nil }
        let n = s[..<i].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    static func parse(_ text: String) -> SipMsg? {
        guard let sep = text.range(of: "\r\n\r\n") else { return nil }
        let lines = String(text[..<sep.lowerBound]).components(separatedBy: "\r\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        let msg = SipMsg(first)
        for line in lines.dropFirst() where !line.isEmpty {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), let last = msg.headers.popLast() {   // folded line
                msg.headers.append((last.0, last.1 + " " + line.trimmingCharacters(in: .whitespaces))); continue
            }
            guard let i = line.firstIndex(of: ":"), i != line.startIndex else { continue }
            msg.headers.append((line[..<i].trimmingCharacters(in: .whitespaces), line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)))
        }
        msg.body = String(text[sep.upperBound...])
        return msg
    }
}

/// A SIP dialog (a call, or a REFER's subscription inside it): what requests inside the call need.
final class Dialog {
    let callId: String, localTag: String, localUri: String, remoteUri: String
    var remoteTag: String, remoteTarget: String, routes: [String], localCseq: Int
    init(callId: String, localTag: String, remoteTag: String, localUri: String, remoteUri: String,
         remoteTarget: String, routes: [String], localCseq: Int) {
        self.callId = callId; self.localTag = localTag; self.remoteTag = remoteTag; self.localUri = localUri
        self.remoteUri = remoteUri; self.remoteTarget = remoteTarget; self.routes = routes; self.localCseq = localCseq
    }
}

protocol SipUaEvents: AnyObject {
    func onRegistration(_ state: SipUa.RegState, _ code: Int, _ reason: String)
    /// A request from the PBX (INVITE, BYE, CANCEL, NOTIFY…); answer it with `SipUa.reply`.
    func onRequest(_ req: SipMsg)
    func onTransportDown()
}

/// The SIP client: one WebSocket, the registration, and sending/receiving messages.
final class SipUa: NSObject, URLSessionWebSocketDelegate {
    enum RegState { case none, progress, ok, failed }

    static let allow = "INVITE, ACK, CANCEL, BYE, UPDATE, OPTIONS, REFER, NOTIFY, INFO, MESSAGE"

    private weak var events: SipUaEvents?
    init(events: SipUaEvents) {
        self.events = events
        viaHost = Self.randomToken(12).lowercased() + ".invalid"
        contactUser = Self.randomToken(8).lowercased()
        regCallId = Self.randomToken(22)
        super.init()
    }

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    private(set) var user = ""
    private(set) var domain = ""
    private var password = ""
    var userAgent = "N2IT Phone iOS"
    private var ws: URLSessionWebSocketTask?
    private(set) var connected = false
    private var wanted = false   // keep connected and registered (false after stop())
    private var backoff: TimeInterval = 2
    private var pingTimer: Timer?

    /// Made-up host for our Via and Contact: over a WebSocket the PBX answers on the socket, not to an address.
    private let viaHost: String
    private let contactUser: String
    var contact: String { "<sip:\(contactUser)@\(viaHost);transport=ws>" }
    var aor: String { "sip:\(user)@\(domain)" }

    // MARK: Registration
    private let regCallId: String
    private var regCseq = 0
    private(set) var regState = RegState.none
    private let expires = 600   // re-register every 10 min; a mobile network forgets an idle connection after a few
    private var refreshItem: DispatchWorkItem?
    private var reconnectItem: DispatchWorkItem?

    private static func randomToken(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
    func token(_ n: Int) -> String { Self.randomToken(n) }

    func start(user: String, password: String, domain: String) {
        stop(unregister: regState == .ok)
        self.user = user.trimmingCharacters(in: .whitespaces); self.password = password; self.domain = domain
        wanted = true; backoff = 2
        connect()
    }

    /// Disconnect and stay disconnected; `unregister` first so the PBX stops sending calls here.
    func stop(unregister: Bool = true) {
        wanted = false
        refreshItem?.cancel(); reconnectItem?.cancel(); pingTimer?.invalidate()
        let old = ws
        let close = { [weak self] in
            guard let self else { return }
            if self.ws === old {
                self.ws = nil; self.connected = false
                self.pending.values.forEach { $0.timeout.cancel() }; self.pending.removeAll()
            }
            old?.cancel(with: .normalClosure, reason: nil)
        }
        if unregister && connected && regState == .ok {
            var done = false
            let finish = { if !done { done = true; close() } }
            request(registerRequest(0)) { if $0.status >= 200 { finish() } }
            later(2) { finish() }
        } else { close() }
        setReg(.none, 0, "")
    }

    /// Re-register now (app back on screen); reconnects first if the socket is gone.
    func refreshNow() {
        dlog("refreshNow (connected \(connected))")
        guard wanted else { return }
        if connected { register() } else { reconnectItem?.cancel(); connect() }
    }

    /// The network changed or the app was suspended: the old socket is dead even if it does not know it yet.
    func reconnectNow() {
        dlog("reconnectNow (wanted \(wanted))")
        guard wanted else { return }
        ws?.cancel(with: .goingAway, reason: nil); ws = nil; connected = false
        pingTimer?.invalidate()
        reconnectItem?.cancel(); connect()
    }

    private func connect() {
        guard wanted, !domain.isEmpty, let url = URL(string: "wss://\(domain)/wss") else { return }
        ws?.cancel(with: .goingAway, reason: nil)
        dlog("connecting wss://\(domain)/wss")
        setReg(.progress, 0, "Connecting…")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("sip", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let t = session.webSocketTask(with: req)
        ws = t
        t.resume()
        listen(t)
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, t === self.ws else { return }
                switch result {
                case .success(let m):
                    switch m {
                    case .string(let s): self.receive(s)
                    case .data(let d): if let s = String(data: d, encoding: .utf8) { self.receive(s) }
                    @unknown default: break
                    }
                    self.listen(t)
                case .failure(let e): self.lost(e.localizedDescription)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard t === ws else { return }
        connected = true; backoff = 2
        dlog("websocket open")
        pingTimer?.invalidate()
        // Keeps mobile networks and NAT from dropping an idle connection (the PBX answers pings)
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self, let t = self.ws else { return }
            t.sendPing { err in if err != nil { DispatchQueue.main.async { if t === self.ws { self.lost("ping failed") } } } }
        }
        register()
    }

    func urlSession(_ session: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if t === ws { lost("closed") }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let t = task as? URLSessionWebSocketTask, t === ws, error != nil { lost(error?.localizedDescription ?? "no connection") }
    }

    private func lost(_ why: String) {
        dlog("connection lost: \(why)")
        ws?.cancel(with: .goingAway, reason: nil)
        connected = false; ws = nil
        pingTimer?.invalidate()
        refreshItem?.cancel()
        for tx in Array(pending.values) {
            tx.timeout.cancel(); pending.removeValue(forKey: tx.branch)
            tx.onResponse(synthetic(tx.req, 503, "Connection lost"))
        }
        events?.onTransportDown()
        guard wanted else { return }
        setReg(.progress, 0, "Cannot reach \(domain) (retrying)")
        reconnectItem = later(backoff) { [weak self] in self?.connect() }
        backoff = min(backoff * 2, 30)
    }

    private func setReg(_ s: RegState, _ code: Int, _ reason: String) { regState = s; events?.onRegistration(s, code, reason) }

    private func registerRequest(_ exp: Int) -> SipMsg {
        SipMsg("REGISTER sip:\(domain) SIP/2.0")
            .add("Via", via()).add("Max-Forwards", "70")
            .add("To", "<\(aor)>").add("From", "<\(aor)>;tag=\(token(10))")
            .add("Call-ID", regCallId).add("CSeq", "\(nextRegCseq()) REGISTER")
            .add("Contact", "\(contact);expires=\(exp)").add("Expires", "\(exp)")
            .add("Allow", Self.allow).add("Supported", "path, outbound").add("User-Agent", userAgent)
    }
    private func nextRegCseq() -> Int { regCseq += 1; return regCseq }

    private func register() {
        refreshItem?.cancel()
        guard connected else { return }
        if regState != .ok { setReg(.progress, 0, "Registering…") }
        request(registerRequest(expires)) { [weak self] res in
            guard let self, self.wanted else { return }
            if (200...299).contains(res.status) {
                // The PBX may shorten the time: re-register at 90% of what it granted
                var granted = Int((res.h("Expires") ?? "").trimmingCharacters(in: .whitespaces)) ?? self.expires
                for c in res.all("Contact") where c.contains(self.contactUser) {
                    if let e = rx("expires=(\\d+)", c).flatMap({ Int($0) }) { granted = e; break }
                }
                self.setReg(.ok, res.status, res.reason)
                self.refreshItem = later(Double(min(max(granted, 60), self.expires)) * 0.9) { [weak self] in self?.register() }
            } else if res.status >= 300 {
                self.setReg(.failed, res.status, res.reason)
                // A wrong password is not retried (the PBX bans the whole network after a few: fail2ban);
                // anything else (PBX busy, connection lost) tries again in a minute
                if ![401, 403, 407, 404].contains(res.status) {
                    self.refreshItem = later(60) { [weak self] in self?.register() }
                }
            }
        }
    }

    // MARK: Sending and receiving
    private final class ClientTx {
        let branch: String, req: SipMsg, onResponse: (SipMsg) -> Void, timeout: DispatchWorkItem
        let onRetry: ((SipMsg) -> Void)?, authTried: Bool
        init(branch: String, req: SipMsg, onResponse: @escaping (SipMsg) -> Void, timeout: DispatchWorkItem,
             onRetry: ((SipMsg) -> Void)?, authTried: Bool = false) {
            self.branch = branch; self.req = req; self.onResponse = onResponse; self.timeout = timeout
            self.onRetry = onRetry; self.authTried = authTried
        }
    }
    private var pending: [String: ClientTx] = [:]

    func via() -> String { "SIP/2.0/WSS \(viaHost);branch=z9hG4bK\(token(16))" }

    @discardableResult
    func send(_ msg: SipMsg) -> Bool {
        guard connected, let w = ws else { dlog("send dropped (not connected): \(msg.startLine)"); return false }
        dlog("-> \(msg.startLine)")
        w.send(.string(msg.encode())) { _ in }
        return true
    }

    /// Send a request and get every response to it (provisional too). A 401/407 is answered once with the password;
    /// the retry gets a new CSeq (`onRetry` lets a call keep its dialog's CSeq in step). No answer in 32 s = 408.
    func request(_ req: SipMsg, onRetry: ((SipMsg) -> Void)? = nil, onResponse: @escaping (SipMsg) -> Void) {
        guard let branch = req.branch else { return }
        track(ClientTx(branch: branch, req: req, onResponse: onResponse, timeout: timeoutFor(branch, req, onResponse), onRetry: onRetry))
    }
    private func timeoutFor(_ branch: String, _ req: SipMsg, _ onResponse: @escaping (SipMsg) -> Void) -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            if self?.pending.removeValue(forKey: branch) != nil { onResponse(self!.synthetic(req, 408, "Request Timeout")) }
        }
    }
    private func track(_ tx: ClientTx) {
        pending[tx.branch] = tx
        DispatchQueue.main.asyncAfter(deadline: .now() + (tx.req.method == "INVITE" ? 180 : 32), execute: tx.timeout)
        if !send(tx.req) {
            pending.removeValue(forKey: tx.branch); tx.timeout.cancel()
            tx.onResponse(synthetic(tx.req, 503, "Not connected"))
        }
    }

    /// Answer an INVITE that is still in progress with CANCEL (same branch, as RFC 3261 wants).
    func cancel(_ invite: SipMsg) {
        let c = SipMsg("CANCEL \(invite.uri) SIP/2.0")
        for n in ["Via", "To", "From", "Call-ID"] { if let v = invite.h(n) { c.add(n, v) } }
        invite.all("Route").forEach { c.add("Route", $0) }
        c.add("CSeq", "\(invite.cseq) CANCEL").add("Max-Forwards", "70").add("User-Agent", userAgent)
        send(c)
    }

    private func receive(_ text: String) {
        guard let msg = SipMsg.parse(text) else { return }
        dlog("<- \(msg.startLine)")
        if msg.isRequest { events?.onRequest(msg); return }
        guard let b = msg.branch, let tx = pending[b] else { return }
        if msg.status == 401 || msg.status == 407 {
            if msg.cseqMethod == "INVITE" { ackFailure(tx.req, msg) }
            guard !tx.authTried, !password.isEmpty, let retry = authorised(tx.req, msg), let nb = retry.branch else { finish(tx, msg); return }
            pending.removeValue(forKey: tx.branch); tx.timeout.cancel()
            tx.onRetry?(retry)
            track(ClientTx(branch: nb, req: retry, onResponse: tx.onResponse, timeout: timeoutFor(nb, retry, tx.onResponse),
                           onRetry: tx.onRetry, authTried: true))
            return
        }
        if msg.status >= 200 {
            // A failed INVITE is acknowledged here (same branch); a 2xx is acknowledged by the call (new branch)
            if msg.cseqMethod == "INVITE" && msg.status >= 300 { ackFailure(tx.req, msg) }
            finish(tx, msg)
        } else { tx.onResponse(msg) }
    }

    private func finish(_ tx: ClientTx, _ res: SipMsg) {
        pending.removeValue(forKey: tx.branch); tx.timeout.cancel()
        tx.onResponse(res)
    }

    private func ackFailure(_ invite: SipMsg, _ res: SipMsg) {
        let ack = SipMsg("ACK \(invite.uri) SIP/2.0")
        if let v = invite.h("Via") { ack.add("Via", v) }
        ack.add("Max-Forwards", "70").add("To", res.h("To") ?? "").add("From", invite.h("From") ?? "")
            .add("Call-ID", invite.callId).add("CSeq", "\(invite.cseq) ACK")
        invite.all("Route").forEach { ack.add("Route", $0) }
        send(ack)
    }

    private static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Copy of `req` with the answer to the PBX's password challenge (digest, MD5).
    private func authorised(_ req: SipMsg, _ challenge: SipMsg) -> SipMsg? {
        let proxy = challenge.status == 407
        guard let ch = challenge.h(proxy ? "Proxy-Authenticate" : "WWW-Authenticate") else { return nil }
        func p(_ n: String) -> String? { rx("\(n)=\"?([^\",]*)\"?", ch) }
        let realm = p("realm") ?? domain
        guard let nonce = p("nonce") else { return nil }
        let qop = p("qop")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.lowercased() == "auth" }
        let algorithm = p("algorithm") ?? "MD5"
        guard algorithm.lowercased() == "md5" else { return nil }
        let uri = req.uri
        let ha1 = Self.md5("\(user):\(realm):\(password)")
        let ha2 = Self.md5("\(req.method):\(uri)")
        let cnonce = token(16).lowercased()
        let nc = "00000001"
        let response = qop != nil ? Self.md5("\(ha1):\(nonce):\(nc):\(cnonce):\(qop!):\(ha2)") : Self.md5("\(ha1):\(nonce):\(ha2)")
        var value = "Digest username=\"\(user)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", response=\"\(response)\", algorithm=MD5"
        if let o = p("opaque") { value += ", opaque=\"\(o)\"" }
        if qop != nil { value += ", qop=\(qop!), nc=\(nc), cnonce=\"\(cnonce)\"" }
        let copy = SipMsg(req.startLine, headers: req.headers, body: req.body)
        copy.remove("Authorization").remove("Proxy-Authorization")
        copy.set("Via", via())
        copy.set("CSeq", "\(req.cseq + 1) \(req.method)")
        copy.add(proxy ? "Proxy-Authorization" : "Authorization", value)
        if req.method == "REGISTER" { regCseq = req.cseq + 1 }
        return copy
    }

    /// A response to the PBX's request `req`: Via, From, To (with our `toTag`), Call-ID and CSeq copied over.
    func reply(_ req: SipMsg, _ code: Int, _ reason: String, toTag: String? = nil, extra: [(String, String)] = [], body: String = "") {
        let res = SipMsg("SIP/2.0 \(code) \(reason)")
        req.all("Via").forEach { res.add("Via", $0) }
        req.all("Record-Route").forEach { res.add("Record-Route", $0) }
        let to = req.h("To") ?? ""
        res.add("From", req.h("From") ?? "")
        res.add("To", (toTag != nil && SipMsg.tagOf(to) == nil && code > 100) ? "\(to);tag=\(toTag!)" : to)
        res.add("Call-ID", req.callId).add("CSeq", req.h("CSeq") ?? "")
        res.add("User-Agent", userAgent)
        extra.forEach { res.add($0.0, $0.1) }
        if !body.isEmpty { res.add("Content-Type", "application/sdp") }
        res.body = body
        send(res)
    }

    /// A request inside `d` (BYE, re-INVITE, REFER, ACK…).
    func inDialog(_ d: Dialog, _ method: String, cseq: Int? = nil) -> SipMsg {
        let n: Int
        if let cseq { n = cseq } else { d.localCseq += 1; n = d.localCseq }
        let m = SipMsg("\(method) \(d.remoteTarget) SIP/2.0")
            .add("Via", via()).add("Max-Forwards", "70")
            .add("To", "<\(d.remoteUri)>;tag=\(d.remoteTag)").add("From", "<\(d.localUri)>;tag=\(d.localTag)")
            .add("Call-ID", d.callId).add("CSeq", "\(n) \(method)")
        d.routes.forEach { m.add("Route", $0) }
        if method != "ACK" && method != "BYE" { m.add("Contact", contact) }
        m.add("User-Agent", userAgent)
        return m
    }

    private func synthetic(_ req: SipMsg, _ code: Int, _ reason: String) -> SipMsg {
        SipMsg("SIP/2.0 \(code) \(reason)").add("Call-ID", req.callId).add("CSeq", "\(req.cseq) \(req.method)")
    }
}
