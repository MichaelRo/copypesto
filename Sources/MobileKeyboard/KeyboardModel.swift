// SPDX-License-Identifier: MIT
import CoreGraphics
import Observation
import PestoCore

/// What the keyboard's view draws: the menu, the word before the caret it searches with (ADR 0062), the search page's
/// own query (ADR 0063) and whether iOS wants the keyboard's own switch key.
@MainActor
@Observable
final class KeyboardModel {
    var menu = KeyboardMenu(hasFullAccess: false) { nil }
    var keyboardSize: KeyboardSize = .medium
    var showsGlobeKey = true
    var word: String?
    /// A word the person took off with its chip, or one already replaced, so it does not search again.
    var dismissedWord: String?
    /// The search page's query while it is open, nil when it is closed. Its letter keys change only this: the model
    /// has no way to reach the app's text field.
    private(set) var searchQuery: KeyboardQuery?
    @ObservationIgnored private var pendingInsert: PendingInsert?

    /// An insert that stayed, until the field shows it: iOS may report the change before the text has landed.
    private struct PendingInsert {
        let tail: String
        var changesLeft = 2
    }

    var isSearching: Bool {
        searchQuery != nil
    }

    /// A clip was inserted and the keyboard stayed: the word that insert leaves before the caret is the clip's own last
    /// word, not one the person typed, so it must not search.
    func noteInsert(_ text: String) {
        pendingInsert = PendingInsert(tail: String(text.suffix(32)))
    }

    /// The word before the caret after the field changed. Once the text before the caret ends with what was inserted,
    /// that word is the insert's and is taken off; a field that never shows it (the caret moved) stops waiting after
    /// two changes.
    func adopt(word newWord: String?, contextBefore: String?) {
        if var pending = pendingInsert {
            if contextBefore?.hasSuffix(pending.tail) == true {
                if let newWord { dismissedWord = newWord }
                pendingInsert = nil
            } else {
                pending.changesLeft -= 1
                pendingInsert = pending.changesLeft > 0 ? pending : nil
            }
        }
        if word != newWord { word = newWord }
    }

    func forgetInsert() {
        pendingInsert = nil
    }

    func openSearch() {
        searchQuery = KeyboardQuery()
    }

    func closeSearch() {
        searchQuery = nil
    }

    func typeInSearch(_ characters: String, composingHangul: Bool = false) {
        searchQuery?.type(characters, composingHangul: composingHangul)
    }

    func deleteInSearch(decomposingHangul: Bool = false) {
        searchQuery?.deleteBackward(decomposingHangul: decomposingHangul)
    }

    func clearSearch() {
        searchQuery?.clear()
    }
}
