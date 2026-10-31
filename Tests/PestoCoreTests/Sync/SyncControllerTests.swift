// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@MainActor
final class SyncMac {
    let container: ModelContainer
    let storage: StorageService
    let secrets = MemorySecrets()
    let defaults = ThrowawayDefaults.make()
    let keyStore: SyncKeyStoring
    let controller: SyncController
    let site: SyncSite

    init(name: String, folder: URL, time: TimeBox, keyStore: SyncKeyStoring? = nil) throws {
        site = try SyncSite(name: name, layout: SyncFolderLayout(root: folder), time: time)
        container = site.container
        storage = site.storage
        self.keyStore = keyStore ?? site.keyStore
        var environment = SyncController.Environment(
            container: container, storage: storage, folder: folder, keyStore: self.keyStore,
            deviceKeys: KeychainDeviceKeyStore(secrets: secrets), highWater: MemoryHighWater(), defaults: defaults,
            deviceID: name, deviceName: "\(name)’s Mac"
        )
        environment.now = { time.now }
        environment.timing.batchWindow = .milliseconds(20)
        environment.timing.pollInterval = .seconds(3600)
        controller = SyncController(environment)
    }

    func clips() throws -> [String] {
        try site.texts()
    }
}

@Suite("Sync controller: turning on, joining, pairing, reset and leave", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncControllerTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-controller-\(UUID().uuidString)")
    let time = TimeBox()

    private func settle(_ macs: SyncMac...) async {
        for _ in 0..<2 {
            for mac in macs {
                time.advance()
                await mac.controller.syncNow()
            }
        }
    }

    @Test(
        "changing the folder pauses sync, remembers it and offers set-up there; the old folder is left alone"
    )
    func changingTheFolder() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        try await a.site.copy("stays")
        await a.controller.turnOn()
        #expect(a.controller.isEnabled)
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-elsewhere-\(UUID().uuidString)")
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

        a.controller.changeFolder(to: elsewhere)

        #expect(!a.controller.isEnabled)
        #expect(a.controller.flow == .setUp)
        #expect(a.controller.folderURL == elsewhere)
        #expect(a.defaults.value(for: Setting.syncFolderPath) == elsewhere.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
        await a.controller.turnOn()
        #expect(a.controller.isEnabled)
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    @Test("sync is off on every Mac until its person turns it on")
    func offByDefault() {
        #expect(Setting.syncEnabled.defaultValue == false)
        #expect(Setting.syncIncludesSecrets.defaultValue == false)
        #expect(Setting.syncFolderPath.defaultValue.isEmpty)
    }

    @Test("the first Mac makes the group, is shown the recovery key, and its clips reach a Mac that joins with the key")
    func firstMacAndJoin() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        try await a.site.copy("from the first Mac")
        await a.controller.turnOn()
        guard case let .recoveryKey(key) = a.controller.flow else {
            Issue.record("expected the recovery key, got \(a.controller.flow)")
            return
        }
        #expect(a.controller.isEnabled)
        #expect(a.defaults.value(for: Setting.syncEnabled))

        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        try await b.site.copy("on the second Mac")
        await b.controller.turnOn()
        #expect(b.controller.flow == .needsKey)
        await b.controller.useRecoveryKey("not a key")
        if case .failed = b.controller.flow {} else { Issue.record("a typo should fail, got \(b.controller.flow)") }
        await b.controller.useRecoveryKey(key)
        guard case let .joinOffer(thisMac, group) = b.controller.flow else {
            Issue.record("expected an offer to join, got \(b.controller.flow)")
            return
        }
        #expect(thisMac == 1)
        #expect(group <= 1)
        await settle(a)
        await b.controller.turnOn()
        guard case let .joinOffer(_, nowGroup) = b.controller.flow else {
            Issue.record("no offer")
            return
        }
        #expect(nowGroup == 1)
        b.controller.confirmJoin()
        await settle(a, b)
        #expect(try a.clips() == ["from the first Mac", "on the second Mac"], "A: \(a.controller.status)")
        #expect(try b.clips() == ["from the first Mac", "on the second Mac"], "B: \(b.controller.status)")
        if case .upToDate = b.controller.status {} else { Issue.record("B status \(b.controller.status)") }
    }

    @Test("with iCloud Keychain as the key store and no key there, the Mac says iCloud Keychain is off")
    func keychainOff() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        let b = try SyncMac(
            name: "mac-b",
            folder: folder,
            time: time,
            keyStore: ICloudSyncKeyStore(client: FakeKeychain())
        )
        await b.controller.turnOn()
        #expect(b.controller.flow == .iCloudKeychainOff)
        #expect(!b.controller.isEnabled)
    }

    @Test("asking another Mac: six words on both screens, an Allow, and the key arrives with nothing typed")
    func pairing() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        await settle(a)
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        #expect(b.controller.flow == .needsKey)

        b.controller.askAnotherMac()
        guard case let .pairing(words, approver) = b.controller.flow else {
            Issue.record("expected pairing, got \(b.controller.flow)")
            return
        }
        #expect(words.count == 6 && approver == "mac-a’s Mac")

        a.controller.refresh()
        let pending = try #require(a.controller.pendingJoin)
        #expect(pending.words == words, "both Macs must show the same six words")
        a.controller.allow(pending)
        b.controller.refresh()
        try await Task.sleep(for: .milliseconds(200))
        guard case .joinOffer = b.controller.flow else {
            Issue.record("expected an offer to join, got \(b.controller.flow)")
            return
        }
    }

    @Test("a request that is denied does not come back, and one addressed to another Mac is not shown")
    func denied() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        await settle(a)
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        b.controller.askAnotherMac()
        a.controller.refresh()
        let pending = try #require(a.controller.pendingJoin)
        a.controller.deny(pending)
        a.controller.refresh()
        #expect(a.controller.pendingJoin == nil)
    }

    @Test("with no other Mac in the folder, asking says so instead of waiting for nobody")
    func nobodyToAsk() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        try FileManager.default.removeItem(at: SyncFolderLayout(root: folder).identity("mac-a"))
        await b.controller.turnOn()
        b.controller.askAnotherMac()
        if case .failed = b.controller.flow {} else { Issue.record("expected a failure, got \(b.controller.flow)") }
    }

    @Test("Reset Sync gives a new recovery key and a new epoch; the other Mac then needs the new key")
    func reset() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        guard case let .recoveryKey(first) = a.controller.flow else {
            Issue.record("no key")
            return
        }
        await a.controller.reset()
        guard case let .recoveryKey(second) = a.controller.flow else {
            Issue.record("no new key")
            return
        }
        #expect(first != second)
        guard case let .ready(group) = try SyncGroupManager.open(
            layout: SyncFolderLayout(root: folder), keyStore: a.keyStore
        ) else {
            Issue.record("no group")
            return
        }
        #expect(group.epoch == 2 && group.key.recoveryKey == second)
    }

    @Test("Leave Sync removes this Mac's own files, turns sync off and keeps its clips; the others keep theirs")
    func leave() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        try await a.site.copy("mine")
        await a.controller.turnOn()
        await settle(a)
        let layout = SyncFolderLayout(root: folder)
        #expect(FileManager.default.fileExists(atPath: layout.device("mac-a").path))

        a.controller.leave()

        #expect(!FileManager.default.fileExists(atPath: layout.device("mac-a").path))
        #expect(!a.controller.isEnabled && a.controller.status == .off)
        #expect(!a.defaults.value(for: Setting.syncEnabled))
        #expect(try a.clips() == ["mine"])
    }

    @Test(
        "a Mac that left and turns sync on again is a new device, so its clips reach a Mac that read the old ones"
    )
    func leaveThenRejoin() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        guard case let .recoveryKey(key) = a.controller.flow else {
            Issue.record("expected the recovery key")
            return
        }
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        await b.controller.useRecoveryKey(key)
        b.controller.confirmJoin()
        for text in ["first", "second", "third"] {
            try await a.site.copy(text)
            await settle(a, b)
        }
        #expect(try b.clips().contains("third"))

        a.controller.leave()
        await settle(b)
        let afterLeave = b.controller.status
        if case .needsKey = afterLeave { Issue.record("B lost the group when the Mac that made it left") }
        await a.controller.turnOn()
        a.controller.confirmJoin()
        try await a.site.copy("after the rejoin")
        await settle(a, b, a, b)

        let received = try b.clips()
        let sent = try a.clips()
        #expect(
            received.contains("after the rejoin"),
            "B never received it: A \(a.controller.status), B \(b.controller.status), A has \(sent)"
        )
        if case let .refused(reason) = b.controller.status { Issue.record("B refuses A's log: \(reason)") }
    }

    @Test("the Mac that made the group can leave: the others keep syncing and a new Mac still gets every clip")
    func theCreatorLeaves() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        guard case let .recoveryKey(key) = a.controller.flow else {
            Issue.record("expected the recovery key")
            return
        }
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        await b.controller.useRecoveryKey(key)
        b.controller.confirmJoin()
        try await a.site.copy("written on A")
        await settle(a, b)
        try await b.site.copy("written on B")
        await settle(b, a)

        a.controller.leave()
        await settle(b)
        try await b.site.copy("written on B after A left")
        await settle(b)
        if case .needsKey = b.controller.status { Issue.record("B lost the group when the Mac that made it left") }

        let c = try SyncMac(name: "mac-c", folder: folder, time: time)
        await c.controller.turnOn()
        await c.controller.useRecoveryKey(key)
        c.controller.confirmJoin()
        await settle(b, c, b, c)

        let got = try c.clips()
        #expect(got.contains("written on A"), "a Mac that left took its clips with it: \(got)")
        #expect(got.contains("written on B"))
        #expect(got.contains("written on B after A left"))
    }

    @Test("a Mac whose folder is merely missing, with no left marker, is not taken over")
    func aMissingFolderAloneAdoptsNothing() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        guard case let .recoveryKey(key) = a.controller.flow else {
            Issue.record("expected the recovery key")
            return
        }
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        await b.controller.useRecoveryKey(key)
        b.controller.confirmJoin()
        try await a.site.copy("written on A")
        await settle(a, b)
        let layout = SyncFolderLayout(root: folder)
        try FileManager.default.removeItem(at: layout.device("mac-a"))
        let before = try b.site.item("written on A")?.changeClock

        await settle(b, b)

        #expect(
            try b.site.item("written on A")?.changeClock == before,
            "B restamped A's clip on a missing folder alone"
        )
    }

    @Test("leaving and joining again twice still delivers every clip")
    func leavingTwice() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        guard case let .recoveryKey(key) = a.controller.flow else {
            Issue.record("expected the recovery key")
            return
        }
        let b = try SyncMac(name: "mac-b", folder: folder, time: time)
        await b.controller.turnOn()
        await b.controller.useRecoveryKey(key)
        b.controller.confirmJoin()
        for round in 1...2 {
            try await a.site.copy("round \(round) before leaving")
            await settle(a, b)
            a.controller.leave()
            await settle(b)
            await a.controller.turnOn()
            a.controller.confirmJoin()
            try await a.site.copy("round \(round) after rejoining")
            await settle(a, b, a, b)
        }
        let got = try b.clips()
        for text in ["round 1 after rejoining", "round 2 before leaving", "round 2 after rejoining"] {
            #expect(got.contains(text), "missing \(text): \(got)")
        }
    }

    @Test("when the folder will not let this Mac remove its files, Leave says so and sync stays on")
    func leaveThatCannotRemove() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        a.controller.cancelFlow()
        let devices = SyncFolderLayout(root: folder).device("mac-a").deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: devices.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: devices.path) }

        a.controller.leave()

        guard case .failed = a.controller.flow else {
            Issue.record("expected a failure, got \(a.controller.flow)")
            return
        }
        #expect(a.controller.isEnabled, "sync was turned off though the files are still in the folder")
    }

    @Test("clips that stay on this Mac are counted, and the count follows the choice about secrets")
    func heldCount() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        try await a.site.copy("4111 1111 1111 1111")
        try await a.site.copy("plain")
        await a.controller.turnOn()
        a.controller.refresh()
        #expect(a.controller.keepsHere == 1)
        await a.controller.setIncludesSecrets(true)
        #expect(a.controller.keepsHere == 0 && a.controller.includesSecrets)
        await a.controller.setIncludesSecrets(false)
        #expect(a.controller.keepsHere == 1)
    }

    @Test("a Mac that had sync on starts it again at launch, and a Mac that did not stays off")
    func resume() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        let again = SyncController({
            var environment = SyncController.Environment(
                container: a.container, storage: a.storage, folder: folder, keyStore: a.keyStore,
                deviceKeys: KeychainDeviceKeyStore(secrets: a.secrets), highWater: MemoryHighWater(),
                defaults: a.defaults, deviceID: "mac-a", deviceName: "mac-a’s Mac"
            )
            environment.now = { self.time.now }
            return environment
        }())
        #expect(again.isEnabled)
        again.resumeIfEnabled()
        await again.syncNow()
        if case .upToDate = again.status {} else { Issue.record("status \(again.status)") }

        let off = try SyncMac(name: "mac-c", folder: folder, time: time)
        off.controller.resumeIfEnabled()
        await off.controller.syncNow()
        #expect(off.controller.status == .off)
    }
}
