// SPDX-License-Identifier: MIT
import XCTest

/// Three messages that differ only in a name and an order number, copied over three days: pasting one from the shelf
/// makes the shelf offer one snippet with a fill-in for what changes (ADR 0017), and accepting it opens the editor with
/// the shared text and the fields already in place.
final class SnippetFamilySuggestionUITests: PestoUITestCase {
    private let dwell: TimeInterval = 1.5

    private var banner: XCUIElement {
        element(AccessibilityID.shelfSuggestionBanner)
    }

    private func launchSuggesting() {
        let armedFourDaysAgo = Int(Date.now.addingTimeInterval(-4 * 86_400).timeIntervalSince1970)
        launch(
            seed: "suggestion",
            defaults: ["hasOnboarded": "true", "shelfSuggestionsArmedAt": String(armedFourDaysAgo)],
            suggestionsLive: true
        )
    }

    private func pasteALookalikeThenReopen() {
        showOverlay()
        card(containing: "Hi Bruno").doubleClick()
        waitForNonExistence(overlay, timeout: 10, "the paste should close the shelf")
        showOverlay()
        XCTAssertTrue(banner.waitForExistence(timeout: dwell + 8), "no suggestion banner after the dwell")
    }

    func test_whenAMessageOfALookalikeFamilyIsPasted_thenTheShelfOffersOneSnippet() {
        launchSuggesting()

        pasteALookalikeThenReopen()

        XCTAssertTrue(
            banner.label.contains("look alike"),
            "the banner should say the clips look alike: \(banner.label)"
        )
        XCTAssertFalse(banner.label.contains("Anna"), "a banner never quotes a clip")
        capture("snippet-family-suggestion-banner")
    }

    func test_whenTheSnippetOfferIsAccepted_thenTheEditorOpensWithTheTemplateAndItsFields() {
        launchSuggesting()
        pasteALookalikeThenReopen()

        element(AccessibilityID.shelfSuggestionAcceptButton).click()

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings should open on the snippets")
        let editor = element(AccessibilityID.snippetTextEditor)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor did not open")
        let text = (editor.value as? String) ?? ""
        XCTAssertTrue(text.contains("{{input:Name}}"), "the template should ask for the name: \(text)")
        XCTAssertTrue(text.contains("{{input:Number}}"), "the template should ask for the number: \(text)")
        XCTAssertTrue(text.contains("has shipped and should arrive on Friday"), "the shared words stay: \(text)")
        XCTAssertTrue(
            element(AccessibilityID.snippetQuestionName).waitForExistence(timeout: 5),
            "the questions should each have a row"
        )
        capture("snippet-family-editor", of: settingsWindow)
        let preview = element(AccessibilityID.snippetPreview)
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "the editor shows no preview")
        let shown = (preview.value as? String) ?? preview.label
        XCTAssertTrue(shown.contains("Number"), "the preview should show the Number field: \(shown)")
    }

    func test_whenTheSnippetOfferIsDeclined_thenItGoesAndStaysAwayForTheFamily() {
        launchSuggesting()
        pasteALookalikeThenReopen()

        element(AccessibilityID.shelfSuggestionDeclineButton).click()

        waitForNonExistence(banner, timeout: 5, "No Thanks should remove the banner")
    }
}
