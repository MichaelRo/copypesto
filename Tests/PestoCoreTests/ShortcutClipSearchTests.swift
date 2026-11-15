// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("What a Shortcuts action may hand out")
struct ShortcutClipSearchTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private func capture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("a search finds plain clips and never a secret, not even by its own text or an empty query")
    func whenSearched_thenSecretsAreNeverReturned() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing())
        try await service.ingest(capture("dinner at eight, token below"))
        try await service.ingest(capture(secret))
        await service.waitForBackgroundWork()
        let context = ModelContext(container)

        let everything = try ShortcutClipSearch.search("", in: context, nsfwMode: .blur)
        #expect(everything.map(\.title) == ["dinner at eight, token below"])
        #expect(try ShortcutClipSearch.search("ghp_", in: context, nsfwMode: .blur).isEmpty)
        #expect(try ShortcutClipSearch.search("dinner", in: context, nsfwMode: .blur).first?.type == .text)

        let ids = try context.fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
        let byID = try ShortcutClipSearch.clips(ids: ids, in: context, nsfwMode: .blur)
        #expect(byID.count == 1)
        #expect(!byID.contains { $0.title.contains("ghp_") })
    }

    @Test("a clip the content filter covers, or one still being judged, is not offered")
    func whenCoveredOrPending_thenNotOffered() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .text, previewText: "", contentHash: UUID().uuidString, byteSize: 1, deviceID: "t", sequenceNumber: 1
        )
        context.insert(item)
        item.isNSFW = true
        #expect(!ShortcutClipSearch.isOffered(item, nsfwMode: .blur))
        #expect(ShortcutClipSearch.isOffered(item, nsfwMode: .show))
        item.isNSFW = false
        item.analysisPending = true
        #expect(!ShortcutClipSearch.isOffered(item, nsfwMode: .show))
    }
}
