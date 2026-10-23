// SPDX-License-Identifier: MIT
import XCTest

/// The import sheet for every source. A file panel cannot be driven, so these launches name a fixture library
/// (`PESTO_UITEST_IMPORT_FIXTURE`) that the menu items show instead.
final class ImportPreviewUITests: PestoUITestCase {
    private func openImport(_ item: String, fixture: String) {
        launch(importFixture: fixture)
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()
        let menu = element(AccessibilityID.importFromAppMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no import menu in Data")
        menu.click()
        let entry = element(item)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "the menu does not offer \(item)")
        entry.click()
    }

    func test_maccy_showsItsPinsAndAnOptionalHistory_andWarnsAboutWhatRetentionRemoves() {
        openImport(AccessibilityID.importMaccyButton, fixture: "maccy")

        XCTAssertTrue(element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 10), "no preview sheet")
        let history = element(AccessibilityID.importPreviewHistoryToggle)
        XCTAssertTrue(history.exists, "Maccy has pins, so history is a choice")
        XCTAssertFalse(element(AccessibilityID.importPreviewExpiring).exists, "no history yet, so nothing expires")
        XCTAssertTrue(element(AccessibilityID.importPasteConfirm).isEnabled, "the pins can be imported")
        capture("import-preview-maccy", of: settingsWindow)

        history.click()
        XCTAssertTrue(
            element(AccessibilityID.importPreviewExpiring).waitForExistence(timeout: 5),
            "with history in, the clip older than the retention setting should be called out"
        )
        element(AccessibilityID.importPreviewCancel).click()
        XCTAssertFalse(
            element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 2),
            "Cancel left the sheet"
        )
    }

    func test_alfred_hasNoPins_soHistoryIsTheImportAndThereIsNoToggle() {
        openImport(AccessibilityID.importAlfredButton, fixture: "alfred")

        XCTAssertTrue(element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 10), "no preview sheet")
        XCTAssertFalse(
            element(AccessibilityID.importPreviewHistoryToggle).exists,
            "Alfred has no pins to choose between"
        )
        XCTAssertTrue(
            element(AccessibilityID.importPreviewExpiring).exists,
            "its old clip should be called out at once"
        )
        XCTAssertTrue(element(AccessibilityID.importPasteConfirm).isEnabled)
        capture("import-preview-alfred", of: settingsWindow)
        element(AccessibilityID.importPreviewCancel).click()
    }

    func test_paste_keepsItsPinboardsAndHistoryChoice() {
        openImport(AccessibilityID.importPasteButton, fixture: "paste")

        XCTAssertTrue(element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 10), "no preview sheet")
        XCTAssertTrue(element(AccessibilityID.importPreviewHistoryToggle).exists)
        element(AccessibilityID.importPreviewCancel).click()
    }
}
