// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    /// An edit made while the sealed metadata could not be opened or sealed used to wipe the title and
    /// note
    /// and write what was left into the plaintext columns.
    @Suite("Metadata fails closed", .serialized)
    struct MetadataFailClosedTests {
        private func sealedItem(title: String) -> ClipboardItem {
            let item = ClipboardItem(
                type: .text, previewText: "x", contentHash: "h\(UUID().uuidString)", byteSize: 1,
                deviceID: "d", sequenceNumber: 1
            )
            item.customTitle = title
            return item
        }

        @Test("an edit to metadata that will not open changes nothing")
        func whenCiphertextDoesNotOpen_thenEditIsRefused() throws {
            let item = sealedItem(title: "Quarterly numbers")
            let original = try #require(item.metadataCiphertext)
            item.metadataNonce = Data(repeating: 7, count: 12)
            PreviewTextCache.shared.clear()
            #expect(item.metadataIsUnreadable)

            item.tags = ["finance"]

            #expect(item.metadataCiphertext == original, "the sealed bytes must be left alone")
            #expect(item.legacyTagsRaw.isEmpty, "nothing may be written in the clear")
        }

        @Test("when sealing fails the earlier metadata stays and nothing reaches the plaintext columns")
        func whenSealingFails_thenNothingChanges() throws {
            let item = sealedItem(title: "Quarterly numbers")
            let before = try #require(item.metadataCiphertext)

            item.updateMetadata(
                sealing: { _, _ in throw BlobEncryption.Error.keyMissing },
                { $0.userNote = "private note" }
            )

            #expect(item.metadataCiphertext == before)
            #expect(item.legacyUserNote == nil)
            #expect(item.customTitle == "Quarterly numbers")
        }

        @Test("ordinary edits still seal and read back")
        func whenSealingWorks_thenEditsStick() {
            let item = sealedItem(title: "Quarterly numbers")

            item.userNote = "check with Dana"

            #expect(item.userNote == "check with Dana")
            #expect(item.customTitle == "Quarterly numbers")
            #expect(item.legacyUserNote == nil)
        }
    }
}
