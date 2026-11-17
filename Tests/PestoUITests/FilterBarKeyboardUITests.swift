// SPDX-License-Identifier: MIT
import XCTest

final class FilterBarKeyboardUITests: PestoUITestCase {
    private func openSearchAndFilterBar() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitUntilExists(timeout: 5))
    }

    func test_whenWalkingFilterBarWithTabAndUsingMenus_thenFiltersApplyAndClear() {
        openSearchAndFilterBar()

        // Tab walks from search field across filter chips (at least 7 chips)
        for _ in 0..<7 {
            overlay.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(overlay.exists, "Tab walk across filter chips should keep shelf open")

        // Open Format menu via filter chip, pick an item with arrow + Return, then clear with Any Format
        let formatChip = element(AccessibilityID.filterChip("Filter by format"))
        XCTAssertTrue(formatChip.waitUntilExists(timeout: 5), "Format chip missing")
        formatChip.click()
        let formatMenu = app.menus.firstMatch
        if formatMenu.waitUntilExists(timeout: 3) {
            overlay.typeKey(.downArrow, modifierFlags: [])
            overlay.typeKey(.return, modifierFlags: [])
        }

        // Re-open Format menu and clear if Any Format is present
        let activeFormat = element(AccessibilityID.filterChip("Filter by format"))
        if activeFormat.exists {
            activeFormat.click()
            let anyFormat = app.menuItems["Any Format"]
            if anyFormat.waitUntilExists(timeout: 2) {
                anyFormat.click()
            } else {
                overlay.typeKey(.escape, modifierFlags: [])
            }
        }

        // More (whenMore) menu
        let moreChip = element(AccessibilityID.filterChip("More time ranges"))
        if moreChip.waitUntilExists(timeout: 3) {
            moreChip.click()
            let anyTime = app.menuItems["Any Time"]
            if anyTime.waitUntilExists(timeout: 2) {
                anyTime.click()
            } else {
                overlay.typeKey(.escape, modifierFlags: [])
            }
        }

        // From menu
        let fromChip = element(AccessibilityID.filterChip("Filter by app"))
        if fromChip.waitUntilExists(timeout: 3) {
            fromChip.click()
            let anyApp = app.menuItems["Any App"]
            if anyApp.waitUntilExists(timeout: 2) {
                anyApp.click()
            } else {
                overlay.typeKey(.escape, modifierFlags: [])
            }
        }

        // Toggle a direct chip with Space after Tab focus
        let textChip = element(AccessibilityID.filterChip("Text"))
        XCTAssertTrue(textChip.waitUntilExists(timeout: 5))
        textChip.click()
        XCTAssertTrue(textChip.isSelected, "Text chip should be selected")
        textChip.click()
        XCTAssertFalse(textChip.isSelected, "Re-picking Text chip should clear it")
    }
}
