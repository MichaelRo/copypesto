// SPDX-License-Identifier: MIT
import XCTest

/// Settings → Snippets: a snippet needs a placeholder, and starters offer templates to begin with.
final class SnippetSuggestionsTests: PestoUITestCase {
    private func openSnippets() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Snippets")).click()
    }

    func test_aStarter_isAddedAsASnippet_andLeavesTheStarters() {
        openSnippets()
        let add = element(AccessibilityID.addSnippetStarter("stand-up"))
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no starter snippets")
        capture("settings-snippets-starters", of: settingsWindow)

        add.click()

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: add)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(
            settingsWindow.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Stand-up'")).firstMatch
                .waitForExistence(timeout: 5),
            "the snippet is not listed"
        )
    }

    func test_text_withNoPlaceholder_cannotBeSaved_untilOneIsInserted() {
        openSnippets()
        settingsWindow.buttons["Add Snippet"].click()
        let editor = element(AccessibilityID.snippetTextEditor)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("Best regards")

        XCTAssertTrue(element(AccessibilityID.snippetNeedsPlaceholder).waitForExistence(timeout: 5))
        XCTAssertFalse(element(AccessibilityID.snippetSaveButton).isEnabled)
        capture("settings-snippet-needs-placeholder", of: settingsWindow)

        settingsWindow.buttons["{{date}}"].click()

        XCTAssertTrue(element(AccessibilityID.snippetSaveButton).waitForExistence(timeout: 5))
        expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: element(AccessibilityID.snippetSaveButton)
        )
        waitForExpectations(timeout: 5)
    }

    /// A snippet used to be add-or-delete only: the list gives Edit, and the editor shows what will paste.
    func test_aSnippet_canBeEdited_andTheListShowsTheChange() {
        openSnippets()
        let add = element(AccessibilityID.addSnippetStarter("stand-up"))
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.click()
        let edit = element(AccessibilityID.editSnippetButton)
        XCTAssertTrue(edit.waitForExistence(timeout: 8), "a snippet in the list should offer Edit")

        edit.click()
        let text = element(AccessibilityID.snippetTextEditor)
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Edit did not open the editor")
        text.click()
        text.typeKey("a", modifierFlags: .command)
        text.typeText("Updated: {{date}} {{cursor}}done")
        let preview = element(AccessibilityID.snippetPreview)
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "the editor shows what the snippet pastes")
        capture("settings-snippet-editor", of: settingsWindow)
        element(AccessibilityID.snippetSaveButton).click()

        XCTAssertTrue(
            settingsWindow.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Updated'")).firstMatch
                .waitForExistence(timeout: 8),
            "the edited text is not listed"
        )
    }

    func test_deletingASnippet_asksFirst() {
        openSnippets()
        let add = element(AccessibilityID.addSnippetStarter("stand-up"))
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.click()
        let delete = element(AccessibilityID.deleteSnippetButton)
        XCTAssertTrue(delete.waitForExistence(timeout: 8))

        delete.click()
        XCTAssertTrue(element(AccessibilityID.deleteSnippetConfirmButton).waitForExistence(timeout: 5))
        element(AccessibilityID.deleteSnippetConfirmButton).click()

        waitForNonExistence(delete, timeout: 8, "confirming should remove the snippet")
    }
}
