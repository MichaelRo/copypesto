// SPDX-License-Identifier: MIT
import Foundation
import Security

public enum SyncKeyStoreError: Error, Equatable {
    /// This build carries no keychain entitlement (a self-signed build, or a release made without the profile).
    case entitlementMissing
    /// The Keychain is locked; try again after the Mac is unlocked.
    case locked
    /// A different key is already stored for this vault and epoch.
    case conflict
    case keychain(Int32)
}

/// The sync key in iCloud Keychain (ADR 0018): a generic password marked synchronizable, in the data protection
/// keychain, readable after first unlock. A second Mac on the same Apple Account finds it with nothing to type. It
/// needs the application-identifier entitlement, which a Developer ID provisioning profile grants.
public struct ICloudSyncKeyStore: SyncKeyStoring {
    private let client: any KeychainItemClient

    public var mode: SyncKeyMode {
        .iCloudKeychain
    }

    public init(client: any KeychainItemClient = SystemKeychainClient()) {
        self.client = client
    }

    static func account(vaultID: Data, epoch: UInt32) -> String {
        "sync-key.\(vaultID.hexString).\(epoch)"
    }

    func baseQuery(vaultID: Data, epoch: UInt32) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.keychainService,
            kSecAttrAccount as String: Self.account(vaultID: vaultID, epoch: epoch),
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private func failure(_ status: OSStatus) -> SyncKeyStoreError {
        switch status {
        case errSecMissingEntitlement: .entitlementMissing
        case errSecInteractionNotAllowed: .locked
        default: .keychain(status)
        }
    }

    public func syncKey(vaultID: Data, epoch: UInt32) throws -> SyncKey? {
        var query = baseQuery(vaultID: vaultID, epoch: epoch)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = client.copy(query)
        switch result.status {
        case errSecSuccess: return try result.data.map { try SyncKey(data: $0) }
        case errSecItemNotFound: return nil
        default: throw failure(result.status)
        }
    }

    public func saveSyncKey(_ key: SyncKey, vaultID: Data, epoch: UInt32) throws {
        var attributes = baseQuery(vaultID: vaultID, epoch: epoch)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = key.data
        let status = client.add(attributes)
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem:
            // Another Mac of this Apple Account already stored it. The same key is fine; a different one is not ours to
            // overwrite, because a change reaches every Mac.
            guard try syncKey(vaultID: vaultID, epoch: epoch) == key else { throw SyncKeyStoreError.conflict }
        default: throw failure(status)
        }
    }

    public func deleteSyncKeys(vaultID _: Data) throws {
        // Leaving the group on one Mac must not delete the key for the others, so a synchronizable item is never
        // deleted here; Reset Sync starts a new epoch instead.
    }
}
