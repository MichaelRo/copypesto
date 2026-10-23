// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The sealed link-preview cache goes with the clips it describes (R-04)")
struct LinkPreviewCacheDeletionTests {
    private func makeCache() -> LinkPreviewCache {
        LinkPreviewCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-cache-\(UUID().uuidString)")
                .appendingPathComponent("metadata-cache.sealed")
        )
    }

    private func entry(_ title: String) -> LinkPreviewCache.Entry {
        LinkPreviewCache.Entry(title: title, siteName: nil, faviconData: nil, ogImageData: nil)
    }

    private func service(cache: LinkPreviewCache) throws -> (StorageService, ModelContainer) {
        let container = try ModelContainerSetup.makeInMemory().synced
        let environment = StorageEnvironment.testing { $0.linkPreviewCache = cache }
        return (StorageService(modelContainer: container, environment: environment), container)
    }

    private func ingest(_ url: URL, into service: StorageService) async throws {
        let text = url.absoluteString
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text, contentHash: hash
        ))
    }

    private func id(of url: URL, in container: ModelContainer) throws -> UUID {
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        return try #require(items.first { $0.displayPreviewText == url.absoluteString }).id
    }

    @Test("deleting a link clip drops that page's cache entry and keeps the others")
    func whenALinkClipIsDeleted_thenItsEntryGoes() async throws {
        let kept = try #require(URL(string: "https://example.com/kept"))
        let gone = try #require(URL(string: "https://example.com/gone"))
        let cache = makeCache()
        cache.store(entry("gone"), for: gone)
        cache.store(entry("kept"), for: kept)
        let (service, container) = try service(cache: cache)
        try await ingest(gone, into: service)
        try await ingest(kept, into: service)

        try await service.deleteItems(ids: [id(of: gone, in: container)], reason: .user)

        #expect(cache.entry(for: gone) == nil)
        #expect(cache.entry(for: kept)?.title == "kept")
    }

    @Test("Clear History empties the cache, and so does an age-based removal of the clip")
    func whenHistoryIsCleared_thenTheCacheIsEmpty() async throws {
        let kept = try #require(URL(string: "https://example.com/kept"))
        let gone = try #require(URL(string: "https://example.com/gone"))
        let cache = makeCache()
        cache.store(entry("gone"), for: gone)
        cache.store(entry("other"), for: kept)
        let (service, _) = try service(cache: cache)
        try await ingest(gone, into: service)

        _ = try await service.clearNonPinned(in: .all)

        #expect(cache.entry(for: gone) == nil)
        #expect(cache.entry(for: kept) == nil)
    }
}
