// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The keyboard's place in the filter bar")
struct FilterChipCursorTests {
    @Test("Tab from the search field goes to the first chip, and Shift-Tab to the last")
    func whenLeavingTheField_thenTheFirstOrLastChip() {
        #expect(FilterChipCursor.moved(from: nil, by: 1, count: 5) == 0)
        #expect(FilterChipCursor.moved(from: nil, by: -1, count: 5) == 4)
    }

    @Test("Tab steps along the chips, and past the last one hands the keyboard back to the field")
    func whenStepping_thenAlongThenBackToTheField() {
        #expect(FilterChipCursor.moved(from: 1, by: 1, count: 5) == 2)
        #expect(FilterChipCursor.moved(from: 4, by: 1, count: 5) == nil)
        #expect(FilterChipCursor.moved(from: 0, by: -1, count: 5) == nil)
        #expect(FilterChipCursor.moved(from: 3, by: -1, count: 5) == 2)
    }

    @Test("with no chips there is nowhere to go")
    func whenNoChips_thenNil() {
        #expect(FilterChipCursor.moved(from: nil, by: 1, count: 0) == nil)
        #expect(FilterChipCursor.moved(from: 2, by: 1, count: 0) == nil)
    }

    @Test("a cursor past the end after the chips changed is dropped, and one still inside is kept")
    func whenChipsShrink_thenTheCursorFollows() {
        #expect(FilterChipCursor.kept(6, count: 5) == nil)
        #expect(FilterChipCursor.kept(4, count: 5) == 4)
        #expect(FilterChipCursor.kept(nil, count: 5) == nil)
    }
}
