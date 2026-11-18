// SPDX-License-Identifier: MIT
import Foundation

enum NoteDraft {
    /// A note with anything typed in it is not thrown away by a swipe or a Cancel without asking.
    static func needsDiscardConfirmation(_ text: String) -> Bool {
        !text.isEmpty
    }
}
