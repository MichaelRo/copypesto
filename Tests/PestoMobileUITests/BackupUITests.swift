// SPDX-License-Identifier: MIT
import XCTest

/// Settings → Data → Backup (ADR 0078). The key store is in memory under a UI-test launch and the file waits in the
/// temporary folder; the test never opens Files, so nothing is saved anywhere real.
@MainActor
final class BackupUITests: MobileUITestCase {
    func test_whenBackingUpWithTheRecoveryKeyOnly_thenTheKeyIsShownBeforeTheFileCanBeSaved() {
        let app = launch()
        XCTAssertTrue(element(MobileAccessibilityID.clipCard, in: app).waitForExistence(timeout: timeout))
        element(MobileAccessibilityID.settingsButton, in: app).tap()
        let backup = element(MobileAccessibilityID.backupSettingsButton, in: app)
        for _ in 0..<8 where !backup.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(backup.waitForExistence(timeout: timeout))
        backup.tap()

        XCTAssertTrue(element(MobileAccessibilityID.restoreBackupButton, in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(
            element(MobileAccessibilityID.showBackupRecoveryKeyButton, in: app).exists,
            "no key exists before the first backup"
        )
        element(MobileAccessibilityID.backUpNowButton, in: app).tap()

        let start = element(MobileAccessibilityID.backupStartButton, in: app)
        XCTAssertTrue(start.waitForExistence(timeout: timeout))
        XCTAssertFalse(start.isEnabled, "a passphrase is needed first")
        app.buttons["Recovery Key Only"].firstMatch.tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()

        XCTAssertTrue(element(MobileAccessibilityID.backupRecoveryKey, in: app).waitForExistence(timeout: 30))
        let save = app.buttons["Save to Files\u{2026}"].firstMatch
        XCTAssertFalse(save.isEnabled, "the key is stored before the file can be saved")
        let stored = app.switches["I Have Stored the Recovery Key"].firstMatch
        stored.tap()
        if stored.value as? String == "0" { stored.switches.firstMatch.tap() }
        XCTAssertTrue(save.isEnabled)

        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(
            element(MobileAccessibilityID.showBackupRecoveryKeyButton, in: app).waitForExistence(timeout: timeout),
            "after a backup, the key can be shown again"
        )
    }
}
