// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Stable per-install device identifier. Used as a tiebreaker in cross-device ordering.
/// Kept in the preferences, which survive deleting the app as the Keychain does, so reading it never asks for a
/// Keychain password; `loadOrCreate` is the legacy home an older install is read from once.
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
        configuration: RuntimeConfiguration = .current,
        identity: DeviceIdentity = DeviceIdentity(),
        defaults: UserDefaults = AppDefaults.store
    )
    -> String {
        guard configuration.mode.usesSystemIntegrations else { return "uitest-device-\(configuration.session)" }
        let saved: String = defaults.value(for: Setting.deviceID)
        if !saved.isEmpty { return saved }
        // An install from before the identity moved to the preferences reads the Keychain item once (one access prompt)
        // and never again; a new install never touches the Keychain for it.
        let id = (try? identity.load()) ?? UUID().uuidString
        defaults.set(id, for: Setting.deviceID)
        return id
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
