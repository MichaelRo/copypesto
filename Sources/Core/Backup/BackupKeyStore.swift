// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Keeps the random backup key in the login Keychain of this Mac, so every backup it writes can be opened with the same
/// recovery key. The passphrase is never stored: it is asked for each time, and it wraps the key inside the file.
public struct BackupKeyStore: Sendable {
    private let secrets: any SecretStoring
    private let service = AppIdentity.keychainService
    private let account = "\(AppIdentity.bundleID).backupKey"

    public init(secrets: any SecretStoring = KeychainSecretStore()) {
        self.secrets = secrets
    }

    public func existingKey() throws -> BackupKey? {
        guard let data = try secrets.read(service: service, account: account), data.count == BackupKey.byteCount else {
            return nil
        }
        return BackupKey(symmetricKey: SymmetricKeyData.key(from: data))
    }

    /// The stored key, or a new one that is stored first. `isNew` is true only the first time, which is when the
    /// recovery key has to be shown to the person.
    public func keyCreatingIfNeeded() throws -> (key: BackupKey, isNew: Bool) {
        if let existing = try existingKey() { return (existing, false) }
        let key = BackupKey.generate()
        try secrets.write(key.bytes, service: service, account: account)
        // The write tolerates an existing item. Whatever is stored is the key; showing the new one as the recovery key
        // would hand the person a key that opens nothing.
        guard let stored = try existingKey() else { throw KeychainSecretStore.Failure(status: errSecDuplicateItem) }
        return (stored, stored.bytes == key.bytes)
    }

    public func forget() {
        secrets.delete(service: service, account: account)
    }
}
