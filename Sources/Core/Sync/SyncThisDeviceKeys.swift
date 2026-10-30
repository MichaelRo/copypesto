// SPDX-License-Identifier: MIT
import Foundation
import Security

/// The sync key as a this-device item: what a self-signed build and every other folder provider use. The key is joined
/// by hand (recovery key or pairing).
public struct ThisDeviceSyncKeyStore: SyncKeyStoring {
    private let secrets: any SecretStoring

    public var mode: SyncKeyMode {
        .thisDevice
    }

    public init(secrets: any SecretStoring = KeychainSecretStore()) {
        self.secrets = secrets
    }

    private func account(_ vaultID: Data, _ epoch: UInt32) -> String {
        "\(AppIdentity.bundleID).syncKey.\(vaultID.hexString).\(epoch)"
    }

    public func syncKey(vaultID: Data, epoch: UInt32) throws -> SyncKey? {
        try secrets.read(service: AppIdentity.keychainService, account: account(vaultID, epoch))
            .map { try SyncKey(data: $0) }
    }

    public func saveSyncKey(_ key: SyncKey, vaultID: Data, epoch: UInt32) throws {
        try secrets.write(key.data, service: AppIdentity.keychainService, account: account(vaultID, epoch))
    }

    public func deleteSyncKeys(vaultID: Data) throws {
        for epoch in UInt32(1)...64 {
            secrets.delete(service: AppIdentity.keychainService, account: account(vaultID, epoch))
        }
    }
}

/// This Mac's signing and pairing keys: this-device items, never synchronized.
public struct KeychainDeviceKeyStore: SyncDeviceKeyStoring {
    private let secrets: any SecretStoring
    private static let account = "\(AppIdentity.bundleID).syncDeviceKeys"

    public init(secrets: any SecretStoring = KeychainSecretStore()) {
        self.secrets = secrets
    }

    public func deviceKeys() throws -> SyncDeviceKeys? {
        try secrets.read(service: AppIdentity.keychainService, account: Self.account)
            .map { try SyncDeviceKeys(rawRepresentation: $0) }
    }

    public func saveDeviceKeys(_ keys: SyncDeviceKeys) throws {
        try secrets.write(keys.rawRepresentation, service: AppIdentity.keychainService, account: Self.account)
    }

    public func deleteDeviceKeys() throws {
        secrets.delete(service: AppIdentity.keychainService, account: Self.account)
    }
}

public enum SyncEntitlement {
    /// True when this build was signed with the application-identifier entitlement a provisioning profile grants, which
    /// is what the iCloud Keychain item needs. A self-signed or profile-less build answers false.
    public static var isPresent: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) != nil
    }

    public static func keyStore(
        hasEntitlement: Bool = isPresent, client: any KeychainItemClient = SystemKeychainClient(),
        secrets: any SecretStoring = KeychainSecretStore()
    )
    -> any SyncKeyStoring {
        hasEntitlement ? ICloudSyncKeyStore(client: client) : ThisDeviceSyncKeyStore(secrets: secrets)
    }
}
