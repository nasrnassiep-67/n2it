import Foundation
import PushKit

/// Registers for VoIP pushes, uploads the token to the N2IT push gateway,
/// and turns each incoming push into a CallKit call.
final class PushManager: NSObject, PKPushRegistryDelegate {
    static let shared = PushManager()
    private var registry: PKPushRegistry?
    private(set) var token: String?

    private static var isSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func start() {
        guard registry == nil else { return }
        registry = PKPushRegistry(queue: .main)
        registry?.delegate = self
        registry?.desiredPushTypes = [.voIP]
    }

    // MARK: Gateway registration

    private var gatewayURL: URL? {
        let host = Bundle.main.infoDictionary?["PushGatewayHost"] as? String ?? ""
        return host.isEmpty ? nil : URL(string: "https://\(host)/register")
    }

    /// Call after sign-in, and whenever the token changes.
    func uploadToken() {
        let acc = Account.load()
        guard let token, acc.isConfigured, let url = gatewayURL else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The gateway verifies these SIP credentials against the PBX before storing the token.
        let body: [String: Any] = [
            "tenant": acc.tenant.lowercased(), "user": acc.user, "password": acc.password,
            "token": token, "bundle": Bundle.main.bundleIdentifier ?? "",
            "sandbox": Self.isSandbox
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Call on log-out (and when switching away from an account) so the gateway stops pushing it to this device.
    func unregister(_ acc: Account) {
        guard let token, let base = gatewayURL?.deletingLastPathComponent() else { return }
        var req = URLRequest(url: base.appendingPathComponent("unregister"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject:
            ["tenant": acc.tenant.lowercased(), "user": acc.user, "token": token])
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        token = credentials.token.map { String(format: "%02x", $0) }.joined()
        uploadToken()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        token = nil
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let caller = payload.dictionaryPayload["caller"] as? String ?? "Incoming call"
        SipManager.shared.checkDnd()
        if SipManager.shared.dndActive {
            CallKitManager.shared.reportPushDeclined(caller: caller, completion: completion)
        } else {
            CallKitManager.shared.reportPushIncoming(caller: caller, completion: completion)
        }
        // The SIP socket is probably dead after suspension: re-register so the PBX delivers the INVITE.
        SipManager.shared.wake()
    }
}
