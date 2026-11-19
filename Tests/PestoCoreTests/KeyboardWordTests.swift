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

    @Test("the length to delete counts what the caret moves over, so an accent or emoji counts once")
    func whenReplaced_thenEachCharacterIsOneDelete() {
        #expect(KeyboardWord.deletions(for: "café") == 4)
        #expect(KeyboardWord.deletions(for: "hi👋🏽") == 3)
    }
}
