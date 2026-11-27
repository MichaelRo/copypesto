// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing

/// After a clip is inserted and the keyboard stays, the word before the caret is the clip's last word; searching by
/// it would swap the row for its matches and throw the person back to the first card.
@Suite("The word an insert leaves does not search")
@MainActor
struct KeyboardModelWordTests {
    @Test("the word left by an insert is taken off; the next word the person types searches again")
    func whenInsertLeavesAWord_thenItIsDismissed() {
        let model = KeyboardModel()
        model.noteInsert("basil and parmesan")
        model.adopt(word: "parmesan", contextBefore: "Get basil and parmesan")
        #expect(model.word == "parmesan")
        #expect(model.dismissedWord == "parmesan")

        model.adopt(word: "bas", contextBefore: "Get basil and parmesan bas")
        #expect(model.word == "bas")
        #expect(model.dismissedWord == "parmesan")
    }

    @Test("a change reported before the insert lands does not use up the insert")
    func whenProxyIsStale_thenTheInsertsWordIsStillDismissed() {
        let model = KeyboardModel()
        model.adopt(word: "Get", contextBefore: "Get")
        model.noteInsert(" basil and parmesan")
        model.adopt(word: "Get", contextBefore: "Get")
        #expect(model.dismissedWord == nil)
        model.adopt(word: "parmesan", contextBefore: "Get basil and parmesan")
        #expect(model.dismissedWord == "parmesan")
    }

    @Test("without an insert, a word is adopted as typed and nothing is dismissed")
    func whenTyped_thenWordSearches() {
        let model = KeyboardModel()
        model.adopt(word: "bas", contextBefore: "bas")
        #expect(model.word == "bas")
        #expect(model.dismissedWord == nil)
    }

    @Test("an insert that leaves no word (a new line) does not dismiss the next word typed")
    func whenInsertLeavesNoWord_thenNextWordSearches() {
        let model = KeyboardModel()
        model.noteInsert("thanks\n")
        model.adopt(word: nil, contextBefore: "thanks\n")
        model.adopt(word: "bas", contextBefore: "thanks\nbas")
        #expect(model.dismissedWord == nil)
    }

    @Test("an insert the field never shows (the caret moved) stops waiting after two changes")
    func whenFieldNeverShowsTheInsert_thenWaitingEnds() {
        let model = KeyboardModel()
        model.noteInsert("parmesan")
        model.adopt(word: "x", contextBefore: "x")
        model.adopt(word: "xy", contextBefore: "xy")
        model.adopt(word: "parmesan", contextBefore: "parmesan")
        #expect(model.dismissedWord == nil)
    }

    @Test("an insert forgotten when the keyboard goes away never dismisses a later word")
    func whenForgotten_thenNothingIsDismissed() {
        let model = KeyboardModel()
        model.noteInsert("parmesan")
        model.forgetInsert()
        model.adopt(word: "parmesan", contextBefore: "parmesan")
        #expect(model.dismissedWord == nil)
    }

    @Test("selected text sets wordIsSelection cleanly without triggering false insert dismissal")
    func whenSelectionQueryAdopted_thenWordIsSelectionTracked() {
        let model = KeyboardModel()
        model.noteInsert("hello world")
        model.adopt(query: KeyboardWord.Query(text: "hello world", isSelection: true), contextBefore: "hello world")
        #expect(model.word == "hello world")
        #expect(model.wordIsSelection)
        #expect(model.dismissedWord == nil)

        model.adopt(query: KeyboardWord.Query(text: "bas", isSelection: false), contextBefore: "bas")
        #expect(model.word == "bas")
        #expect(!model.wordIsSelection)
    }
}
