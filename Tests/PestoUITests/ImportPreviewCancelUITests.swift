// SPDX-License-Identifier: MIT
import XCTest

final class ImportPreviewCancelUITests: PestoUITestCase {
    private func pasteTempDirectories() -> [URL] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix("pesto-paste-") }
    }

    func test_whenPasteImportPreviewIsCancelled_thenNoPasteTempDirectoriesRemain() {
        let before = Set(pasteTempDirectories().map(\.lastPathComponent))

        launch(importFixture: "paste")
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()

        let menu = element(AccessibilityID.importFromAppMenu)
        XCTAssertTrue(menu.waitUntilExists(timeout: 10), "no import menu in Data")
        menu.click()

        let pasteItem = element(AccessibilityID.importPasteButton)
        XCTAssertTrue(pasteItem.waitUntilExists(timeout: 5))
        pasteItem.click()

        XCTAssertTrue(element(AccessibilityID.importPreviewSheet).waitUntilExists(timeout: 10), "no preview sheet")
        element(AccessibilityID.importPreviewCancel).click()
        waitForNonExistence(element(AccessibilityID.importPreviewSheet), timeout: 5, "Cancel did not close sheet")

        let remaining = pasteTempDirectories().filter { !before.contains($0.lastPathComponent) }
        XCTAssertTrue(remaining.isEmpty, "leftover pesto-paste-* dirs in TMPDIR: \(remaining.map(\.lastPathComponent))")
    }
}
