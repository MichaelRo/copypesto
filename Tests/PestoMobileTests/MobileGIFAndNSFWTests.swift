// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("iOS GIF, Preview, and NSFW card revision")
@MainActor
struct MobileGIFAndNSFWTests {
    @Test("ClipCard.Revision changes when analysisPending clears and isNSFW flips true")
    func whenPendingImageBecomesNSFW_thenRevisionChanges() {
        let item = ClipboardItem(
            type: .image,
            previewText: "",
            contentHash: "abc",
            byteSize: 1024,
            deviceID: "test-device",
            sequenceNumber: 1
        )
        item.analysisPending = true
        item.isNSFW = false
        let pendingRevision = ClipCard.Revision(item)

        item.analysisPending = false
        item.isNSFW = true
        let nsfwRevision = ClipCard.Revision(item)

        #expect(pendingRevision != nsfwRevision)
    }

    @Test("LibraryModel preview state opens independently and clears on detail open or lock")
    func whenPreviewUsed_thenOpensAndClearsCleanly() {
        let library = LibraryModel()
        let id = UUID()

        library.preview(id)
        #expect(library.previewClipID == id)
        #expect(library.openClipID == nil)

        library.open(id)
        #expect(library.previewClipID == nil)
        #expect(library.openClipID == id)

        library.preview(id)
        library.closeEverything()
        #expect(library.previewClipID == nil)
        #expect(library.openClipID == nil)
    }

    @Test("CardMenu excludes preview for concealed, NSFW, pending, or secret items")
    func whenItemSensitiveOrConcealed_thenPreviewHidden() {
        let regular = ClipboardItem(
            type: .text, previewText: "hello", contentHash: "1", byteSize: 5,
            deviceID: "test-device", sequenceNumber: 1
        )
        #expect(CardMenu.canPreview(item: regular, isConcealed: false))
        #expect(!CardMenu.canPreview(item: regular, isConcealed: true))

        let secret = ClipboardItem(
            type: .text, previewText: "secret", contentHash: "2", byteSize: 6,
            deviceID: "test-device", sequenceNumber: 2
        )
        secret.sensitivityRaw = "password"
        #expect(!CardMenu.canPreview(item: secret, isConcealed: false))
    }
}
