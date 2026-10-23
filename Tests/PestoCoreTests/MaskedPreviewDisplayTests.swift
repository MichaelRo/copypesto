// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The masked preview a card shows")
struct MaskedPreviewDisplayTests {
    private func item(_ category: SensitivityCategory?, masked: String?) -> ClipboardItem {
        ClipboardItem(
            type: .text, previewText: "", sensitivity: category, sensitivityMaskedPreview: masked,
            contentHash: UUID().uuidString, byteSize: 40, deviceID: "device", sequenceNumber: 1
        )
    }

    @Test("keeps what the stored mask says: the last four digits, the key's label and prefix, the app's name")
    func whenAMaskIsStored_thenItIsWhatTheCardShows() {
        let card = item(.creditCard, masked: "•••• •••• •••• 4242")
        let token = item(.oauthToken, masked: "ghp_•••• (GitHub PAT, 36 characters hidden)")
        let credential = item(.credential, masked: "Hidden by 1Password")

        #expect(card.localizedMaskedPreview == "•••• •••• •••• 4242")
        #expect(token.localizedMaskedPreview == "ghp_•••• (GitHub PAT, 36 characters hidden)")
        #expect(credential.localizedMaskedPreview == "Hidden by 1Password")
    }

    @Test("falls back to the generic mask for the category when nothing was stored")
    func whenNoMaskIsStored_thenTheGenericOneIsShown() {
        let token = item(.oauthToken, masked: nil)

        #expect(token.localizedMaskedPreview == SensitiveContentDetector.localizedMask(for: .oauthToken, count: 0))
    }

    @Test("an item that is not sensitive has no mask")
    func whenNotSensitive_thenNoMask() {
        #expect(item(nil, masked: nil).localizedMaskedPreview == nil)
    }
}
