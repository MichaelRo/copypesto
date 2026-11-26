// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// After a clip is inserted and the keyboard stays, the word before the caret is the clip's last word; searching by
/// it would swap the row for its matches and throw the person back to the first card.
@Suite("The word an insert leaves does not search")
@MainActor
struct KeyboardModelWordTests {
    @Test("the word left by an insert is taken off; the next word the person types searches again")
    func whenInsertLeavesAWord_thenItIsDismissed() {
        let model = KeyboardModel()
        model.noteInsert()
        model.adopt(word: "parmesan")
        #expect(model.word == "parmesan")
        #expect(model.dismissedWord == "parmesan")

        model.adopt(word: "bas")
        #expect(model.word == "bas")
        #expect(model.dismissedWord == "parmesan")
    }

    @Test("without an insert, a word is adopted as typed and nothing is dismissed")
    func whenTyped_thenWordSearches() {
        let model = KeyboardModel()
        model.adopt(word: "bas")
        #expect(model.word == "bas")
        #expect(model.dismissedWord == nil)
    }

    @Test("an insert that leaves no word (a space, a new line) does not dismiss the next word typed")
    func whenInsertLeavesNoWord_thenNextWordSearches() {
        let model = KeyboardModel()
        model.noteInsert()
        model.adopt(word: nil)
        model.adopt(word: "bas")
        #expect(model.dismissedWord == nil)
    }
}
