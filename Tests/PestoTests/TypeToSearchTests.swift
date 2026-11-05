// SPDX-License-Identifier: MIT
import XCTest
@testable import Pesto

@MainActor
final class TypeToSearchTests: XCTestCase {
    func test_whenSeveralKeysArriveBeforeTheFieldHasFocus_thenTheyAreAllKept() {
        let state = AppState()

        state.typeIntoSearch("1")
        state.typeIntoSearch("2")
        state.typeIntoSearch("3")
        state.typeIntoSearch("4")

        XCTAssertEqual(state.searchText, "1234")
        XCTAssertTrue(state.isSearchActive)
    }

    func test_whenSearchWasClosed_thenTheNextKeyStartsANewSearch() {
        let state = AppState()
        state.typeIntoSearch("12")
        state.isSearchActive = false

        state.typeIntoSearch("3")

        XCTAssertEqual(state.searchText, "3")
        XCTAssertTrue(state.isSearchActive)
    }

    func test_whenTheFieldTookFocusWithItsTextSelected_thenTheNextKeyFindsTheCaretAtTheEnd() {
        let editor = NSTextView()
        editor.string = "12"
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        SearchFieldCaret.arm()

        SearchFieldCaret.settle(editor)

        XCTAssertEqual(editor.selectedRange, NSRange(location: 2, length: 0))
    }

    func test_whenTheCaretWasPlaced_thenASelectionThePersonMakesIsKept() {
        let editor = NSTextView()
        editor.string = "12"
        SearchFieldCaret.arm()
        SearchFieldCaret.settle(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 2))

        SearchFieldCaret.settle(editor)

        XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 2))
    }
}
