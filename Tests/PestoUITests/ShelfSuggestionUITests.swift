// SPDX-License-Identifier: MIT
import XCTest

/// A clip pasted six times, a shelf armed four days ago, Accessibility granted: the shelf offers ⌃1 for it (ADR 0014),
/// and a decline keeps the offer away until the person has pasted the clip twice as often again (ADR 0015).
final class ShelfSuggestionUITests: PestoUITestCase {
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

    private func closeShelf() {
        send(.hideOverlay)
        waitForNonExistence(overlay, timeout: 10, "the shelf did not close")
    }

    func test_whenTheShelfOpensForAFrequentClip_thenTheShortcutOfferShowsAndNoThanksKeepsItAway() {
        launchSuggesting()

        // An offer needs a paste from the shelf in this run on top of the stored count.
        showOverlay()
        card(containing: "Quarterly report draft").doubleClick()
        waitForNonExistence(overlay, timeout: 10, "the paste should close the shelf")

        showOverlay()
        XCTAssertTrue(banner.waitForExistence(timeout: dwell + 8), "no suggestion banner after the dwell")
        XCTAssertTrue(banner.label.contains("⌃1"), "the banner should offer ⌃1, said: \(banner.label)")
        let suggestedCard = cards.matching(NSPredicate(format: "value CONTAINS 'suggested shortcut Control 1'"))
            .firstMatch
        XCTAssertTrue(suggestedCard.exists, "the clip the offer is about should carry the ring and the ghost keycap")
        capture("suggestion-banner-with-ring-and-ghost-keycap")

        element(AccessibilityID.shelfSuggestionDeclineButton).click()
        waitForNonExistence(banner, timeout: 5, "No Thanks should remove the banner")
        XCTAssertFalse(suggestedCard.exists, "the ring and ghost keycap should go with the banner")
        capture("suggestion-declined")

        // The 24-hour pause after a banner also keeps it away here; "twice the pastes" is covered by the policy tests.
        closeShelf()
        showOverlay()
        let returned = banner.waitForExistence(timeout: dwell + 4)
        capture("suggestion-after-reopen")
        XCTAssertFalse(returned, "a declined offer comes back only after the clip is pasted twice as often (ADR 0015)")
    }
}
