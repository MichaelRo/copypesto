// SPDX-License-Identifier: MIT
import XCTest

/// ADRs 0071 and 0075: the Clip window saves a title, note and tags as they are changed, and Make Snippet turns the
/// clip into a snippet in place.
final class ClipWindowUITests: PestoUITestCase {
    private var clipWindow: XCUIElement {
        app.windows.matching(identifier: AccessibilityID.textEditWindow).firstMatch
    }

    private func field(_ identifier: String) -> XCUIElement {
        clipWindow.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ identifier: String) -> XCUIElement {
        clipWindow.buttons.matching(identifier: identifier).firstMatch
    }

    private func focusCard(containing text: String) -> XCUIElement {
        let target = card(containing: text)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "the clip \(text) is not on the shelf")
        target.click()
        return target
    }

    private func openWindowFromMenu(containing text: String) {
        let target = focusCard(containing: text)
        target.rightClick()
        let item = app.menuItems["Show Details\u{2026}"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the card's menu has no Show Details")
        item.click()
        XCTAssertTrue(clipWindow.waitForExistence(timeout: 10), "the Clip window did not open")
    }

    private func closeWindow() {
        button(AccessibilityID.textEditCancelButton).click()
        waitForNonExistence(clipWindow, timeout: 5, "Close should close the Clip window")
    }

    private func type(_ text: String, into identifier: String) {
        let target = field(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no \(identifier) in the Clip window")
        target.click()
        target.typeText(text)
    }

    func test_whenATitleIsTypedAndFocusMovesAway_thenTheCardShowsItAfterClosing() {
        let text = "Window title clip"
        launch()
        copyToClipboard(text)
        showOverlay()
        _ = focusCard(containing: text)
        overlay.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(clipWindow.waitForExistence(timeout: 10), "⌘I did not open the Clip window")

        type("Gate code", into: AccessibilityID.clipInspectorTitle)
        field(AccessibilityID.clipInspectorNote).click()
        closeWindow()

        showOverlay()
        let titled = cards.matching(NSPredicate(format: "label CONTAINS %@ AND value CONTAINS %@", text, "Gate code"))
        XCTAssertTrue(titled.firstMatch.waitForExistence(timeout: 10), "the card does not show the typed title")
    }

    func test_whenANoteAndATagAreAdded_thenReopeningTheWindowShowsThem() {
        let text = "Window note clip"
        launch()
        copyToClipboard(text)
        showOverlay()
        openWindowFromMenu(containing: text)

        type("Ask Dana first", into: AccessibilityID.clipInspectorNote)
        type("gate\r", into: AccessibilityID.clipInspectorTagField)
        closeWindow()

        showOverlay()
        openWindowFromMenu(containing: text)
        let note = field(AccessibilityID.clipInspectorNote)
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Ask Dana first", "the note was not kept")
        let tag = clipWindow.descendants(matching: .staticText).matching(
            NSPredicate(format: "label == %@ OR value == %@", "@gate", "@gate")
        ).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "the tag was not kept")
    }

    func test_whenMakeSnippetIsSaved_thenTheClipIsPinnedAndCommandZTakesItBack() {
        let original = "Dear team plain"
        let templated = "Dear team on {{date}}"
        launch()
        copyToClipboard(original)
        showOverlay()
        openWindowFromMenu(containing: original)

        let make = button(AccessibilityID.clipInspectorMakeSnippet)
        XCTAssertTrue(make.waitForExistence(timeout: 5), "no Make Snippet button")
        make.click()

        let snippetText = field(AccessibilityID.snippetTextEditor)
        XCTAssertTrue(snippetText.waitForExistence(timeout: 5), "the snippet editor did not appear in the window")
        XCTAssertTrue(clipWindow.exists)
        snippetText.click()
        snippetText.typeKey("a", modifierFlags: .command)
        snippetText.typeText(templated)
        capture("clip-window-snippet-editor")

        let save = button(AccessibilityID.snippetSaveButton)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)],
            timeout: 5
        )
        save.click()
        waitForNonExistence(clipWindow, timeout: 10, "Saving the snippet should close the window")

        showOverlay()
        let snippet = card(containing: templated)
        XCTAssertTrue(snippet.waitForExistence(timeout: 10), "the card does not show the snippet text")
        XCTAssertTrue(
            (snippet.label + " " + (snippet.value as? String ?? "")).contains("pinned"),
            "the snippet is not pinned: \(snippet.label) / \(String(describing: snippet.value))"
        )
        XCTAssertEqual(cardCount(containing: original), 0, "the clip became the snippet; no copy is left beside it")

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(card(containing: original).waitForExistence(timeout: 5), "⌘Z did not bring the plain text back")
        XCTAssertEqual(cardCount(containing: templated), 0, "the snippet stayed after ⌘Z")
    }

    func test_whenEscapeIsPressedInTheSnippetEditor_thenTheTextEditorReturnsAndTheWindowStays() {
        let original = "Escape snippet clip"
        launch()
        copyToClipboard(original)
        showOverlay()
        openWindowFromMenu(containing: original)

        button(AccessibilityID.clipInspectorMakeSnippet).click()
        let snippetText = field(AccessibilityID.snippetTextEditor)
        XCTAssertTrue(snippetText.waitForExistence(timeout: 5), "the snippet editor did not appear")
        snippetText.click()
        snippetText.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(field(AccessibilityID.textEditor).waitForExistence(timeout: 5), "Esc did not return to the text")
        XCTAssertTrue(clipWindow.exists, "Esc in the snippet editor closed the window")
        XCTAssertFalse(field(AccessibilityID.snippetTextEditor).exists, "the snippet editor stayed open")
    }
}
