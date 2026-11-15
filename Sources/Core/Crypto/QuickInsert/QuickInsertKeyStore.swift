// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The quick-insert key (ADR 0051): a random AES-256 key the app and its AutoFill extension both read, kept in the
/// Keychain group they share (`SharedKeychainSecretStore`). It opens the quick-insert file and nothing else: never
/// the store, the inbox or sync.
public struct QuickInsertKeyStore: Sendable {
    private let secrets: any SecretStoring

    public init(secrets: any SecretStoring) {
        self.secrets = secrets
    }

    public func key() throws -> SymmetricKey? {
        guard let raw = try secrets.read(
            service: AppIdentity.keychainService,
            account: AppIdentity.quickInsertKeyAccount
        ) else { return nil }
        guard raw.count == 32 else { throw QuickInsertError.noKey }
        return SymmetricKey(data: raw)
    }

    /// The stored key, or a new one. A write that met an existing item adopts what is stored, never the key it made.
    public func loadOrCreate() throws -> SymmetricKey {
        if let stored = try key() { return stored }
        let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try secrets.write(created, service: AppIdentity.keychainService, account: AppIdentity.quickInsertKeyAccount)
        guard let stored = try key() else { throw QuickInsertError.noKey }
        return stored
    }

    public func remove() {
        secrets.delete(service: AppIdentity.keychainService, account: AppIdentity.quickInsertKeyAccount)
    }
}
