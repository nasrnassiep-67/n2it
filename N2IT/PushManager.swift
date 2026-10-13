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

    /// Every N2IT server serves the gateway at /push on all its company addresses, so each account
    /// registers with its own server (falls back to Info.plist PushGatewayHost).
    private func gatewayURL(_ acc: Account, _ action: String) -> URL? {
        let host = acc.domain.isEmpty ? Bundle.main.infoDictionary?["PushGatewayHost"] as? String ?? "" : "\(acc.domain)/push"
        return host.isEmpty ? nil : URL(string: "https://\(host)/\(action)")
    }

    /// Call after sign-in, and whenever the token changes.
    func uploadToken() {
        let acc = Account.load()
        guard let token, acc.isConfigured, let url = gatewayURL(acc, "register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The gateway verifies these SIP credentials against the PBX before storing the token.
        let body: [String: Any] = [
            "tenant": acc.tenantKey, "user": acc.user, "password": acc.password,
            "token": token, "bundle": Bundle.main.bundleIdentifier ?? "",
            "sandbox": Self.isSandbox
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Call on log-out (and when switching away from an account) so the gateway stops pushing it to this device.
    func unregister(_ acc: Account) {
        guard let token, let url = gatewayURL(acc, "unregister") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject:
            ["tenant": acc.tenantKey, "user": acc.user, "token": token])
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
        // {"type":"cancel","reason":"answered"|"ended"}: answered elsewhere / caller hung up before we reconnected
        if payload.dictionaryPayload["type"] as? String == "cancel" {
            let answered = payload.dictionaryPayload["reason"] as? String == "answered"
            CallKitManager.shared.reportPushCancelled(answeredElsewhere: answered, completion: completion)
            return
        }
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
