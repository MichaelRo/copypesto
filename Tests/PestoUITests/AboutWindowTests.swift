// SPDX-License-Identifier: MIT
import XCTest

final class AboutWindowTests: PestoUITestCase {
    func test_aboutWindow_showsTheNameVersionAndLinks_andClosesCleanly() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openAbout)

        let window = app.windows.matching(identifier: AccessibilityID.aboutWindow).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "About did not open")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("about", of: window)
        XCTAssertTrue(window.staticTexts["Pesto"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Everything you copy. Readable only by you."].exists)
        let version = window.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Version", "Version")
        ).firstMatch
        XCTAssertTrue(version.exists, "no version line")
        XCTAssertTrue(window.descendants(matching: .any)["Website"].exists, "no Website link")

        window.buttons[XCUIIdentifierCloseWindow].click()
        waitForNonExistence(window, timeout: 5, "About did not close")
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground, "the app died on close")

        send(.openAbout)
        XCTAssertTrue(window.waitForExistence(timeout: 10), "About did not reopen")
    }

    /// There was no way to see the welcome screen again short of resetting the app's state.
    func test_aboutWindow_canShowTheWelcomeScreenAgain() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openAbout)
        let window = app.windows.matching(identifier: AccessibilityID.aboutWindow).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        element(AccessibilityID.showWelcomeButton).click()

        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10), "the welcome screen did not open")
    }
}
