// SPDX-License-Identifier: MIT
import XCTest

/// The lost-key alert and its restore window (`PESTO_UITEST_KEYLOSS`): the real flow needs a missing Keychain key and a
/// file
/// panel, so a UI launch shows the alert once launch is over and finds a fixture backup (passphrase "fixture
/// passphrase", one
/// clip). The empty seed makes the restored history exactly that clip.
final class KeyLossRecoveryUITests: PestoUITestCase {
    private let passphrase = "fixture passphrase"
    private var restoreFromBackup: XCUIElement {
        app.buttons["Restore from Backup\u{2026}"]
    }

    private func openRestoreWindow() {
        XCTAssertTrue(restoreFromBackup.waitForExistence(timeout: 30), "the lost-key alert did not appear")
        restoreFromBackup.click()
        XCTAssertTrue(app.buttons["Choose Backup\u{2026}"].waitForExistence(timeout: 10), "no restore window")
        app.buttons["Choose Backup\u{2026}"].click()
    }

    private func open(with secret: String) {
        let field = app.secureTextFields["Passphrase"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(secret)
        app.buttons["Open"].click()
    }

    func test_aWrongPassphrase_changesNothing_andCloseBringsTheAlertBack() {
        launch(seed: "empty", keyLoss: true)
        openRestoreWindow()

        open(with: "not the passphrase")

        if !app.buttons["Back"].waitForExistence(timeout: 10) { dumpState("after-open") }
        XCTAssertTrue(app.buttons["Back"].exists, "a wrong passphrase showed no error")
        app.buttons["Close"].click()
        XCTAssertTrue(restoreFromBackup.waitForExistence(timeout: 10), "the alert did not come back")
    }

    func test_cancellingAtThePreview_changesNothing_andTheAlertComesBack() {
        launch(seed: "empty", keyLoss: true)
        openRestoreWindow()

        open(with: passphrase)

        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 20), "the preview did not open")
        // The sheet's texts reach XCUITest as `value`, not `label`.
        let warning = app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'Restoring replaces it with this backup' OR label CONTAINS 'Restoring replaces it'"
        )).firstMatch
        XCTAssertTrue(
            warning.waitForExistence(timeout: 10),
            "the preview should say that restoring replaces the current history"
        )
        XCTAssertTrue(
            "\(warning.value ?? "")".contains("Your current history cannot be opened on this Mac"),
            "the preview says: \(warning.value ?? warning.label)"
        )
        app.buttons["Cancel"].click()
        XCTAssertTrue(restoreFromBackup.waitForExistence(timeout: 10), "the alert did not come back")
    }

    func test_restoring_replacesTheHistoryWithTheBackup_andLaunchContinues() {
        launch(seed: "empty", keyLoss: true)
        openRestoreWindow()
        open(with: passphrase)
        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 10))

        app.buttons["Restore"].click()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20), "the restore did not finish")
        app.buttons["Done"].click()
        waitUntilReady(timeout: 60)
        showOverlay()
        XCTAssertEqual(cards.count, 1, "the history should be the backup's one clip")
        XCTAssertTrue(card(containing: "Restored from the fixture backup").exists)
    }
}
