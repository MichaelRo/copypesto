// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A random AES-256 key that the iOS app and one extension both read, kept under its own account in a Keychain group
/// they share (`SharedKeychainSecretStore`). Each key opens one sealed group file and nothing else (ADR 0051, ADR
/// 0052): never the store, the inbox, sync or the other file.
public struct SharedFileKeyStore: Sendable {
    private let secrets: any SecretStoring
    public let account: String

    public init(secrets: any SecretStoring, account: String) {
        self.secrets = secrets
        self.account = account
    }

    public func key() throws -> SymmetricKey? {
        guard let raw = try secrets.read(service: AppIdentity.keychainService, account: account) else { return nil }
        guard raw.count == 32 else { throw SealedFileError.noKey }
        return SymmetricKey(data: raw)
    }

    /// The stored key, or a new one. A write that met an existing item adopts what is stored, never the key it made.
    public func loadOrCreate() throws -> SymmetricKey {
        if let stored = try key() { return stored }
        let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try secrets.write(created, service: AppIdentity.keychainService, account: account)
        guard let stored = try key() else { throw SealedFileError.noKey }
        return stored
    }

    public func remove() {
        secrets.delete(service: AppIdentity.keychainService, account: account)
    }
}
