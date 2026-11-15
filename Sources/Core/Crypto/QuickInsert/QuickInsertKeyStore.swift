// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The quick-insert key (ADR 0051): a `SharedFileKeyStore` under `AppIdentity.quickInsertKeyAccount` in the Keychain
/// group the app and its AutoFill extension share. It opens the quick-insert file and nothing else.
public struct QuickInsertKeyStore: Sendable {
    private let store: SharedFileKeyStore

    public init(secrets: any SecretStoring) {
        store = SharedFileKeyStore(secrets: secrets, account: AppIdentity.quickInsertKeyAccount)
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
