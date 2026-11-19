// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The word before the cursor the keyboard searches with")
struct KeyboardWordTests {
    @Test("the last word just typed, two to thirty-two characters, is the search")
    func whenAWordWasJustTyped_thenItIsTheSearch() {
        #expect(KeyboardWord.before("Send it to addr", after: nil) == "addr")
        #expect(KeyboardWord.before("addr", after: "") == "addr")
        #expect(KeyboardWord.before("line one\nwifi", after: " and more") == "wifi")
    }

    @Test("no search after a space, for a single letter, a long run, or with the cursor inside a word")
    func whenThereIsNoFreshWord_thenThereIsNoSearch() {
        #expect(KeyboardWord.before("Send it ", after: nil) == nil)
        #expect(KeyboardWord.before("a", after: nil) == nil)
        #expect(KeyboardWord.before(String(repeating: "x", count: 33), after: nil) == nil)
        #expect(KeyboardWord.before("add", after: "ress") == nil)
        #expect(KeyboardWord.before(nil, after: nil) == nil)
    }

    @Test("the length to delete counts what the caret moves over, so an accent counts once")
    func whenReplaced_thenEachCharacterIsOneDelete() {
        #expect(KeyboardWord.deletions(replacing: "café", before: "a café", after: nil) == 4)
    }

    @Test("punctuation around the word is not part of the search, and a word ending in punctuation is not one")
    func whenPunctuated_thenOnlyTheWordCounts() {
        #expect(KeyboardWord.before("see (home", after: nil) == "home")
        #expect(KeyboardWord.before("to addr.", after: nil) == nil)
        #expect(KeyboardWord.before("שלום", after: nil) == "שלום")
        #expect(KeyboardWord.before("👋🏽👋🏽", after: nil) == nil)
    }

    @Test("the word is replaced only while the field still ends with it")
    func whenTheFieldChanged_thenNothingIsDeleted() {
        #expect(KeyboardWord.deletions(replacing: "addr", before: "Send addr", after: nil) == 4)
        #expect(KeyboardWord.deletions(replacing: "addr", before: "Send addr 12 Basil Lane", after: nil) == nil)
        #expect(KeyboardWord.deletions(replacing: "addr", before: "Send ad", after: "dr") == nil)
    }
}
