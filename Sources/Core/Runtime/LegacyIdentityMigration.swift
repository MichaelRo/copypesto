// SPDX-License-Identifier: MIT
import Foundation
import Security

public protocol SecretStoring: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String)
}

public struct KeychainSecretStore: SecretStoring {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        case let status: throw Failure(status: status)
        }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure(status: status) }
    }

    public func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Moves an install made under the old bundle ID (`io.pesto.app`) to the current one: the data folder, the
/// preferences and the encryption key. Each step stands alone and can be retried on the next launch, and the old key
/// is deleted only once the history it protects has been moved, so a half-finished migration never strands clips.
public struct LegacyIdentityMigration {
    public enum StoreOutcome: Equatable, Sendable {
        case nothingToMove
        case moved
        case alreadyCurrent
        case conflict
        case failed
    }

    public enum KeyOutcome: Equatable, Sendable {
        case nothingToMove
        case alreadyCurrent
        case moved
        case movedKeepingOld
        case failed
    }

    public struct Report: Equatable, Sendable {
        public var store: StoreOutcome
        public var preferencesCopied: Int
        public var key: KeyOutcome
    }

    private let fileManager: FileManager
    private let applicationSupport: URL
    private let legacyDefaults: UserDefaults
    private let legacyDomain: String
    private let currentDefaults: UserDefaults
    private let secrets: any SecretStoring

    public init(
        applicationSupport: URL,
        legacyDefaults: UserDefaults,
        legacyDomain: String = AppIdentity.legacyBundleID,
        currentDefaults: UserDefaults,
        secrets: any SecretStoring,
        fileManager: FileManager = .default
    ) {
        self.applicationSupport = applicationSupport
        self.legacyDefaults = legacyDefaults
        self.legacyDomain = legacyDomain
        self.currentDefaults = currentDefaults
        self.secrets = secrets
        self.fileManager = fileManager
    }

    @discardableResult
    public func run() -> Report {
        let store = moveSupportDirectory()
        let copied = copyPreferences()
        let key = moveKey(storeOutcome: store)
        return Report(store: store, preferencesCopied: copied, key: key)
    }

    private var legacyDirectory: URL {
        applicationSupport.appendingPathComponent(AppIdentity.legacySupportDirectoryName, isDirectory: true)
    }

    private var currentDirectory: URL {
        applicationSupport.appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
    }

    private func moveSupportDirectory() -> StoreOutcome {
        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return .nothingToMove }
        if fileManager.fileExists(atPath: currentDirectory.path) {
            let entries = (try? fileManager.contentsOfDirectory(atPath: currentDirectory.path)) ?? ["?"]
            guard entries.isEmpty else { return .conflict }
            try? fileManager.removeItem(at: currentDirectory)
        }
        do {
            try fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
            return .moved
        } catch {
            return .failed
        }
    }

    /// Copies the old preferences domain the first time only, recognised by its own marker and by the new domain not
    /// yet knowing whether onboarding happened (resetting that flag must not bring the old settings back).
    /// System-owned keys are left behind.
    private func copyPreferences() -> Int {
        guard !currentDefaults.value(for: Setting.legacyPreferencesCopied) else { return 0 }
        defer { currentDefaults.set(true, for: Setting.legacyPreferencesCopied) }
        guard !currentDefaults.hasValue(for: Setting.hasOnboarded),
              let old = legacyDefaults.persistentDomain(forName: legacyDomain) else { return 0 }
        var copied = 0
        for (key, value) in old where !Self.isSystemKey(key) {
            currentDefaults.set(value, forKey: key)
            copied += 1
        }
        return copied
    }

    private static func isSystemKey(_ key: String) -> Bool {
        key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple.")
    }

    private func moveKey(storeOutcome: StoreOutcome) -> KeyOutcome {
        do {
            if try secrets.read(service: AppIdentity.keychainService, account: AppIdentity.blobKeyAccount) != nil {
                return .alreadyCurrent
            }
            guard let key = try secrets.read(
                service: AppIdentity.legacyKeychainService, account: AppIdentity.legacyBlobKeyAccount
            ) else { return .nothingToMove }
            try secrets.write(key, service: AppIdentity.keychainService, account: AppIdentity.blobKeyAccount)
            guard try secrets.read(
                service: AppIdentity.keychainService, account: AppIdentity.blobKeyAccount
            ) == key else { return .failed }
            guard storeOutcome == .moved || storeOutcome == .nothingToMove else { return .movedKeepingOld }
            secrets.delete(service: AppIdentity.legacyKeychainService, account: AppIdentity.legacyBlobKeyAccount)
            return .moved
        } catch {
            return .failed
        }
    }
}
