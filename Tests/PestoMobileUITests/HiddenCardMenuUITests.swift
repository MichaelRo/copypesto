// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// A long press draws the card again as the menu's preview, outside the grid. A hidden card's cover reads the app
/// state, and the preview once had none: the long press on a secret ended the app.
@MainActor
final class HiddenCardMenuUITests: XCTestCase {
    func test_whenAHiddenCardIsLongPressed_thenItsMenuOpensAndPestoKeepsRunning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        app.launch()

        let secret = app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
            .matching(NSPredicate(format: "label CONTAINS %@", "ghp_")).firstMatch
        XCTAssertTrue(secret.waitForExistence(timeout: 15), "the seeded secret is on a card")
        secret.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Edit Details"].waitForExistence(timeout: 10), "the card's menu opened")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
