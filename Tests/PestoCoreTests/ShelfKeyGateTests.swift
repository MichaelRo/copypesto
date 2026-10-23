// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Shelf keys that act on the focused clip")
struct ShelfKeyGateTests {
    @Test("Quick Look opens on a clip nothing covers")
    func whenNothingCovers_thenQuickLookIsAllowed() {
        #expect(ShelfKeyGate.quickLookAllowed(
            isHidden: false, isFilteredContent: false, isPendingAnalysis: false, isCoveredForSharing: false
        ))
    }

    @Test("Quick Look never opens on a covered clip", arguments: [
        (true, false, false, false), (false, true, false, false), (false, false, true, false), (
            false,
            false,
            false,
            true
        )
    ])
    func whenCovered_thenNoQuickLook(hidden: Bool, filtered: Bool, pending: Bool, sharing: Bool) {
        #expect(!ShelfKeyGate.quickLookAllowed(
            isHidden: hidden, isFilteredContent: filtered, isPendingAnalysis: pending, isCoveredForSharing: sharing
        ))
    }

    @Test("plain-text paste is offered for the kinds that have text, and for nothing else")
    func whenKind_thenPlainPasteFollowsTheMenu() {
        for type in ClipboardType.allCases {
            let hasText = [ClipboardType.text, .code, .url, .color].contains(type)
            #expect(ShelfKeyGate.plainPasteAllowed(for: type) == hasText, "\(type)")
        }
    }
}
