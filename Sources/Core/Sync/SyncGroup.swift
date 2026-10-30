// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A sync group as one Mac sees it once it holds the key: the current vault, the key, and the devices whose records
/// open under that key (the signatures this Mac trusts).
public struct SyncGroup: Sendable {
    public let vault: SyncVault
    public let key: SyncKey
    public let devices: [SyncDeviceRecord]

    public var trust: SyncTrust {
        SyncTrust(devices.map(\.keys))
    }

    public var epoch: UInt32 {
        vault.epoch
    }
}

public enum SyncGroupOpening: Sendable {
    /// No sync group in the folder.
    case empty
    /// A group is there, but this Mac does not have its key (iCloud Keychain off, or a new Mac in the interim mode).
    case needsKey(SyncVault)
    case ready(SyncGroup)
}

/// Who this Mac is in the group: its id, a name people recognize, and its keys.
public struct SyncIdentity: Sendable {
    public var deviceID: String
    public var name: String
    public var keys: SyncDeviceKeys

    public init(deviceID: String, name: String, keys: SyncDeviceKeys) {
        self.deviceID = deviceID
        self.name = name
        self.keys = keys
    }
}

public enum SyncGroupManager {
    /// Makes a new sync group in an empty folder: the vault, a new key (kept in `keyStore`), this Mac's device record.
    /// Returns the recovery key, which is the sync key itself.
    public static func create(
        layout: SyncFolderLayout, identity: SyncIdentity, keyStore: SyncKeyStoring, now: Date = .now
    ) throws
    -> (group: SyncGroup, recoveryKey: String) {
        try startEpoch(
            layout: layout, start: (1, nil), identity: identity, keyStore: keyStore, now: now
        )
    }

    /// Starts a new epoch with a new key (Reset Sync). The others find the new vault file and switch.
    public static func reset(
        layout: SyncFolderLayout, from group: SyncGroup, identity: SyncIdentity, keyStore: SyncKeyStoring,
        now: Date = .now
    ) throws
    -> (group: SyncGroup, recoveryKey: String) {
        try startEpoch(
            layout: layout, start: (group.epoch + 1, group.vault.vaultID), identity: identity, keyStore: keyStore,
            now: now
        )
    }

    private static func startEpoch(
        layout: SyncFolderLayout, start: (epoch: UInt32, vaultID: Data?), identity: SyncIdentity,
        keyStore: SyncKeyStoring,
        now: Date
    ) throws
    -> (group: SyncGroup, recoveryKey: String) {
        let key = SyncKey.generate()
        let (epoch, vaultID) = start
        let device = identity.keys
        let vault = vaultID.map { SyncVault.create(vaultID: $0, epoch: epoch, syncKey: key, creator: device) }
            ?? SyncVault.create(epoch: epoch, syncKey: key, creator: device)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try keyStore.saveSyncKey(key, vaultID: vault.vaultID, epoch: epoch)
        let record = try writeDeviceRecord(
            layout: layout, vault: vault, key: key, identity: identity, now: now
        )
        try vault.serialized(signedBy: device).write(to: layout.vault(epoch: epoch), options: .atomic)
        return (SyncGroup(vault: vault, key: key, devices: [record]), key.recoveryKey)
    }

    /// Writes this Mac's device record under the group's key, which is how a Mac that has the key joins (and how every
    /// Mac re-announces itself in a new epoch).
    @discardableResult
    public static func writeDeviceRecord(
        layout: SyncFolderLayout, vault: SyncVault, key: SyncKey, identity: SyncIdentity, now: Date = .now
    ) throws
    -> SyncDeviceRecord {
        let record = SyncDeviceRecord(
            deviceID: identity.deviceID, name: identity.name, keys: identity.keys.publicKeys, epoch: vault.epoch,
            createdAt: now
        )
        try FileManager.default.createDirectory(at: layout.device(identity.deviceID), withIntermediateDirectories: true)
        try record.sealed(syncKey: key, vaultID: vault.vaultID, signedBy: identity.keys)
            .write(to: layout.deviceRecord(identity.deviceID), options: .atomic)
        return record
    }

    /// Finds the group a folder holds: the newest epoch whose vault file is validly signed by a device of that epoch,
    /// and the key for it if this Mac has one. Two vaults of the same epoch (two resets that raced) resolve to the one
    /// with the smaller file hash, the same on every Mac.
    public static func open(layout: SyncFolderLayout, keyStore: SyncKeyStoring) throws -> SyncGroupOpening {
        var candidates: [(vault: SyncVault, hash: String)] = []
        for url in layout.vaultFiles() {
            guard let data = try? Data(contentsOf: url), let vault = try? SyncVault.parse(data) else { continue }
            candidates.append((vault, Data(SHA256.hash(data: data)).hexString))
        }
        guard let vaultID = candidates.map(\.vault.vaultID).min(by: { $0.lexicographicallyPrecedes($1) }) else {
            return .empty
        }
        let ordered = candidates.filter { $0.vault.vaultID == vaultID }
            .sorted { ($0.vault.epoch, $1.hash) > ($1.vault.epoch, $0.hash) }
        guard let newest = ordered.first?.vault else { return .empty }
        for candidate in ordered.map(\.vault) {
            guard let key = try keyStore.syncKey(vaultID: vaultID, epoch: candidate.epoch),
                  candidate.accepts(key) else
            {
                if candidate.epoch == newest.epoch { return .needsKey(newest) }
                continue
            }
            let devices = devices(layout: layout, vault: candidate, key: key)
            guard devices.contains(where: { $0.keys == candidate.creator }) else { continue }
            return .ready(SyncGroup(vault: candidate, key: key, devices: devices))
        }
        return .needsKey(newest)
    }

    /// The group as it stands now, or nil when the folder holds none this Mac can open.
    public static func openGroup(layout: SyncFolderLayout, keyStore: SyncKeyStoring) throws -> SyncGroup? {
        if case let .ready(group) = try open(layout: layout, keyStore: keyStore) { return group }
        return nil
    }

    static func devices(layout: SyncFolderLayout, vault: SyncVault, key: SyncKey) -> [SyncDeviceRecord] {
        layout.deviceIDs().compactMap { id in
            guard let data = try? Data(contentsOf: layout.deviceRecord(id)) else { return nil }
            return try? SyncDeviceRecord.open(
                data,
                syncKey: key,
                vaultID: vault.vaultID,
                epoch: vault.epoch,
                deviceID: id
            )
        }
    }
}
