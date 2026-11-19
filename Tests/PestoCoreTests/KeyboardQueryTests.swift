// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the person types into the keyboard's own search field")
struct KeyboardQueryTests {
    @Test("letters are added and removed one at a time, and Clear empties it")
    func whenTyped_thenTheQueryFollows() {
        var query = KeyboardQuery()
        query.type("b")
        query.type("a")
        query.type("s")
        #expect(query.text == "bas")
        query.deleteBackward()
        #expect(query.text == "ba")
        query.clear()
        #expect(query.text.isEmpty)
        query.deleteBackward()
        #expect(query.text.isEmpty)
    }

    @Test("it searches only once it holds a letter or digit, and never grows past its limit")
    func whenLongOrBlank_thenItIsBounded() {
        var query = KeyboardQuery()
        query.type(" ")
        #expect(query.search == nil)
        query.type("1z")
        #expect(query.search == "1z")
        for _ in 0..<100 {
            query.type("x")
        }
        #expect(query.text.count == KeyboardQuery.maxLength)
    }

    @Test("a word typed in the field before switching starts the search")
    func whenAWordWasTyped_thenTheQueryStartsWithIt() {
        #expect(KeyboardQuery(starting: "addr").text == "addr")
        #expect(KeyboardQuery(starting: nil).text.isEmpty)
    }
}
