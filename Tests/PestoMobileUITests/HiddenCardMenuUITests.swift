// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// A long press draws the card again as the menu's preview, outside the grid. A hidden card's cover reads the app
/// state, and the preview once had none: the long press on a secret ended the app.
@MainActor
final class HiddenCardMenuUITests: MobileUITestCase {
    func test_whenAHiddenCardIsLongPressed_thenItsMenuOpensAndPestoKeepsRunning() {
        let app = launch()

        let secret = card(containing: "ghp_", in: app)
        XCTAssertTrue(secret.waitForExistence(timeout: timeout), "the seeded secret is on a card")
        pressForContextMenu(secret, in: app)

        XCTAssertTrue(app.buttons["Edit Details"].waitForExistence(timeout: 10), "the card's menu opened")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
