// SPDX-License-Identifier: MIT
import XCTest

/// A long text summarized one part at a time (`docs/design/ai-chunked-summary.md`). A fake model answers at once
/// (`PESTO_UITEST_AI_FIXTURE`), so the test runs on any Mac and only the panel is under test.
final class AIPartsUITests: PestoUITestCase {
    private let longText = (0..<60).map { "sentence number \($0)." }.joined(separator: " ")

    private func openKeyPoints() {
        launch(seed: "empty", aiFixture: true)
        copyToClipboard(longText)
        showOverlay()
        let target = card(containing: "sentence number 0")
        XCTAssertTrue(target.waitForExistence(timeout: 10), "the long text was not captured")
        target.rightClick()
        // "Summarize" is also a macOS Writing Tools item; "Key Points" is only Pesto's.
        app.menuItems["Key Points"].click()
    }

    func test_theFirstPartComesAtOnce_andTheNextOnesWaitForAClick() {
        openKeyPoints()
        let next = element(AccessibilityID.aiReadNextPartButton)
        XCTAssertTrue(next.waitForExistence(timeout: 15), "no Read Part 2 button after the first part")
        XCTAssertTrue(app.staticTexts["Read the next part?"].exists)

        next.click()

        XCTAssertTrue(
            element(AccessibilityID.aiReadNextPartButton).waitForExistence(timeout: 15),
            "the next part did not come in and offer the one after it"
        )
        XCTAssertTrue(
            element(AccessibilityID.aiReadNextPartButton).label.contains("part 3"),
            "the question should now offer part 3"
        )
        capture("ai-parts-after-part-two")
    }

    func test_readingEveryPart_offersCombine_andPasteStaysTheDefault() {
        openKeyPoints()
        var guardCount = 0
        while element(AccessibilityID.aiReadNextPartButton).waitForExistence(timeout: 10), guardCount < 20 {
            element(AccessibilityID.aiReadNextPartButton).click()
            guardCount += 1
        }
        XCTAssertTrue(
            element(AccessibilityID.aiCombineButton).waitForExistence(timeout: 15),
            "no Combine after the last part"
        )
        XCTAssertTrue(element(AccessibilityID.aiResultPasteButton).exists, "Paste is still the default button")

        element(AccessibilityID.aiCombineButton).click()

        XCTAssertTrue(app.staticTexts["Combined summary"].waitForExistence(timeout: 15), "no combined summary")
    }
}
