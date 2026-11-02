import Foundation
import Security

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "za.co.n2it.softphone",
         kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        // Readable when a push wakes the app (after first unlock), and ThisDeviceOnly: never copied to another phone by
        // an iCloud or computer backup, so a new phone signs in again (as Android 0.2.9: no backup of the app's data).
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    /// Items saved before 0.3.6 could be copied by a backup: save them again as ThisDeviceOnly. Once per install.
    static func migrateToThisDeviceOnly() {
        guard !UserDefaults.standard.bool(forKey: "keychainThisDeviceOnly") else { return }
        for key in ["password", "others"] { if let v = get(key) { set(v, for: key) } }
        UserDefaults.standard.set(true, forKey: "keychainThisDeviceOnly")
    }

    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
