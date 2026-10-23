// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("StorageService heavy columns")
struct StorageServiceHeavyColumnsTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container)
    }

    private func fetchItems() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func capture(text: String, bundleID: String? = nil) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(text.utf8),
            payloadString: text,
            frontmostBundleID: bundleID,
            contentHash: UUID().uuidString
        )
    }

    @Test("legacy per-item icons are dropped; icons resolve by bundle ID instead")
    func clearLegacyIcons_emptiesTheColumn() async throws {
        let ctx = ModelContext(container)
        for index in 0..<3 {
            let item = ClipboardItem(
                type: .text, previewText: "x", contentHash: "h-\(index)", byteSize: 1, deviceID: "d",
                sequenceNumber: Int64(index)
            )
            item.sourceBundleID = "com.apple.finder"
            item.sourceIconData = Data(repeating: 7, count: 512)
            ctx.insert(item)
        }
        try ctx.save()

        #expect(try await service.clearLegacyIcons() == 3)

        let after = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(after.allSatisfy { $0.sourceIconData == nil })
        #expect(after.allSatisfy { $0.sourceBundleID == "com.apple.finder" })
        #expect(try await service.clearLegacyIcons() == 0, "running it again must change nothing")
    }

    @Test("a new capture does not copy the app icon onto the item")
    func ingest_doesNotStoreTheIcon() async throws {
        try await service.ingest(capture(text: "from finder", bundleID: "com.apple.finder"))
        let item = try #require(fetchItems().first)
        #expect(item.sourceBundleID == "com.apple.finder")
        #expect(item.sourceIconData == nil)
    }

    @Test("link preview images move out of the item rows into the encrypted store")
    func moveLinkPreviewImages_movesAndClearsTheColumn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-og-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = LinkPreviewImageStore(directory: directory, key: { key })
        let service = StorageService(modelContainer: container, environment: .testing { $0.linkPreviews = store })
        let ctx = ModelContext(container)
        let image = Data(repeating: 9, count: 30 * 1024)
        var withImage: [UUID] = []
        for index in 0..<3 {
            let item = ClipboardItem(
                type: .url, previewText: "", contentHash: "u-\(index)", byteSize: 1, deviceID: "d",
                sequenceNumber: Int64(index)
            )
            if index < 2 {
                item.ogImageThumbnail = image
                withImage.append(item.id)
            }
            ctx.insert(item)
        }
        try ctx.save()

        #expect(try await service.moveLinkPreviewImages() == 2)

        let after = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(after.allSatisfy { $0.ogImageThumbnail == nil })
        #expect(withImage.allSatisfy { store.load(for: $0) == image })
        #expect(try await service.moveLinkPreviewImages() == 0, "running it again must change nothing")
    }

    @Test("deleting an item deletes its link preview image")
    func deleteItems_removesTheLinkPreviewImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-og-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = LinkPreviewImageStore(directory: directory, key: { key })
        let service = StorageService(modelContainer: container, environment: .testing { $0.linkPreviews = store })
        try await service.ingest(capture(text: "https://example.com/a"))
        let id = try #require(fetchItems().first?.id)
        try store.save(Data([1, 2, 3]), for: id)

        try await service.deleteItems(ids: [id], reason: .user)

        #expect(store.load(for: id) == nil)
    }

    @Test("clearing history deletes every link preview image")
    func clearNonPinned_removesLinkPreviewImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-og-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = LinkPreviewImageStore(directory: directory, key: { key })
        let service = StorageService(modelContainer: container, environment: .testing { $0.linkPreviews = store })
        try await service.ingest(capture(text: "https://example.com/b"))
        let id = try #require(fetchItems().first?.id)
        try store.save(Data([1, 2, 3]), for: id)

        try await service.clearNonPinned(in: .all)

        #expect(store.load(for: id) == nil)
    }
}
