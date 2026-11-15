// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The inbox's private key: a this-device Keychain item of the app alone (`KeychainSecretStore` stores it
/// when-unlocked, this device only, never synchronized). The share extension never reads it.
public struct InboxKeyStore: Sendable {
    private let secrets: any SecretStoring

    public init(secrets: any SecretStoring = KeychainSecretStore()) {
        self.secrets = secrets
    }

    public func privateKey() throws -> Curve25519.KeyAgreement.PrivateKey? {
        try secrets.read(service: AppIdentity.keychainService, account: AppIdentity.inboxKeyAccount)
            .map { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data($0)) }
    }

    /// The stored key, or a new one. A write that met an existing item adopts what is stored, never the key it made.
    public func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let stored = try privateKey() { return stored }
        let created = Curve25519.KeyAgreement.PrivateKey()
        try secrets.write(
            Data(created.rawRepresentation), service: AppIdentity.keychainService, account: AppIdentity.inboxKeyAccount
        )
        guard let stored = try privateKey() else { throw InboxError.noKey }
        return stored
    }
}
