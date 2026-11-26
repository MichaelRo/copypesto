// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// A text clip made a snippet from its menu (ADR 0075), then filled in: Return in a one-line field copies, as the Mac
/// prompt and AutoFill do (`docs/design/search-and-return.md`).
@MainActor
final class SnippetFillUITests: MobileUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
    }

    func test_whenMadeSnippetIsFilledAndReturnIsPressed_thenTheSheetCopiesAndCloses() {
        let app = launch()
        waitForSeededClips(in: app)
        let newNote = element(MobileAccessibilityID.newNoteButton, in: app)
        XCTAssertTrue(newNote.waitForExistence(timeout: timeout))
        newNote.tap()
        let note = app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.tap()
        note.typeText("Hi {Name}, your table is ready.")
        app.buttons["Save"].firstMatch.tap()

        let draft = card(containing: "your table is ready", in: app)
        XCTAssertTrue(draft.waitForExistence(timeout: timeout))
        chooseContextMenuItem("Make Snippet\u{2026}", on: draft, in: app)
        XCTAssertTrue(element(MobileAccessibilityID.snippetEditor, in: app).waitForExistence(timeout: timeout))
        element(MobileAccessibilityID.snippetSaveButton, in: app).tap()

        let snippet = card(containing: "{{input:Name}}", in: app)
        XCTAssertTrue(snippet.waitForExistence(timeout: timeout), "the clip itself became the snippet")
        XCTAssertFalse(
            card(containing: "Hi {Name}", in: app).exists, "no copy of the old text is left beside the snippet"
        )
        snippet.tap()
        let sheet = element(MobileAccessibilityID.snippetFillSheet, in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: timeout))
        let field = app.textFields["Name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("Ana\n")

        XCTAssertTrue(sheet.waitForNonExistence(timeout: timeout), "Return in a one-line field copies and closes")
    }
}
