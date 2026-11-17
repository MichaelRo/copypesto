// SPDX-License-Identifier: MIT
import XCTest

final class LostKeyAXTreeUITests: PestoUITestCase {
    func test_whenKeyLossAlertAndPreviewOpen_thenWarningAndRestoreCancelButtonsAreReachableInAXTree() {
        launch(seed: "empty", keyLoss: true)

        let restoreFromBackup = app.buttons["Restore from Backup\u{2026}"]
        XCTAssertTrue(restoreFromBackup.waitUntilExists(timeout: 30), "lost-key alert did not appear")
        XCTAssertTrue(restoreFromBackup.isHittable, "Restore from Backup button should be reachable in AX tree")

        let alertText = app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'can’t unlock' OR label CONTAINS 'can’t unlock' "
                + "OR value CONTAINS 'Keychain' OR label CONTAINS 'Keychain'"
        )).firstMatch
        XCTAssertTrue(alertText.exists, "lost-key alert warning text missing from AX tree")

        clickIgnoringInterruptions(restoreFromBackup)

        let chooseBackup = app.buttons["Choose Backup\u{2026}"]
        XCTAssertTrue(chooseBackup.waitUntilExists(timeout: 10), "Choose Backup button missing")
        chooseBackup.click()

        let passphraseField = app.secureTextFields["Passphrase"]
        XCTAssertTrue(passphraseField.waitUntilExists(timeout: 5), "Passphrase field missing")
        passphraseField.click()
        passphraseField.typeText("fixture passphrase")
        app.buttons["Open"].click()

        let restoreButton = app.buttons["Restore"]
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(restoreButton.waitUntilExists(timeout: 20), "Restore button not reachable in AX tree")
        XCTAssertTrue(cancelButton.exists, "Cancel button not reachable in AX tree")
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(cancelButton.isEnabled)

        let warning = app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'Restoring replaces it with this backup' OR label CONTAINS 'Restoring replaces it'"
        )).firstMatch
        XCTAssertTrue(warning.exists, "preview warning text missing from AX tree")

        cancelButton.click()
        XCTAssertTrue(restoreFromBackup.waitUntilExists(timeout: 10), "Cancel should return to lost-key alert")
    }
}
