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
    @ObservationIgnored private var insertedSinceWord = false

    var isSearching: Bool {
        searchQuery != nil
    }

    /// A clip was inserted and the keyboard stayed: the word that insert leaves before the caret is the clip's own last
    /// word, not one the person typed, so it must not search.
    func noteInsert() {
        insertedSinceWord = true
    }

    /// The word before the caret after the field changed.
    func adopt(word newWord: String?) {
        if insertedSinceWord {
            insertedSinceWord = false
            if let newWord { dismissedWord = newWord }
        }
        if word != newWord { word = newWord }
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
