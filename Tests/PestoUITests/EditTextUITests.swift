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

    func test_escapeInTextEditor_cancelsWithoutSaving() {
        let original = "Escape keeps this text"
        openEditor(for: original)

        let editor = editWindow.descendants(matching: .any).matching(identifier: AccessibilityID.textEditor).firstMatch
        XCTAssertTrue(editor.waitUntilExists(timeout: 5), "no text view in the editor")
        editor.click()
        editor.typeText(" extra unsaved")
        editor.typeKey(.escape, modifierFlags: [])
        waitForNonExistence(editWindow, timeout: 5, "Esc in the text editor should cancel and close")

        showOverlay()
        XCTAssertTrue(card(containing: original).waitUntilExists(timeout: 10))
        XCTAssertEqual(cardCount(containing: "extra unsaved"), 0, "Esc saved the draft")
    }

    func test_editingAShownSecret_requiresShowThenSavesResealedAndReclassified() {
        launch(defaults: ["hasOnboarded": "true", "uitestAuthenticationGranted": "true"])
        showOverlay()
        let masked = card(containing: "4242")
        XCTAssertTrue(masked.waitUntilExists(timeout: 10), "no masked secret card on the shelf")

        masked.rightClick()
        XCTAssertTrue(app.menuItems["Show"].waitUntilExists(timeout: 5))
        XCTAssertFalse(app.menuItems["Edit Text\u{2026}"].exists, "masked secret must not offer Edit Text")
        app.menuItems["Show"].click()

        let shown = NSPredicate { _, _ in (masked.value as? String ?? "").contains("4242 4242 4242 4242") }
        wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 5)

        masked.rightClick()
        let editItem = app.menuItems["Edit Text\u{2026}"]
        XCTAssertTrue(editItem.waitUntilExists(timeout: 5), "shown secret should offer Edit Text")
        editItem.click()
        XCTAssertTrue(editWindow.waitUntilExists(timeout: 10), "Edit Text window did not open")

        replaceText(with: "4111 1111 1111 1111")
        editWindow.buttons.matching(identifier: AccessibilityID.textEditSaveButton).firstMatch.click()
        waitForNonExistence(editWindow, timeout: 5, "Save should close the editor")

        showOverlay()
        let updated = card(containing: "1111")
        XCTAssertTrue(updated.waitUntilExists(timeout: 10), "re-classified secret is missing")
        XCTAssertFalse((updated.value as? String ?? "").contains("4111 1111"), "edited secret stayed unmasked")
        XCTAssertEqual(cardCount(containing: "4242"), 0, "old secret remained")
    }

    func test_contentCoverWhileEditorOpen_hidesTextDisablesSaveAndPreservesDraft() {
        openEditor(for: "Clip before cover")
        replaceText(with: "Draft kept across cover")
        let save = editWindow.buttons.matching(identifier: AccessibilityID.textEditSaveButton).firstMatch
        XCTAssertTrue(save.isEnabled)

        send(.toggleHideContents)
        let covered = editWindow.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS 'Hidden while clip contents are covered' "
                    + "OR value CONTAINS 'Hidden while clip contents are covered'"
            )
        ).firstMatch
        XCTAssertTrue(covered.waitUntilExists(timeout: 5), "editor did not cover text")
        XCTAssertFalse(save.isEnabled, "Save must be disabled while covered")

        send(.toggleHideContents)
        let editor = editWindow.descendants(matching: .any).matching(identifier: AccessibilityID.textEditor).firstMatch
        XCTAssertTrue(editor.waitUntilExists(timeout: 5), "editor did not uncover")
        XCTAssertEqual(editor.value as? String, "Draft kept across cover", "draft was lost during cover")
        XCTAssertTrue(save.isEnabled)
    }

    func test_editingFromFloatingWindow_keepsFloatingWindowOpenAndUpdatesCard() {
        launch()
        copyToClipboard("Float edit original")
        send(.togglePinnedWindow)
        let pinned = element(AccessibilityID.pinnedPanel)
        XCTAssertTrue(pinned.waitUntilExists(timeout: 10), "floating window did not open")
        let target = pinned.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", AccessibilityID.card, "Float edit original")
        ).firstMatch
        XCTAssertTrue(target.waitUntilExists(timeout: 10), "copied clip missing in floating window")

        target.rightClick()
        let item = app.menuItems["Edit Text\u{2026}"]
        XCTAssertTrue(item.waitUntilExists(timeout: 5))
        item.click()
        XCTAssertTrue(editWindow.waitUntilExists(timeout: 10), "Edit Text window did not open")
        XCTAssertTrue(pinned.exists, "floating window should remain open while editing")

        replaceText(with: "Float edit saved")
        editWindow.buttons.matching(identifier: AccessibilityID.textEditSaveButton).firstMatch.click()
        waitForNonExistence(editWindow, timeout: 5)

        XCTAssertTrue(pinned.exists, "floating window closed after saving")
        let updated = pinned.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", AccessibilityID.card, "Float edit saved")
        ).firstMatch
        XCTAssertTrue(updated.waitUntilExists(timeout: 10), "floating window card did not update")
    }
}
