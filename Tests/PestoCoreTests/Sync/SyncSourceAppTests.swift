// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private struct NamedSourceApps: SourceAppResolving {
    func resolve(bundleID: String) async -> SourceAppRecord {
        SourceAppRecord(bundleID: bundleID, displayName: "Notes", iconData: Data(), dominantColorHex: "#FFCC00")
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
}
