import Foundation
import Security

enum DeepgramKeychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.localvoice.app"
    private static let transcriptionAccount = "DEEPGRAM_API_KEY"
    private static let billingAccount = "DEEPGRAM_BILLING_API_KEY"

    static func load() -> String? {
        load(account: transcriptionAccount)
    }

    static func loadBilling() -> String? {
        load(account: billingAccount)
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        try save(key, account: transcriptionAccount)
    }

    static func saveBilling(_ key: String) throws {
        try save(key, account: billingAccount)
    }

    private static func save(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Couldn’t save the key in Keychain (\(status))."
    }
}
