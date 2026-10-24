import Foundation
import Security
import RelayCore

/// Separate from cloud tokens and SQLite. No sync or network calls.
struct ResidentDetailsVault {
    private func query(scope: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "relay") + ".resident-details.v1",
         kSecAttrAccount as String: scope,
         kSecAttrSynchronizable as String: false]
    }
    func read(scope: String) throws -> ResidentDetails {
        var query = query(scope: scope)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return ResidentDetails() }
        guard status == errSecSuccess, let data = result as? Data else { throw RelayError.invalid("Saved personal details could not be opened. Unlock this device and retry; your saved details have not been replaced.") }
        return try CloudCodec.decode(ResidentDetails.self, data)
    }
    func save(_ value: ResidentDetails, scope: String) throws {
        let data = try CloudCodec.encode(value)
        let key = query(scope: scope)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RelayError.invalid("Could not securely save your personal details. Retry after unlocking the device.") }
        } else if status != errSecSuccess { throw RelayError.invalid("Could not update your saved personal details. They have not been replaced.") }
    }
    func clear(scope: String) throws {
        let status = SecItemDelete(query(scope: scope) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RelayError.invalid("Could not clear your saved details. Unlock this device and retry.") }
    }
}
