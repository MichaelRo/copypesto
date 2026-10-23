// SPDX-License-Identifier: MIT
import Foundation

/// When a shelf key that acts on the focused clip may act. The keys never reach past a card's concealment: a clip that
/// is hidden, filtered, still being analysed or covered for a screen share offers no side door (ADR 0003, ADR 0003).
public enum ShelfKeyGate {
    /// ⌘Y opens Quick Look on a clip only when nothing covers it.
    public static func quickLookAllowed(
        isHidden: Bool, isFilteredContent: Bool, isPendingAnalysis: Bool, isCoveredForSharing: Bool
    )
    -> Bool {
        !isHidden && !isFilteredContent && !isPendingAnalysis && !isCoveredForSharing
    }

    /// ⇧Return pastes the focused clip's text without formatting. Only the kinds whose menu offers Plain Text have text
    /// to paste that way.
    public static func plainPasteAllowed(for type: ClipboardType) -> Bool {
        switch type {
        case .text, .code, .url, .color: true
        default: false
        }
    }
}
