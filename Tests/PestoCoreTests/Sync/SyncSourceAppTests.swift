// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

private struct NamedSourceApps: SourceAppResolving {
    func resolve(bundleID: String) async -> SourceAppRecord {
        SourceAppRecord(bundleID: bundleID, displayName: "Notes", iconData: Data(), dominantColorHex: "#FFCC00")
    }
}

private struct IconSourceApps: SourceAppResolving {
    static let icon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])

    func resolve(bundleID: String) async -> SourceAppRecord {
        SourceAppRecord(bundleID: bundleID, displayName: "Notes", iconData: Self.icon, dominantColorHex: "#FAD927")
    }
}

@Suite("A synced clip keeps the name of the app it came from", .serialized)
@MainActor
struct SyncSourceAppTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-source-\(UUID().uuidString)")
    )
    let time = TimeBox()

    private func exchange(_ sites: [SyncSite]) async {
        for _ in 0..<2 {
            for site in sites {
                time.advance()
                await site.service.syncNow()
            }
        }
    }

    @Test("a device that cannot look an app up by its bundle ID shows the name the clip arrived with")
    func whenTheReceiverCannotResolveTheApp_thenTheArrivedNameIsKept() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let mac = try SyncSite(
            name: "mac-a", layout: layout, time: time, environment: .testing { $0.sourceApps = NamedSourceApps() }
        )
        let phone = try SyncSite(
            name: "iphone-b", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        let made = try SyncGroupManager.create(
            layout: layout, identity: mac.identity, keyStore: mac.keyStore, now: time.now
        )
        try phone.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await mac.copy("from Notes")
        #expect(try mac.item("from Notes")?.sourceAppName == "Notes")

        await exchange([mac, phone])

        let arrived = try #require(try phone.item("from Notes"))
        #expect(arrived.sourceBundleID == "com.apple.Notes")
        #expect(arrived.sourceAppName == "Notes")
    }

    @Test("a device that knows the app keeps its own name for it")
    func whenTheReceiverResolvesTheApp_thenItsOwnNameIsUsed() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let phone = try SyncSite(
            name: "iphone-a", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        let mac = try SyncSite(
            name: "mac-b", layout: layout, time: time, environment: .testing { $0.sourceApps = NamedSourceApps() }
        )
        let made = try SyncGroupManager.create(
            layout: layout, identity: phone.identity, keyStore: phone.keyStore, now: time.now
        )
        try mac.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await phone.copy("typed on the phone")
        #expect(try phone.item("typed on the phone")?.sourceAppName == SourceAppRecord.unknownDisplayName)

        await exchange([phone, mac])

        #expect(try mac.item("typed on the phone")?.sourceAppName == "Notes")
    }

    @Test("a Universal Clipboard echo synced back from Mac never relabels the phone's local clip as Another device")
    func whenMacEchoesRemoteUpdateForLocalPhoneClip_thenPhoneKeepsLocalProvenance() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let phone = try SyncSite(
            name: "iphone-a", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        let mac = try SyncSite(
            name: "mac-b", layout: layout, time: time, environment: .testing { $0.sourceApps = NamedSourceApps() }
        )
        let made = try SyncGroupManager.create(
            layout: layout, identity: phone.identity, keyStore: phone.keyStore, now: time.now
        )
        try mac.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await phone.copy("copied on phone")

        await exchange([phone, mac])

        time.advance()
        let payload = Data("copied on phone".utf8)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try await mac.storage.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: payload,
            payloadString: "copied on phone",
            frontmostBundleID: nil,
            timestamp: time.now,
            contentHash: hash,
            isRemote: true
        ))

        await exchange([mac, phone])

        let afterEcho = try #require(try phone.item("copied on phone"))
        #expect(!afterEcho.isRemote)
        #expect(afterEcho.sourceAppName != PasteboardCapture.remoteSourceName)
    }

    @Test("a device that cannot sample an app gets its color with the clip and its icon from the Mac's catalog")
    func whenTheMacKnowsTheApp_thenThePhoneGetsColorAndIcon() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let mac = try SyncSite(
            name: "mac-a", layout: layout, time: time, environment: .testing { $0.sourceApps = IconSourceApps() }
        )
        let phone = try SyncSite(
            name: "iphone-b", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        var received: [SyncAppCatalog.Entry] = []
        phone.service.onAppCatalog = { received = $0 }
        var macReceived: [SyncAppCatalog.Entry] = []
        mac.service.onAppCatalog = { macReceived = $0 }
        let made = try SyncGroupManager.create(
            layout: layout, identity: mac.identity, keyStore: mac.keyStore, now: time.now
        )
        try phone.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await mac.copy("from Notes")

        await exchange([mac, phone])

        #expect(try phone.item("from Notes")?.sourceDominantColorHex == "#FAD927")
        #expect(received.map(\.bundleID) == ["com.apple.Notes"])
        #expect(received.first?.icon == IconSourceApps.icon)
        #expect(macReceived.isEmpty, "an iPhone resolves no app, so it writes no catalog")
        #expect(!FileManager.default.fileExists(atPath: layout.appCatalog(phone.identity.deviceID).path))
    }

    @Test("after Reset Sync on another device the Mac writes its catalog again under the new epoch")
    func whenTheGroupIsReset_thenTheCatalogIsWrittenAgain() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let mac = try SyncSite(
            name: "mac-a", layout: layout, time: time, environment: .testing { $0.sourceApps = IconSourceApps() }
        )
        let phone = try SyncSite(
            name: "iphone-b", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        var received: [SyncAppCatalog.Entry] = []
        phone.service.onAppCatalog = { received = $0 }
        let made = try SyncGroupManager.create(
            layout: layout, identity: mac.identity, keyStore: mac.keyStore, now: time.now
        )
        try phone.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await mac.copy("from Notes")
        await exchange([mac, phone])
        #expect(received.count == 1)

        let next = try SyncGroupManager.reset(
            layout: layout, from: made.group, identity: phone.identity, keyStore: phone.keyStore, now: time.now
        )
        try mac.keyStore.saveSyncKey(next.group.key, vaultID: next.group.vault.vaultID, epoch: 2)
        received = []
        await exchange([mac, phone])

        guard case let .ready(now) = try SyncGroupManager.open(layout: layout, keyStore: phone.keyStore) else {
            Issue.record("no group")
            return
        }
        let data = try #require(SyncSmallFile.read(layout.appCatalog(mac.identity.deviceID)))
        let opened = try SyncAppCatalog.open(
            data, syncKey: now.key, trust: now.trust, deviceID: mac.identity.deviceID, epoch: now.epoch
        )
        #expect(opened.entries.map(\.bundleID) == ["com.apple.Notes"])
        #expect(received.map(\.bundleID) == ["com.apple.Notes"])
    }

    @Test("a clip that stays on the Mac (a secret) does not name its app to the other devices")
    func whenAClipStaysHere_thenItsAppIsNotInTheCatalog() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let mac = try SyncSite(
            name: "mac-a", layout: layout, time: time, environment: .testing { $0.sourceApps = IconSourceApps() }
        )
        let phone = try SyncSite(
            name: "iphone-b", layout: layout, time: time, environment: .testing { $0.sourceApps = UnknownSourceApps() }
        )
        var received: [SyncAppCatalog.Entry] = []
        phone.service.onAppCatalog = { received = $0 }
        let made = try SyncGroupManager.create(
            layout: layout, identity: mac.identity, keyStore: mac.keyStore, now: time.now
        )
        try phone.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await mac.copy("from Notes")
        try await mac.copy("4111 1111 1111 1111", from: "com.example.Vault")

        await exchange([mac, phone])

        #expect(received.map(\.bundleID) == ["com.apple.Notes"])
    }
}
