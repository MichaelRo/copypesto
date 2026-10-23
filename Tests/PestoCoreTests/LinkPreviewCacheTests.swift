// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("LinkPreviewCache")
struct LinkPreviewCacheTests {
    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-test-cache-\(UUID().uuidString)")
            .appendingPathComponent("metadata-cache.json")
    }

    @Test("stores and retrieves preview entries by URL")
    func storeAndRetrieve() throws {
        let file = tempCacheURL()
        let cache = LinkPreviewCache(fileURL: file)
        let url = try #require(URL(string: "https://example.com/test"))
        let entry = LinkPreviewCache.Entry(
            title: "Test Page",
            siteName: "Example",
            faviconData: Data([1, 2]),
            ogImageData: Data([3, 4])
        )

        cache.store(entry, for: url)
        let retrieved = cache.entry(for: url)

        #expect(retrieved?.title == "Test Page")
        #expect(retrieved?.siteName == "Example")
        #expect(retrieved?.faviconData == Data([1, 2]))
        #expect(retrieved?.ogImageData == Data([3, 4]))
        #expect(retrieved?.isNegative == false)

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test("expires entries older than TTL")
    func ttlExpiration() throws {
        let file = tempCacheURL()
        let cache = LinkPreviewCache(fileURL: file, ttl: 10)
        let url = try #require(URL(string: "https://example.com/expired"))
        let oldDate = Date.now.addingTimeInterval(-20)
        let entry = LinkPreviewCache.Entry(
            title: "Old Page",
            siteName: "Example",
            faviconData: nil,
            ogImageData: nil,
            fetchedAt: oldDate
        )

        cache.store(entry, for: url)
        #expect(cache.entry(for: url, now: .now) == nil)

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test("persists across cache instances using same file")
    func persistenceAcrossInstances() throws {
        let file = tempCacheURL()
        let url = try #require(URL(string: "https://example.com/persist"))
        let entry = LinkPreviewCache.Entry(
            title: "Persistent Title",
            siteName: "Persistent Site",
            faviconData: nil,
            ogImageData: nil
        )

        let cache1 = LinkPreviewCache(fileURL: file)
        cache1.store(entry, for: url)

        let cache2 = LinkPreviewCache(fileURL: file)
        let retrieved = cache2.entry(for: url)
        #expect(retrieved?.title == "Persistent Title")
        #expect(retrieved?.siteName == "Persistent Site")

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test("negative cache entries are retrieved as negative")
    func negativeCaching() throws {
        let file = tempCacheURL()
        let cache = LinkPreviewCache(fileURL: file)
        let url = try #require(URL(string: "https://example.com/404"))
        let entry = LinkPreviewCache.Entry(
            title: nil,
            siteName: nil,
            faviconData: nil,
            ogImageData: nil,
            isNegative: true
        )

        cache.store(entry, for: url)
        let retrieved = cache.entry(for: url)
        #expect(retrieved?.isNegative == true)

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    @Test("the file on disk holds neither the title nor the address, and an old plaintext cache beside it is removed")
    func sealedOnDisk() throws {
        let directory = tempCacheURL().deletingLastPathComponent()
        let file = directory.appendingPathComponent("metadata-cache.sealed")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("metadata-cache.json")
        try Data(#"{"abc":{"title":"Old plaintext title"}}"#.utf8).write(to: old)
        let cache = LinkPreviewCache(fileURL: file)
        let url = try #require(URL(string: "https://private.example.com/secret-plan"))

        cache.store(
            LinkPreviewCache.Entry(title: "Confidential Page Title", siteName: nil, faviconData: nil, ogImageData: nil),
            for: url
        )

        #expect(!FileManager.default.fileExists(atPath: old.path))
        let onDisk = try Data(contentsOf: file)
        #expect(onDisk.range(of: Data("Confidential".utf8)) == nil)
        #expect(onDisk.range(of: Data("secret-plan".utf8)) == nil)
        cache.clear()
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try? FileManager.default.removeItem(at: directory)
    }
}
