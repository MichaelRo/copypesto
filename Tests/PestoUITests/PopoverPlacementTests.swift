// SPDX-License-Identifier: MIT
import XCTest

final class PopoverPlacementTests: PestoUITestCase {
    /// The hover card rests on top of the shelf, above its chip bar and clips, centred on its clip and inside the
    /// shelf's width.
    func test_hoverCard_restsAboveItsClipInsideTheShelf() {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.hover()
        XCTAssertTrue(
            element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 5), "no hover card appeared"
        )
        let hoverCard = app.windows.matching(NSPredicate(format: "label == 'Clip details'")).firstMatch
        XCTAssertTrue(hoverCard.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        captureScreen("hover-card-above-clip")

        let shelfTop = overlay.frame.minY
        XCTAssertLessThanOrEqual(
            hoverCard.frame.maxY, shelfTop + 1,
            "the hover card (bottom \(hoverCard.frame.maxY)) overlaps the shelf (top \(shelfTop))"
        )
        XCTAssertGreaterThanOrEqual(hoverCard.frame.maxY, shelfTop - 40, "the hover card floats far above the shelf")
        XCTAssertGreaterThanOrEqual(hoverCard.frame.minX, overlay.frame.minX - 1, "it hangs off the shelf's left edge")
        XCTAssertLessThanOrEqual(hoverCard.frame.maxX, overlay.frame.maxX + 1, "it hangs off the shelf's right edge")
    }

    /// On the top shelf the card opens below it, so it never covers the menu bar side or the chip bar.
    func test_hoverCard_onTheTopShelf_restsBelowItsClipInsideTheShelf() {
        launch(defaults: ["hasOnboarded": "true", "shelfPosition": "underNotch"])
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.hover()
        XCTAssertTrue(
            element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 5), "no hover card appeared"
        )
        let hoverCard = app.windows.matching(NSPredicate(format: "label == 'Clip details'")).firstMatch
        XCTAssertTrue(hoverCard.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        captureScreen("hover-card-below-clip-top-shelf")

        let shelfBottom = overlay.frame.maxY
        XCTAssertGreaterThanOrEqual(
            hoverCard.frame.minY, shelfBottom - 1,
            "the hover card (top \(hoverCard.frame.minY)) overlaps the shelf (bottom \(shelfBottom))"
        )
        XCTAssertLessThanOrEqual(hoverCard.frame.minY, shelfBottom + 40, "the hover card floats far below the shelf")
        XCTAssertGreaterThanOrEqual(hoverCard.frame.minX, overlay.frame.minX - 1, "it hangs off the shelf's left edge")
        XCTAssertLessThanOrEqual(hoverCard.frame.maxX, overlay.frame.maxX + 1, "it hangs off the shelf's right edge")
    }
}
