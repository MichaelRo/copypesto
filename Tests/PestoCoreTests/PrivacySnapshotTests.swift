// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("What the privacy dashboard reports, and the panic button", .serialized)
struct PrivacySnapshotTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func ingest(_ text: String, at time: Date) async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text, timestamp: time,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        ))
    }

    @Test("an empty history reports zeros")
    func whenEmpty_thenZeros() async throws {
        let snapshot = try await service.privacySnapshot()
        #expect(snapshot.clipCount == 0 && snapshot.pinnedCount == 0 && snapshot.maskedSecretCount == 0)
        #expect(snapshot.oldest == nil)
    }

    @Test("it counts clips, pinned clips, masked secrets and the oldest clip")
    func whenHistoryHasContent_thenCounted() async throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try await ingest("plain note", at: old)
        try await ingest("4111 1111 1111 1111", at: old.addingTimeInterval(60))
        try await ingest("another note", at: old.addingTimeInterval(120))
        let ctx = ModelContext(container)
        try #require(try ctx.fetch(FetchDescriptor<ClipboardItem>()).first { $0.displayPreviewText == "another note" })
            .isPinned = true
        try ctx.save()

        let snapshot = try await service.privacySnapshot()

        #expect(snapshot.clipCount == 3)
        #expect(snapshot.pinnedCount == 1)
        #expect(snapshot.maskedSecretCount == 1)
        #expect(snapshot.oldest == old)
    }

    @Test("clearing everything removes pinned clips too, unlike Clear History")
    func whenClearEverything_thenPinnedGoneToo() async throws {
        try await ingest("keep me? no", at: .now)
        let ctx = ModelContext(container)
        try #require(try ctx.fetch(FetchDescriptor<ClipboardItem>()).first).isPinned = true
        try ctx.save()
        try await ingest("second", at: .now.addingTimeInterval(5))

        let removed = try await service.clearEverything()

        #expect(removed == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 0)
        #expect(try await service.privacySnapshot().clipCount == 0)
    }

    @Test("the panic button also forgets what was searched for")
    func whenClearEverything_thenSearchHistoryGone() async throws {
        AppDefaults.store.set(SearchHistory.recording("secret query", in: ""), forKey: SearchHistory.defaultsKey)
        defer { AppDefaults.store.removeObject(forKey: SearchHistory.defaultsKey) }
        try await ingest("something", at: .now)

        try await service.clearEverything()

        #expect(AppDefaults.store.string(forKey: SearchHistory.defaultsKey) == nil)
    }

    @Test("the panic button removes the collections too, smart ones included")
    func whenClearEverything_thenCollectionsGoToo() async throws {
        let context = ModelContext(container)
        context.insert(Pinboard(name: "Work", symbolName: "folder", colorHex: "#4C8DFF", sortOrder: 0))
        let smart = Pinboard(name: "Links", symbolName: "link", colorHex: "#34C759", sortOrder: 1)
        smart.isSmart = true
        context.insert(smart)
        try context.save()
        try await ingest("a clip", at: .now)

        try await service.clearEverything()

        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Pinboard>()) == 0)
    }
}
