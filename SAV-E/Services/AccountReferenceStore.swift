import Foundation
import Security

enum AccountReferenceStoreError: Error {
    case invalidReference
    case invalidStoredData
    case keychain(OSStatus)
}

struct KeychainAccountReferenceStore: AccountReferenceStoring {
    static let shared = KeychainAccountReferenceStore()

    private let service = "com.wanderly.app.account-gate"
    private let account = "last-confirmed-account-ref-v1"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AccountReferenceStoreError.keychain(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              AccountGatePolicy.isValidAccountRef(value) else {
            throw AccountReferenceStoreError.invalidStoredData
        }
        return value
    }

    func save(_ accountRef: String) throws {
        guard AccountGatePolicy.isValidAccountRef(accountRef),
              let data = accountRef.data(using: .utf8) else {
            throw AccountReferenceStoreError.invalidReference
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AccountReferenceStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AccountReferenceStoreError.keychain(addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
