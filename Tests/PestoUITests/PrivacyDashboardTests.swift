// SPDX-License-Identifier: MIT
import XCTest

final class PrivacyDashboardTests: PestoUITestCase {
    private func openPrivacy(
        pane: String = "Privacy", defaults: [String: String] = ["hasOnboarded": "true"]
    ) {
        launch(defaults: defaults)
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar(pane)).click()
    }

    private func fact(_ name: String) -> String {
        let item = element(AccessibilityID.privacyFact(name))
        return (item.value as? String) ?? item.label
    }

    func test_privacyOpensWithThePromise_andItsLines() {
        openPrivacy()
        XCTAssertTrue(element(AccessibilityID.privacyFact("net-clips")).waitForExistence(timeout: 10), "no promise")
        for line in ["key", "net-ai", "net-updates", "net-backup"] {
            XCTAssertFalse(fact(line).isEmpty, "the promise has no \(line) line")
        }
        capture("settings-privacy", of: settingsWindow)
    }

    func test_clearEverything_cancelKeepsHistory() {
        openPrivacy(pane: "Data")
        element(AccessibilityID.clearEverythingButton).click()
        XCTAssertTrue(app.sheets.buttons["Cancel"].waitForExistence(timeout: 5) || app.dialogs.buttons["Cancel"]
            .waitForExistence(timeout: 2))
        (app.sheets.buttons["Cancel"].exists ? app.sheets.buttons["Cancel"] : app.dialogs.buttons["Cancel"]).click()

        send(.showOverlay)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "cancelling must keep the history")
    }

    func test_clearEverything_confirmedWithAuthenticationEmptiesTheHistory() {
        openPrivacy(pane: "Data", defaults: ["hasOnboarded": "true", "uitestAuthenticationGranted": "true"])
        element(AccessibilityID.clearEverythingButton).click()
        let confirm = app.sheets.buttons["Clear Everything"].exists ? app.sheets.buttons["Clear Everything"] : app
            .dialogs.buttons["Clear Everything"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        send(.showOverlay)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(cards.count, 0, "the history should be empty")
    }
}

final class PrivacyWordingTests: PestoUITestCase {
    func test_thePromise_saysPlainlyWhatLeavesThisMac() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()

        func line(_ id: String) -> String {
            let item = element(AccessibilityID.privacyFact(id))
            _ = item.waitForExistence(timeout: 5)
            return (item.value as? String) ?? item.label
        }
        XCTAssertTrue(line("net-updates").contains(PrivacyNetworkFacts.updates), line("net-updates"))
        XCTAssertTrue(line("net-clips").contains(PrivacyNetworkFacts.clips), line("net-clips"))
        XCTAssertTrue(line("net-ai").contains("Run on this Mac only"), line("net-ai"))
    }
}
