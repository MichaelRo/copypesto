// SPDX-License-Identifier: MIT
import XCTest

/// Audit P-04: "Clear History → Last 5 minutes" used to delete everything OLDER than five minutes, with no
/// confirmation, from the menu, `pesto://clear` and AppleScript alike.
final class ClearHistoryTests: PestoUITestCase {
    private func chooseClear(_ identifier: String) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar item")
        statusItem.click()
        let parent = app.menuItems["Clear History"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5), "status menu has no Clear History")
        parent.click()
        let item = app.menuItems.matching(identifier: identifier).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "submenu item \(identifier) missing")
        item.click()
    }

    func test_clearLastFiveMinutes_confirmsThenDeletesOnlyTheRecentItems() {
        launch()

        chooseClear("statusClearLast5")
        let confirm = element(AccessibilityID.clearConfirmDelete)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no confirmation before deleting")
        capture("clear-confirmation", of: confirm.exists ? app.windows.firstMatch : nil)
        confirm.click()

        showOverlay()
        XCTAssertFalse(card(containing: "Quarterly report draft").exists, "the newest item should be gone")
        XCTAssertTrue(
            card(containing: "Remember to renew the domain").waitForExistence(timeout: 5),
            "older history must survive clearing the last five minutes"
        )
    }

    func test_cancellingTheConfirmation_deletesNothing() {
        launch()

        chooseClear("statusClearAll")
        let cancel = element(AccessibilityID.clearConfirmCancel)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "no confirmation before deleting")
        cancel.click()

        showOverlay()
        XCTAssertTrue(card(containing: "Quarterly report draft").exists)
        XCTAssertTrue(card(containing: "Remember to renew the domain").waitForExistence(timeout: 5))
    }
}
