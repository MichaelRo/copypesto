// SPDX-License-Identifier: MIT
import Foundation

public enum SyncKeyMode: String, Sendable {
    case iCloudKeychain
    case thisDevice
}

/// Where the sync key lives. The iCloud Keychain version needs the entitlement a provisioning profile grants; the
/// this-device version is what a self-signed build and every other provider use (phase 4).
public protocol SyncKeyStoring: Sendable {
    var mode: SyncKeyMode { get }
    func syncKey(vaultID: Data, epoch: UInt32) throws -> SyncKey?
    func saveSyncKey(_ key: SyncKey, vaultID: Data, epoch: UInt32) throws
    func deleteSyncKeys(vaultID: Data) throws
}

public protocol SyncDeviceKeyStoring: Sendable {
    func deviceKeys() throws -> SyncDeviceKeys?
    func saveDeviceKeys(_ keys: SyncDeviceKeys) throws
    func deleteDeviceKeys() throws
}
