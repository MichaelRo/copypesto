// SPDX-License-Identifier: MIT
import XCTest

/// Regression coverage for AGENTS.md invariant "writeItemToPasteboard must skip the next watcher
/// capture": selecting or re-copying an item must never produce a duplicate history entry.
final class DedupeFlowTests: PestoUITestCase {
    func test_copyingTheSameTextTwice_showsOneCard() {
        launch(seed: "empty")
        let sentinel = "pesto-dedupe-\(UUID().uuidString.prefix(6))"

        copyToClipboard(sentinel)
        showOverlay()
        XCTAssertTrue(card(containing: sentinel).waitForExistence(timeout: 10))
        copyToClipboard("something else")
        copyToClipboard(sentinel)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertEqual(cardCount(containing: sentinel), 1, "re-copying must pop the existing card, not add one")
    }

    /// A re-copied clip has to come to the front of the shelf, not just be recognised as a duplicate.
    func test_reCopyingAnOlderClip_bringsItsCardToTheFront() {
        launch()
        let older = "Team lunch is at 12:30 on Thursday, booked under Alex."
        showOverlay()
        XCTAssertTrue(card(containing: "Team lunch").waitForExistence(timeout: 10))
        XCTAssertGreaterThan(card(containing: "Team lunch").frame.minX, cards.firstMatch.frame.minX)

        copyToClipboard("something else \(UUID().uuidString.prefix(6))")
        copyToClipboard(older)
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let leftmost = cards.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        XCTAssertTrue(leftmost?.label.contains("Team lunch") == true, "the re-copied clip is not the first card")
        XCTAssertEqual(cardCount(containing: "Team lunch"), 1)
    }

    func test_selectingACard_doesNotAddADuplicate() {
        launch(seed: "empty")
        let sentinel = "pesto-select-\(UUID().uuidString.prefix(6))"
        copyToClipboard(sentinel)
        showOverlay()
        XCTAssertTrue(card(containing: sentinel).waitForExistence(timeout: 10))

        card(containing: sentinel).doubleClick()
        XCTAssertEqual(waitForPaste(count: 1), [sentinel])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        showOverlay()

        XCTAssertEqual(cardCount(containing: sentinel), 1, "the paste round-trip must not be re-captured")
    }

    func test_history_survivesARelaunch() {
        launch(seed: "empty")
        let sentinel = "pesto-persist-\(UUID().uuidString.prefix(6))"
        copyToClipboard(sentinel)
        showOverlay()
        XCTAssertTrue(card(containing: sentinel).waitForExistence(timeout: 10))

        relaunch()
        showOverlay()

        XCTAssertEqual(cardCount(containing: sentinel), 1)
    }
}
