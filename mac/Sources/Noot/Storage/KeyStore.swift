import Foundation
import Security

enum KeyStoreError: Error, Equatable {
    case cannotGenerateRandom
    case keychainStoreFailed(OSStatus)
    case keychainReadFailed(OSStatus)
}

struct KeyStore {
    let service: String
    let account: String

    static let `default` = KeyStore(
        service: "com.lennertjansen.noot",
        account: "primary-database-key"
    )

    func loadOrCreate() throws -> Data {
        if let existing = try read() { return existing }
        let key = try Self.generateKey()
        try store(key)
        return key
    }

    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeyStoreError.cannotGenerateRandom }
        return Data(bytes)
    }

    private func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyStoreError.keychainReadFailed(status)
        }
        return data
    }

    private func store(_ key: Data) throws {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychainStoreFailed(status) }
    }
}
