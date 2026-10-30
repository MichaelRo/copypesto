// SPDX-License-Identifier: MIT
import Foundation
import Security
import Testing
@testable import PestoCore

final class FakeKeychain: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var queries: [[String: Any]] = []
    private var forcedStatus: OSStatus?

    var lastQuery: [String: Any]? {
        lock.withLock { queries.last }
    }

    func fail(with status: OSStatus?) {
        lock.withLock { forcedStatus = status }
    }

    private func key(_ query: [String: Any]) -> String {
        (query[kSecAttrAccount as String] as? String) ?? ""
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            queries.append(attributes)
            if let forcedStatus { return forcedStatus }
            let name = key(attributes)
            if items[name] != nil { return errSecDuplicateItem }
            items[name] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            queries.append(query)
            if let forcedStatus { return (forcedStatus, nil) }
            guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock { items[key(query)] = nil }
        return errSecSuccess
    }
}

@Suite("Sync keys: where the key lives, how a group is made, reset and joined")
struct SyncKeysTests {
    let vaultID = Data((0..<16).map { UInt8($0) })
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func layout() -> SyncFolderLayout {
        SyncFolderLayout(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-group-\(UUID().uuidString)"))
    }

    // MARK: Stores

    @Test("the iCloud Keychain item is synchronizable, in the data protection keychain, readable after first unlock")
    func iCloudItemAttributes() throws {
        let client = FakeKeychain()
        let store = ICloudSyncKeyStore(client: client)
        let key = SyncKey.generate()
        try store.saveSyncKey(key, vaultID: vaultID, epoch: 3)

        let added = try #require(client.lastQuery)
        #expect(added[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(added[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(added[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(added[kSecAttrAccount as String] as? String == "sync-key.\(vaultID.hexString).3")
        #expect(try store.syncKey(vaultID: vaultID, epoch: 3) == key)
        #expect(try store.syncKey(vaultID: vaultID, epoch: 4) == nil)
    }

    @Test("the same key stored twice is fine; a different key is a conflict that is not overwritten")
    func duplicates() throws {
        let store = ICloudSyncKeyStore(client: FakeKeychain())
        let key = SyncKey.generate()
        try store.saveSyncKey(key, vaultID: vaultID, epoch: 1)
        try store.saveSyncKey(key, vaultID: vaultID, epoch: 1)
        #expect(throws: SyncKeyStoreError.conflict) { try store.saveSyncKey(.generate(), vaultID: vaultID, epoch: 1) }
        #expect(try store.syncKey(vaultID: vaultID, epoch: 1) == key)
    }

    @Test("a missing entitlement and a locked Keychain are named, not mistaken for 'no key'")
    func failures() {
        let client = FakeKeychain()
        let store = ICloudSyncKeyStore(client: client)
        client.fail(with: errSecMissingEntitlement)
        #expect(throws: SyncKeyStoreError.entitlementMissing) { try store.syncKey(vaultID: vaultID, epoch: 1) }
        #expect(throws: SyncKeyStoreError.entitlementMissing) { try store.saveSyncKey(
            .generate(),
            vaultID: vaultID,
            epoch: 1
        ) }
        client.fail(with: errSecInteractionNotAllowed)
        #expect(throws: SyncKeyStoreError.locked) { try store.syncKey(vaultID: vaultID, epoch: 1) }
        client.fail(with: -1)
        #expect(throws: SyncKeyStoreError.keychain(-1)) { try store.syncKey(vaultID: vaultID, epoch: 1) }
    }

    @Test("a synchronizable key is never deleted by one Mac leaving; the choice follows the entitlement")
    func leavingAndChoice() throws {
        let client = FakeKeychain()
        let store = ICloudSyncKeyStore(client: client)
        try store.saveSyncKey(.generate(), vaultID: vaultID, epoch: 1)
        try store.deleteSyncKeys(vaultID: vaultID)
        #expect(try store.syncKey(vaultID: vaultID, epoch: 1) != nil)
        #expect(SyncEntitlement.keyStore(hasEntitlement: true, client: client, secrets: MemorySecrets())
            .mode == .iCloudKeychain)
        #expect(SyncEntitlement.keyStore(hasEntitlement: false, client: client, secrets: MemorySecrets())
            .mode == .thisDevice)
    }

    @Test("the this-device store and the device keys round-trip, and leaving removes the this-device key")
    func thisDevice() throws {
        let secrets = MemorySecrets()
        let store = ThisDeviceSyncKeyStore(secrets: secrets)
        let key = SyncKey.generate()
        try store.saveSyncKey(key, vaultID: vaultID, epoch: 2)
        #expect(try store.syncKey(vaultID: vaultID, epoch: 2) == key)
        try store.deleteSyncKeys(vaultID: vaultID)
        #expect(try store.syncKey(vaultID: vaultID, epoch: 2) == nil)

        let devices = KeychainDeviceKeyStore(secrets: secrets)
        #expect(try devices.deviceKeys() == nil)
        let keys = SyncDeviceKeys.generate()
        try devices.saveDeviceKeys(keys)
        #expect(try devices.deviceKeys()?.publicKeys == keys.publicKeys)
        try devices.deleteDeviceKeys()
        #expect(try devices.deviceKeys() == nil)
    }

    // MARK: Groups

    @Test("a new group writes a vault and a device record, stores the key and opens again on the same Mac")
    func createAndOpen() throws {
        let layout = layout(), store = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let device = SyncDeviceKeys.generate()
        let made = try SyncGroupManager.create(
            layout: layout, identity: .init(deviceID: "mac-a", name: "Michael's MacBook", keys: device),
            keyStore: store,
            now: now
        )
        #expect(FileManager.default.fileExists(atPath: layout.vault(epoch: 1).path))
        #expect(FileManager.default.fileExists(atPath: layout.deviceRecord("mac-a").path))
        #expect(try SyncKey(recoveryKey: made.recoveryKey) == made.group.key)

        guard case let .ready(group) = try SyncGroupManager.open(layout: layout, keyStore: store) else {
            Issue.record("the group did not open")
            return
        }
        #expect(group.vault == made.group.vault && group.key == made.group.key)
        #expect(group.devices.map(\.deviceID) == ["mac-a"] && group.trust.signers.count == 1)
    }

    @Test("an empty folder is empty, and a Mac without the key is told it needs one")
    func emptyAndNeedsKey() throws {
        let layout = layout()
        guard case .empty = try SyncGroupManager.open(
            layout: layout,
            keyStore: ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        ) else {
            Issue.record("expected an empty folder")
            return
        }
        _ = try SyncGroupManager.create(
            layout: layout, identity: .init(deviceID: "mac-a", name: "A", keys: .generate()),
            keyStore: ThisDeviceSyncKeyStore(secrets: MemorySecrets()), now: now
        )
        guard case .needsKey = try SyncGroupManager.open(
            layout: layout, keyStore: ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        ) else {
            Issue.record("expected needsKey")
            return
        }
    }

    @Test("a second Mac that types the recovery key joins, announces itself, and the first Mac then trusts it")
    func joinByRecoveryKey() throws {
        let layout = layout()
        let storeA = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let made = try SyncGroupManager.create(
            layout: layout, identity: .init(deviceID: "mac-a", name: "A", keys: .generate()), keyStore: storeA, now: now
        )
        let storeB = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let deviceB = SyncDeviceKeys.generate()
        guard case let .needsKey(vault) = try SyncGroupManager.open(layout: layout, keyStore: storeB) else {
            Issue.record("expected needsKey")
            return
        }
        let typed = try SyncKey(recoveryKey: made.recoveryKey)
        #expect(vault.accepts(typed) && !vault.accepts(.generate()))
        try storeB.saveSyncKey(typed, vaultID: vault.vaultID, epoch: vault.epoch)
        try SyncGroupManager.writeDeviceRecord(
            layout: layout, vault: vault, key: typed, identity: .init(deviceID: "mac-b", name: "B", keys: deviceB),
            now: now
        )

        guard case let .ready(seenByA) = try SyncGroupManager.open(layout: layout, keyStore: storeA) else {
            Issue.record("A could not open")
            return
        }
        #expect(Set(seenByA.devices.map(\.deviceID)) == ["mac-a", "mac-b"])
        #expect(seenByA.trust.signers[deviceB.publicKeys.keyID] != nil)
    }

    @Test("Reset Sync starts a new epoch with a new key; the others find it, and the old key does not open it")
    func reset() throws {
        let layout = layout()
        let store = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let device = SyncDeviceKeys.generate()
        let first = try SyncGroupManager.create(
            layout: layout, identity: .init(deviceID: "mac-a", name: "A", keys: device), keyStore: store, now: now
        )
        let second = try SyncGroupManager.reset(
            layout: layout, from: first.group, identity: .init(deviceID: "mac-a", name: "A", keys: device),
            keyStore: store,
            now: now
        )
        #expect(second.group.epoch == 2 && second.group.key != first.group.key)
        #expect(second.group.vault.vaultID == first.group.vault.vaultID)
        #expect(!second.group.vault.accepts(first.group.key))
        guard case let .ready(group) = try SyncGroupManager.open(layout: layout, keyStore: store) else {
            Issue.record("the new epoch did not open")
            return
        }
        #expect(group.epoch == 2)

        // A Mac that only has the old key is told it needs the new one.
        let stale = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        try stale.saveSyncKey(first.group.key, vaultID: first.group.vault.vaultID, epoch: 1)
        guard case let .needsKey(vault) = try SyncGroupManager.open(layout: layout, keyStore: stale) else {
            Issue.record("expected needsKey")
            return
        }
        #expect(vault.epoch == 2)
    }

    @Test("two resets that raced to the same epoch resolve to the same vault on every Mac")
    func racingResets() throws {
        let layout = layout()
        let storeA = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let storeB = ThisDeviceSyncKeyStore(secrets: MemorySecrets())
        let deviceA = SyncDeviceKeys.generate(), deviceB = SyncDeviceKeys.generate()
        let made = try SyncGroupManager.create(
            layout: layout, identity: .init(deviceID: "mac-a", name: "A", keys: deviceA), keyStore: storeA, now: now
        )
        try storeB.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try SyncGroupManager.writeDeviceRecord(
            layout: layout, vault: made.group.vault, key: made.group.key, identity: .init(
                deviceID: "mac-b",
                name: "B",
                keys: deviceB
            )
        )
        // Both reset at once, each into its own epoch-2 vault file under its own new key. Only one file can be named
        // vault-2, so the second writer's rename replaces the first; either way every Mac reads the same one.
        let fromA = try SyncGroupManager.reset(
            layout: layout, from: made.group, identity: .init(deviceID: "mac-a", name: "A", keys: deviceA),
            keyStore: storeA
        )
        let fromB = try SyncGroupManager.reset(
            layout: layout, from: made.group, identity: .init(deviceID: "mac-b", name: "B", keys: deviceB),
            keyStore: storeB
        )
        let seenByA = try SyncGroupManager.open(layout: layout, keyStore: storeA)
        let seenByB = try SyncGroupManager.open(layout: layout, keyStore: storeB)
        func epochOne(_ state: SyncGroupOpening) -> Bool {
            if case .needsKey = state { return true }
            if case let .ready(group) = state { return group.epoch == 2 }
            return false
        }
        #expect(epochOne(seenByA) && epochOne(seenByB))
        #expect(fromA.group.epoch == 2 && fromB.group.epoch == 2)
    }

    // MARK: Pairing

    @Test("a join request is signed by the joining Mac and a changed byte is refused")
    func joinRequest() throws {
        let device = SyncDeviceKeys.generate()
        let request = try SyncJoinRequest(
            deviceID: "mac-b", name: "B", keys: device.publicKeys, vaultID: vaultID, createdAt: now
        ).signed(by: device)
        let data = try request.serialized()
        #expect(try SyncJoinRequest.parse(data) == request)
        var forged = request
        forged.name = "Not B"
        #expect(throws: SyncError.badSignature) { try SyncJoinRequest.parse(forged.serialized()) }
    }

    @Test(
        "an approved join: both Macs show the same six words, the grant opens only for the joining Mac, once confirmed"
    )
    func grantRoundTrip() throws {
        let approver = SyncDeviceKeys.generate(), joiner = SyncDeviceKeys.generate(),
            stranger = SyncDeviceKeys.generate()
        let key = SyncKey.generate()
        let request = try SyncJoinRequest(
            deviceID: "mac-b", name: "B", keys: joiner.publicKeys, vaultID: vaultID, createdAt: now
        ).signed(by: joiner)
        let grant = try SyncGrant.seal(key: key, vaultID: vaultID, epoch: 2, to: request, approver: approver)
        let parsed = try SyncGrant.parse(grant.serialized())

        #expect(request.pairingWords(approver: approver.publicKeys) == parsed.pairingWords(for: request))
        let opened = try parsed.open(
            device: joiner, deviceID: "mac-b", vaultID: vaultID, expectedApprover: approver.publicKeys
        )
        #expect(opened.key == key && opened.epoch == 2)

        #expect(throws: SyncError.self) {
            try parsed.open(
                device: stranger,
                deviceID: "mac-b",
                vaultID: vaultID,
                expectedApprover: approver.publicKeys
            )
        }
        #expect(throws: SyncError.deviceUnknown) {
            try parsed.open(device: joiner, deviceID: "mac-c", vaultID: vaultID, expectedApprover: approver.publicKeys)
        }
        #expect(throws: SyncError.wrongVault) {
            try parsed.open(
                device: joiner, deviceID: "mac-b", vaultID: Data(repeating: 9, count: 16),
                expectedApprover: approver.publicKeys
            )
        }
        // A provider that put its own key in the grant changes the words, so the person sees a mismatch, and the
        // grant does not open for an approver the words did not name.
        let impostor = SyncDeviceKeys.generate()
        #expect(request.pairingWords(approver: impostor.publicKeys) != parsed.pairingWords(for: request))
        #expect(throws: SyncError.badSignature) {
            try parsed.open(device: joiner, deviceID: "mac-b", vaultID: vaultID, expectedApprover: impostor.publicKeys)
        }
    }

    @Test("a changed byte in a grant does not open")
    func tamperedGrant() throws {
        let approver = SyncDeviceKeys.generate(), joiner = SyncDeviceKeys.generate()
        let request = try SyncJoinRequest(
            deviceID: "mac-b", name: "B", keys: joiner.publicKeys, vaultID: vaultID, createdAt: now
        ).signed(by: joiner)
        var grant = try SyncGrant.seal(key: .generate(), vaultID: vaultID, epoch: 1, to: request, approver: approver)
        grant.sealedKey[0] ^= 1
        #expect(throws: SyncError.self) {
            try grant.open(device: joiner, deviceID: "mac-b", vaultID: vaultID, expectedApprover: approver.publicKeys)
        }
    }

    @Test("a changed byte in a device record does not open, and neither does the wrong epoch")
    func tamperedDeviceRecord() throws {
        let joiner = SyncDeviceKeys.generate()
        let key = SyncKey.generate()
        let record = SyncDeviceRecord(deviceID: "mac-b", name: "B", keys: joiner.publicKeys, epoch: 1, createdAt: now)
        let sealed = try record.sealed(syncKey: key, vaultID: vaultID, signedBy: joiner)
        let opened = try SyncDeviceRecord.open(sealed, syncKey: key, vaultID: vaultID, epoch: 1, deviceID: "mac-b")
        #expect(opened.deviceID == "mac-b" && opened.keys == joiner.publicKeys && opened.name == "B")
        for index in sealed.indices {
            var damaged = sealed
            damaged[index] ^= 1
            #expect(
                (try? SyncDeviceRecord.open(damaged, syncKey: key, vaultID: vaultID, epoch: 1, deviceID: "mac-b")) ==
                    nil
            )
        }
        #expect(throws: SyncError.wrongKey) {
            try SyncDeviceRecord.open(sealed, syncKey: key, vaultID: vaultID, epoch: 2, deviceID: "mac-b")
        }
    }
}
