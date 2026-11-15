// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Keychain items in one named access group that the iOS app and its AutoFill extension both hold (ADR 0051): this
/// device only, never synchronized, readable after the first unlock. Every query names the group, so nothing here
/// reads or writes the app's own items (the history key, the inbox key, the sync keys).
public struct SharedKeychainSecretStore: SecretStoring {
    public let accessGroup: String

    public init(accessGroup: String) {
        self.accessGroup = accessGroup
    }

    private func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    public func read(service: String, account: String) throws -> Data? {
        var request = query(service: service, account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(request as CFDictionary, &item) {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        case let status: throw KeychainSecretStore.Failure(status: status)
        }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        var attributes = query(service: service, account: account)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainSecretStore.Failure(status: status)
        }
    }

    public func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }
}
