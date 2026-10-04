import Foundation
import linphonesw

enum SipTransport: String, CaseIterable, Identifiable {
    case udp = "UDP", tcp = "TCP", tls = "TLS"
    var id: String { rawValue }
    var linphone: TransportType {
        switch self { case .udp: return .Udp; case .tcp: return .Tcp; case .tls: return .Tls }
    }
}

struct Account {
    var tenant: String
    var user: String
    var password: String
    var port: Int
    var transport: SipTransport
    var voicemailNumber: String

    static let baseDomain = "voip.n2it.co.za"
    /// Each client has its own PBX at <tenant>.voip.n2it.co.za
    var domain: String { tenant.isEmpty ? "" : "\(tenant.lowercased()).\(Account.baseDomain)" }
    var isConfigured: Bool { !tenant.isEmpty && !user.isEmpty && !password.isEmpty }

    /// Saved settings win; first launch seeds from Secrets.xcconfig via Info.plist.
    static func load() -> Account {
        let d = UserDefaults.standard
        let info = Bundle.main.infoDictionary ?? [:]
        return Account(
            tenant: d.string(forKey: "tenant") ?? info["SIPTenant"] as? String ?? "",
            user: d.string(forKey: "user") ?? info["SIPUser"] as? String ?? "",
            password: d.string(forKey: "password") ?? info["SIPPassword"] as? String ?? "",
            port: d.object(forKey: "port") as? Int ?? 5060,
            transport: SipTransport(rawValue: d.string(forKey: "transport") ?? "") ?? .udp,
            voicemailNumber: d.string(forKey: "voicemail") ?? "*97")
    }

    func save() {
        let d = UserDefaults.standard
        d.set(tenant, forKey: "tenant"); d.set(user, forKey: "user")
        d.set(password, forKey: "password"); d.set(port, forKey: "port")
        d.set(transport.rawValue, forKey: "transport"); d.set(voicemailNumber, forKey: "voicemail")
    }
}
