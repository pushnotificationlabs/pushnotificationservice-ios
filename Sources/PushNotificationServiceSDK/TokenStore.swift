import Foundation
import Security

protocol TokenStoring {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

/// Persists the last successfully-registered device token so the SDK can
/// automatically supply it as `old_token` on the next registration call —
/// the host app never manages rotation bookkeeping itself.
final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let account = "device-token"

    init(service: String = "com.pushnotificationservice.sdk") {
        self.service = service
    }

    func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        // Update-then-add (not delete-then-add): if an item already exists
        // and the update fails for any reason, the previous token is left
        // intact rather than silently dropped. A delete-then-add that fails
        // mid-way loses the rotation record — the next registration then
        // sends no old_token, the server never retires the previous
        // (now-orphaned) device-token row, and the same device ends up with
        // two active rows: double delivery, double quota billing.
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var query = baseQuery()
            query[kSecValueData as String] = Data(token.utf8)
            // AfterFirstUnlock (not the WhenUnlocked default): a device token
            // arrives via didRegisterForRemoteNotificationsWithDeviceToken,
            // which iOS can call on a background launch before the device has
            // been unlocked this boot — WhenUnlocked would fail that save.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            logIfFailed(addStatus, operation: "add")
        } else {
            logIfFailed(updateStatus, operation: "update")
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// A client SDK must never abort its host app over an OS-level Keychain
    /// status it doesn't control (device state, entitlement configuration,
    /// an unusual Keychain condition) — this used to be `assert()`, which
    /// SPM builds in the app's own configuration, so any integrator running
    /// Debug got a hard process abort on any non-success status. Debug-only,
    /// non-fatal logging preserves the diagnostic value without the crash.
    private func logIfFailed(_ status: OSStatus, operation: String) {
        #if DEBUG
        if status != errSecSuccess {
            print("PushNotificationServiceSDK: KeychainTokenStore.save (\(operation)) failed: OSStatus \(status)")
        }
        #endif
    }
}
