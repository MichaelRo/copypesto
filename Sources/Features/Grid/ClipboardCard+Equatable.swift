// SPDX-License-Identifier: MIT
import SwiftUI

/// Two cards are the same when every value the shelf hands them is. The shelf re-runs when focus moves, and without
/// this
/// every realized card re-ran its body each time though only two of them (the one losing focus, the one gaining it) had
/// a
/// different input. What a card reads itself (the clip's fields, its own state, the settings and the environment) still
/// redraws it: `.equatable()` only decides whether a new input from the parent does.
/// SwiftUI compares views on the main thread, which is why the comparison may assume it.
extension ClipboardCard: Equatable {
    nonisolated static func == (lhs: ClipboardCard, rhs: ClipboardCard) -> Bool {
        MainActor.assumeIsolated { sameInputs(lhs, rhs) }
    }

    private static func sameInputs(_ lhs: ClipboardCard, _ rhs: ClipboardCard) -> Bool {
        lhs.item === rhs.item
            && lhs.focusAnchor === rhs.focusAnchor
            && lhs.scrollState === rhs.scrollState
            && lhs.isFocused == rhs.isFocused
            && lhs.shortcutNumber == rhs.shortcutNumber
            && lhs.revealsDetail == rhs.revealsDetail
            && lhs.detailSuppressed == rhs.detailSuppressed
            && lhs.isSelected == rhs.isSelected
            && lhs.showRequest == rhs.showRequest
            && lhs.isFlashing == rhs.isFlashing
            && lhs.unavailableHotkeySlots == rhs.unavailableHotkeySlots
            && lhs.isPrivacyBlurred == rhs.isPrivacyBlurred
            && lhs.availableCollections == rhs.availableCollections
            && lhs.revealedFromOutside == rhs.revealedFromOutside
            && lhs.previewsAllowed == rhs.previewsAllowed
            && lhs.hideSecretsGeneration == rhs.hideSecretsGeneration
            && lhs.canRevealHidden == rhs.canRevealHidden
            && lhs.isSuggested == rhs.isSuggested
            && lhs.suggestedHotkeySlot == rhs.suggestedHotkeySlot
            && lhs.showsFirstCopyTime == rhs.showsFirstCopyTime
    }
}
