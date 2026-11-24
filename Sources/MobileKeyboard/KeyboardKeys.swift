// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What a key does to the field being typed in, set by the view controller that owns the text document proxy.
@MainActor
struct KeyboardKeys {
    let insert: (String) -> Void
    let deleteBackward: () -> Void
    let switchKeyboard: () -> Void
    /// The field's text around the caret, read again at the moment a search's word is replaced.
    let contextBefore: () -> String?
    let contextAfter: () -> String?
    /// Sets the keyboard's height again, after the search page opens or closes.
    let relayout: () -> Void
    /// Updates the card size directly from inside the keyboard and persists it for Settings.
    var setKeyboardSize: ((KeyboardSize) -> Void)?
    /// Opens a `pesto://` link in the host app (only works when Full Access is granted).
    var openURL: ((URL) -> Void)?
}
