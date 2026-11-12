// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

@Suite("Card equality")
@MainActor
struct ClipboardCardEqualityTests {
    private let item = ClipboardItem(
        type: .text, previewText: "hello", contentHash: "h", byteSize: 5, deviceID: "test-device", sequenceNumber: 1
    )

    private func card(_ change: (inout ClipboardCard) -> Void = { _ in }) -> ClipboardCard {
        var card = ClipboardCard(item: item)
        change(&card)
        return card
    }

    @Test("two cards handed the same values are equal, so the shelf does not run the second one's body")
    func whenInputsMatch_thenCardsAreEqual() {
        #expect(card() == card())
    }

    @Test("every value the shelf hands a card makes it differ, so none can leave a card stale")
    func whenAnInputChanges_thenCardsDiffer() {
        let other = ClipboardItem(
            type: .text, previewText: "other", contentHash: "o", byteSize: 5, deviceID: "test-device", sequenceNumber: 2
        )
        let changes: [(String, (inout ClipboardCard) -> Void)] = [
            ("item", { $0 = ClipboardCard(item: other) }),
            ("isFocused", { $0.isFocused = true }),
            ("focusAnchor", { $0.focusAnchor = FocusedCardAnchor() }),
            ("shortcutNumber", { $0.shortcutNumber = 3 }),
            ("revealsDetail", { $0.revealsDetail = true }),
            ("detailSuppressed", { $0.detailSuppressed = true }),
            ("scrollState", { $0.scrollState = ShelfScrollState() }),
            ("isSelected", { $0.isSelected = true }),
            ("isFlashing", { $0.isFlashing = true }),
            ("unavailableHotkeySlots", { $0.unavailableHotkeySlots = [2] }),
            ("isPrivacyBlurred", { $0.isPrivacyBlurred = true }),
            (
                "availableCollections",
                { $0.availableCollections = [CollectionRef(id: UUID(), name: "A", symbolName: "tray")] }
            ),
            ("revealedFromOutside", { $0.revealedFromOutside = true }),
            ("previewsAllowed", { $0.previewsAllowed = false }),
            ("hideSecretsGeneration", { $0.hideSecretsGeneration = 1 }),
            ("canRevealHidden", { $0.canRevealHidden = false }),
            ("isSuggested", { $0.isSuggested = true }),
            ("suggestedHotkeySlot", { $0.suggestedHotkeySlot = 4 }),
            ("showsFirstCopyTime", { $0.showsFirstCopyTime = true })
        ]
        for (name, change) in changes {
            #expect(card() != card(change), "\(name) must make two cards differ")
        }
    }

    @Test("the same collections rebuilt each time the shelf updates still compare equal")
    func whenCollectionsAreRebuilt_thenCardsStayEqual() {
        let id = UUID()
        let first = card { $0.availableCollections = [CollectionRef(id: id, name: "A", symbolName: "tray")] }
        let second = card { $0.availableCollections = [CollectionRef(id: id, name: "A", symbolName: "tray")] }
        #expect(first == second)
    }
}
