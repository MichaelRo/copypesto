// SPDX-License-Identifier: MIT
import XCTest

/// ADR 0050: Edit Text from the card's menu opens a window of its own after the shelf closes; Save changes the card and
/// ⌘Z on the shelf brings the old text back.
final class EditTextUITests: PestoUITestCase {
    private var editWindow: XCUIElement {
        app.windows.matching(identifier: AccessibilityID.textEditWindow).firstMatch
    }

    private func openEditor(for text: String) {
        launch()
        copyToClipboard(text)
        showOverlay()
        let target = card(containing: text)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "the copied clip is not on the shelf")
        target.rightClick()
        let item = app.menuItems["Edit Text\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the card's menu has no Edit Text")
        item.click()
        XCTAssertTrue(editWindow.waitForExistence(timeout: 10), "the Edit Text window did not open")
    }

    private func replaceText(with text: String) {
        let editor = editWindow.descendants(matching: .any).matching(identifier: AccessibilityID.textEditor).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "no text view in the editor")
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(text)
    }

    func test_editingFromTheMenu_changesTheCard_andCommandZRestoresIt() {
        let original = "Meet at the north gate"
        let edited = "Meet at the south gate"
        openEditor(for: original)
        waitForNonExistence(overlay, timeout: 5, "the shelf should close while the editor is open")

        replaceText(with: edited)
        capture("edit-text-window")
        let save = editWindow.buttons.matching(identifier: AccessibilityID.textEditSaveButton).firstMatch
        XCTAssertTrue(save.isEnabled, "Save should be ready for a changed text")
        save.click()
        waitForNonExistence(editWindow, timeout: 5, "Save should close the editor")

        showOverlay()
        XCTAssertTrue(card(containing: edited).waitForExistence(timeout: 10), "the card does not show the new text")
        XCTAssertEqual(cardCount(containing: original), 0, "the old text is still on a card")

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(card(containing: original).waitForExistence(timeout: 5), "⌘Z did not restore the old text")
        XCTAssertEqual(cardCount(containing: edited), 0, "the edited text stayed after ⌘Z")
    }

    func test_cancelLeavesTheClipAsItWas() {
        let original = "Bring the basil seedlings"
        openEditor(for: original)

        replaceText(with: "Never saved words")
        editWindow.buttons.matching(identifier: AccessibilityID.textEditCancelButton).firstMatch.click()
        waitForNonExistence(editWindow, timeout: 5, "Cancel should close the editor")

        showOverlay()
        XCTAssertTrue(card(containing: original).waitForExistence(timeout: 10))
        XCTAssertEqual(cardCount(containing: "Never saved words"), 0, "Cancel saved the draft")
    }
}
