import Foundation
import linphonesw

enum SipTransport: String, CaseIterable, Identifiable, Codable {
    case udp = "UDP", tcp = "TCP", tls = "TLS"
    var id: String { rawValue }
    var linphone: TransportType {
        switch self { case .udp: return .Udp; case .tcp: return .Tcp; case .tls: return .Tls }
    }
}

struct Account: Codable {
    var tenant: String
    var user: String
    var password: String
    var port: Int
    var transport: SipTransport
    var voicemailNumber: String
    var srtp: Bool

    static let baseDomain = "voip.n2it.co.za"
    /// Each client has its own PBX at <tenant>.voip.n2it.co.za
    var domain: String { tenant.isEmpty ? "" : "\(tenant.lowercased()).\(Account.baseDomain)" }
    var isConfigured: Bool { !tenant.isEmpty && !user.isEmpty && !password.isEmpty }
    /// Same extension on the same PBX = same account.
    func sameAs(_ o: Account) -> Bool { domain == o.domain && user == o.user }
    var key: String { "\(user)@\(domain)" }

    static let blank = Account(tenant: "", user: "", password: "", port: 5061, transport: .tls, voicemailNumber: "*97", srtp: true)

    /// Saved settings win; first launch seeds from Secrets.xcconfig via Info.plist.
    static func load() -> Account {
        let d = UserDefaults.standard
        let info = d.bool(forKey: signedOutKey) ? [:] : (Bundle.main.infoDictionary ?? [:])
        return Account(
            tenant: (d.string(forKey: "tenant") ?? info["SIPTenant"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            user: (d.string(forKey: "user") ?? info["SIPUser"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            password: Keychain.get("password") ?? info["SIPPassword"] as? String ?? "",
            port: d.object(forKey: "port") as? Int ?? 5061,
            transport: SipTransport(rawValue: d.string(forKey: "transport") ?? "") ?? .tls,
            voicemailNumber: d.string(forKey: "voicemail") ?? "*97",
            srtp: d.object(forKey: "srtp") as? Bool ?? true)
    }

    /// Strips stray spaces (autocorrect, paste) so the SIP URI stays valid.
    mutating func save() {
        tenant = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = UserDefaults.standard
        d.set(false, forKey: Account.signedOutKey)
        d.set(tenant, forKey: "tenant"); d.set(user, forKey: "user")
        Keychain.set(password, for: "password"); d.set(port, forKey: "port")
        d.set(transport.rawValue, forKey: "transport"); d.set(voicemailNumber, forKey: "voicemail"); d.set(srtp, forKey: "srtp")
    }

    /// Sign out: forget the account on this device.
    static func clear() {
        let d = UserDefaults.standard
        d.set(true, forKey: signedOutKey)
        ["tenant", "user", "port", "transport", "voicemail", "srtp", "recents"].forEach { d.removeObject(forKey: $0) }
        Keychain.delete("password")
    }

    /// Dev defaults from Secrets.xcconfig must not silently re-login after sign-out.
    static var signedOutKey: String { "signedOut" }

    // MARK: More than one account (one active at a time)
    // The active account stays in the keys above; the others are a JSON list in the Keychain (they hold passwords).

    /// Saved accounts that are not active.
    static func others() -> [Account] {
        guard let json = Keychain.get("others"), let list = try? JSONDecoder().decode([Account].self, from: Data(json.utf8))
        else { return [] }
        return list.filter(\.isConfigured)
    }

    private static func saveOthers(_ list: [Account]) {
        if let d = try? JSONEncoder().encode(list) { Keychain.set(String(decoding: d, as: UTF8.self), for: "others") }
    }

    /// Make `a` the active account; the previous active one stays in the list.
    static func activate(_ a: Account) {
        let current = load()
        let rest = others().filter { !$0.sameAs(a) && !(current.isConfigured && $0.sameAs(current)) }
        saveOthers((current.isConfigured && !current.sameAs(a) ? [current] : []) + rest)
        var a = a
        a.save()
    }

    /// Log `a` out and forget it. Returns the account that is active afterwards (nil = none left).
    static func remove(_ a: Account) -> Account? {
        let current = load()
        if !current.sameAs(a) {
            saveOthers(others().filter { !$0.sameAs(a) })
            return current.isConfigured ? current : nil
        }
        guard var next = others().first else { clear(); return nil }
        saveOthers(Array(others().dropFirst()))
        next.save()
        return next
    }
}
