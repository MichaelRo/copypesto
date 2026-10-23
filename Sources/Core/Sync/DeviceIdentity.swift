// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Stable per-install device identifier. Used as a tiebreaker in cross-device ordering.
/// Stored in the Keychain so it survives app reinstall
/// (Keychain items persist across app deletion when accessibleWhenUnlockedThisDeviceOnly).
public struct DeviceIdentity: Sendable {
    public let service: String
    public let account: String

    public init(service: String = AppIdentity.keychainService, account: String = AppIdentity.deviceIDAccount) {
        self.service = service
        self.account = account
    }

    public func loadOrCreate() throws -> String {
        if let existing = try load() { return existing }
        try store(UUID().uuidString)
        // The add tolerates an existing item, so the stored value is the identity, not the one just made.
        guard let stored = try load() else { throw BlobEncryption.Error.keychainAccessFailed(errSecDuplicateItem) }
        return stored
    }

    /// The identity this process uses: the Keychain's in the app, and a fixed one per session under a test launch,
    /// which
    /// must not read the login Keychain (an item made by another build blocks the reader on an access prompt, as the
    /// restore window of the key-loss UI test did).
    public static func current(
        configuration: RuntimeConfiguration = .current, identity: DeviceIdentity = DeviceIdentity()
    )
    -> String {
        guard configuration.mode.usesSystemIntegrations else { return "uitest-device-\(configuration.session)" }
        return (try? identity.loadOrCreate()) ?? "unknown"
    }

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw BlobEncryption.Error.keychainAccessFailed(status)
        }
    }

    func store(_ value: String) throws {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw BlobEncryption.Error.keychainAccessFailed(status)
        }
    }
}
