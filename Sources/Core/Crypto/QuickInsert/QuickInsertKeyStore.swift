// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The quick-insert key (ADR 0051): a `SharedFileKeyStore` under `AppIdentity.quickInsertKeyAccount` in the Keychain
/// group the app, its AutoFill extension and its keyboard share (ADR 0061). It opens the quick-insert file and nothing
/// else.
public struct QuickInsertKeyStore: Sendable {
    private let store: SharedFileKeyStore

    public init(secrets: any SecretStoring) {
        store = SharedFileKeyStore(secrets: secrets, account: AppIdentity.quickInsertKeyAccount)
    }

    /// The store in the shared Keychain group, as the extensions that read the set open it.
    public static func shared(in bundle: Bundle = .main) -> QuickInsertKeyStore {
        QuickInsertKeyStore(
            secrets: SharedKeychainSecretStore(accessGroup: AppIdentity.quickInsertKeychainGroup(in: bundle))
        )
    }

    public func key() throws -> SymmetricKey? {
        try store.key()
    }

    public func loadOrCreate() throws -> SymmetricKey {
        try store.loadOrCreate()
    }

    public func remove() {
        store.remove()
    }
}
