// SPDX-License-Identifier: MIT
import XCTest

final class AskPestoTests: PestoUITestCase {
    func test_askingInWords_setsTheMatchingFilters() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("images from today")

        let ask = element(AccessibilityID.askButton)
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "no Ask button for a multi-word search")
        ask.click()

        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: element(AccessibilityID.filterChip("Today")))
        expectation(for: selected, evaluatedWith: element(AccessibilityID.filterChip("Image")))
        waitForExpectations(timeout: 5)
        capture("ask-pesto")
    }

    func test_aSingleWord_offersNoAsk() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Quarterly")

        XCTAssertFalse(element(AccessibilityID.askButton).exists)
    }
}
