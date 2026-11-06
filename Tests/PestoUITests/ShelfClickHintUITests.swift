// SPDX-License-Identifier: MIT
import XCTest

final class ShelfClickHintUITests: PestoUITestCase {
    func test_aSingleClick_showsTheDoubleClickHint() {
        launch()
        showOverlay()

        cards.firstMatch.click()

        XCTAssertTrue(
            element(AccessibilityID.clickHint).waitForExistence(timeout: 5),
            "a click that only selects did not say that a double-click pastes"
        )
    }
}
