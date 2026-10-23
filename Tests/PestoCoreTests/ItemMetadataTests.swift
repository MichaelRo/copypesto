// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Item metadata")
struct ItemMetadataTests {
    @Test("nothing set is empty, any one field is not")
    func isEmpty_followsTheFields() {
        #expect(ItemMetadata().isEmpty)
        #expect(!ItemMetadata(customTitle: "t").isEmpty)
        #expect(!ItemMetadata(customSymbolName: "star.fill").isEmpty)
        #expect(!ItemMetadata(collectionOrder: 0).isEmpty)
        #expect(!ItemMetadata(tags: ["a"]).isEmpty)
        #expect(!ItemMetadata(ogSiteName: "site").isEmpty)
        #expect(!ItemMetadata(linkPreviewFetched: true).isEmpty)
        #expect(ItemMetadata(linkPreviewFetched: false).isEmpty)
    }

    @Test("stored tag text splits on commas, trimmed, blanks dropped")
    func parseTags_trimsAndDropsBlanks() {
        #expect(ItemMetadata.parseTags("a, b ,,c") == ["a", "b", "c"])
        #expect(ItemMetadata.parseTags("").isEmpty)
    }

    @Test("it round-trips through JSON")
    func codable_roundTrips() throws {
        let value = ItemMetadata(
            customTitle: "T", userNote: "N", tags: ["x"], customSymbolName: "star.fill",
            collectionOrder: 4, ogTitle: "O", ogSiteName: "S", linkPreviewFetched: true
        )
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ItemMetadata.self, from: data) == value)
    }

    @Test("the cache opens a ciphertext once and clear() forgets it")
    func cache_opensOnce() {
        let cache = PreviewTextCache()
        let id = UUID()
        let nonce = Data([1, 2, 3])
        var opened = 0
        let decrypt: () -> ItemMetadata? = {
            opened += 1
            return ItemMetadata(customTitle: "T")
        }

        _ = cache.metadata(id: id, nonce: nonce, decrypt: decrypt)
        _ = cache.metadata(id: id, nonce: nonce, decrypt: decrypt)
        #expect(opened == 1)
        #expect(!cache.isEmpty)

        cache.clear()
        #expect(cache.isEmpty)
    }

    @Test("a custom icon is offered only for a clip in a collection or one that already has an icon")
    func whenCheckingOffersCustomIcon_thenCollectionOrExistingSymbolRequired() {
        let plain = ClipboardItem(
            type: .text, previewText: "hello", contentHash: "h1", byteSize: 5, deviceID: "d", sequenceNumber: 1
        )
        #expect(!plain.offersCustomIcon)

        let inCollection = ClipboardItem(
            type: .text, previewText: "hello", contentHash: "h2", byteSize: 5, deviceID: "d", sequenceNumber: 2,
            collectionID: UUID()
        )
        #expect(inCollection.offersCustomIcon)

        let alreadyCustomized = ClipboardItem(
            type: .text, previewText: "hello", contentHash: "h3", byteSize: 5, deviceID: "d", sequenceNumber: 3
        )
        alreadyCustomized.customSymbolName = "star.fill"
        #expect(alreadyCustomized.offersCustomIcon)
    }
}
