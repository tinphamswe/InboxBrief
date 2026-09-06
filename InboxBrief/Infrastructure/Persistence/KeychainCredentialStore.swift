import Foundation
import Security

struct KeychainCredentialStore: CredentialDataStoring {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func data(for accountID: MailAccount.ID) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw SecureStorageError.unavailable }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStorageError.unavailable
        }
    }

    func save(_ data: Data, for accountID: MailAccount.ID) async throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecureStorageError.unavailable }

        var insertion = identity
        attributes.forEach { insertion[$0.key] = $0.value }
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
            throw SecureStorageError.unavailable
        }
    }

    func removeData(for accountID: MailAccount.ID) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.unavailable
        }
    }
}
