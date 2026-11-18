// SPDX-License-Identifier: MIT
import Foundation

/// What to do with the clipboard when Pesto comes to the front. Only the change count and whether something is there
/// are read to decide (no permission prompt); the content is read only when the person turned on adding copies.
enum ClipboardOffer: Equatable {
    case nothing
    /// The banner "Add what you copied", whose action is the system Paste button.
    case offer
    /// Read the clipboard and add it through the normal capture path.
    case addNow

    static func decide(changeCount: Int, lastSeen: Int, hasContent: Bool, addsAutomatically: Bool) -> ClipboardOffer {
        guard changeCount != lastSeen, hasContent else { return .nothing }
        return addsAutomatically ? .addNow : .offer
    }
}
