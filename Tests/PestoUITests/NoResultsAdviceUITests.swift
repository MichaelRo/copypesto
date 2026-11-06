// SPDX-License-Identifier: MIT
import XCTest

final class NoResultsAdviceUITests: PestoUITestCase {
    func test_noResultsWithAKindOn_offersClearFilters() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let imageChip = element(AccessibilityID.filterChip("Image"))
        XCTAssertTrue(imageChip.waitForExistence(timeout: 5))
        imageChip.click()
        field.click()
        field.typeText("Quarterly")

        let advice = element(AccessibilityID.shelfEmptyStateAdvice)
        XCTAssertTrue(
            advice.waitForExistence(timeout: 5),
            "no Clear Filters button on an empty search with a filter on"
        )
        advice.click()

        XCTAssertTrue(card(containing: "Quarterly report draft").waitForExistence(timeout: 5))
    }
}
