// SPDX-License-Identifier: MIT
import XCTest

final class AIResultDelayedPasteUITests: PestoUITestCase {
    private func openAIResultOnSecondCard() -> String {
        showOverlay()
        let secondCard = cards.element(boundBy: 1)
        XCTAssertTrue(secondCard.waitUntilExists(timeout: 10), "second card missing")
        let sourceLabel = secondCard.label
        secondCard.rightClick()

        let keyPoints = app.menuItems["Key Points"]
        XCTAssertTrue(keyPoints.waitUntilExists(timeout: 5), "Key Points menu item missing")
        keyPoints.click()
        return sourceLabel
    }

    func test_whenWaitingOver20SecondsBeforePaste_thenPasteLandsAndAddsNoClipWhileCopyResultAddsOne() {
        launch(aiFixture: true)
        showOverlay()
        let countBeforePaste = cards.count
        _ = openAIResultOnSecondCard()

        let pasteButton = element(AccessibilityID.aiResultPasteButton)
        XCTAssertTrue(pasteButton.waitUntilExists(timeout: 15), "AIResultPanel Paste button missing")

        let copyResultButton = app.buttons["Copy Result"]
        XCTAssertTrue(copyResultButton.exists, "Copy Result button missing")
        XCTAssertEqual(
            app.windows["AI result"].frame.width, 340, accuracy: 2,
            "AIResultPanel width should match AIResultLayout.panelWidth"
        )

        // Wait >20 s on AIResultPanel before Return
        RunLoop.current.run(until: Date().addingTimeInterval(21))

        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(waitForPaste(count: 1).isEmpty, "Return after >20 s should land paste")

        // Paste must add no clip; source clip moves to front
        showOverlay()
        XCTAssertEqual(cards.count, countBeforePaste, "Paste should not add a new clip")
        XCTAssertTrue(
            cards.firstMatch.label.contains("Team lunch"),
            "source clip should move to front after paste, got: \(cards.firstMatch.label)"
        )

        // Copy Result adds a new clip
        cards.element(boundBy: 1).rightClick()
        app.menuItems["Key Points"].click()
        XCTAssertTrue(copyResultButton.waitUntilExists(timeout: 15))
        copyResultButton.click()

        showOverlay()
        XCTAssertEqual(cards.count, countBeforePaste + 1, "Copy Result should add a clip to history")
    }
}
