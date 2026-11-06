import Foundation
import Security

struct KeychainError: LocalizedError {
    var status: OSStatus

    var errorDescription: String? {
        "The Keychain could not store the read token (\(status)). Check the App Group and team ID in Shared.xcconfig."
    }
}

enum SecretStore {
    static func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return token
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery()
        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let updated = SecItemUpdate(
                query as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ] as CFDictionary
            )
            guard updated == errSecSuccess else { throw KeychainError(status: updated) }
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    static func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.keychainService,
            kSecAttrAccount as String: AppIdentity.keychainAccount,
            kSecAttrAccessGroup as String: AppIdentity.keychainAccessGroup,
        ]
    }
}
