// SPDX-License-Identifier: MIT
import XCTest

/// The bar that appears under the shelf once two or more clips are selected. Its pictures go to the gate's screenshot
/// folder in both appearances, with and without Paste All, so a change to its look is seen and not only asserted.
final class SelectionBarTests: PestoUITestCase {
    private func settle(_ seconds: TimeInterval = 0.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func inBothAppearances(_ shot: (String) -> Void) {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            launch(seed: "marketing", defaults: [
                "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                "linkPreviewsEnabled": "false", "appearanceMode": mode
            ])
            showOverlay()
            shot(mode)
        }
    }

    private func pick(_ cardIndexes: [Int]) {
        var position = 0
        for index in cardIndexes {
            while position < index {
                overlay.typeKey(.rightArrow, modifierFlags: [])
                position += 1
            }
            overlay.typeKey(.space, modifierFlags: [])
        }
    }

    func test_selectionBar_ofTextClips_offersPasteAllPasteOneByOneAndDelete() {
        inBothAppearances { mode in
            pick([0, 2, 3])
            XCTAssertTrue(element(AccessibilityID.pasteAllButton).waitForExistence(timeout: 5))
            XCTAssertTrue(element(AccessibilityID.pasteOneByOneButton).exists)
            XCTAssertTrue(element(AccessibilityID.deleteSelectedButton).exists)
            settle()
            capture("selection-bar-merge-\(mode)")
        }
    }

    func test_selectionBar_ofMixedClips_offersNoPasteAll() {
        inBothAppearances { mode in
            pick([0, 1])
            XCTAssertTrue(element(AccessibilityID.pasteOneByOneButton).waitForExistence(timeout: 5))
            XCTAssertFalse(
                element(AccessibilityID.pasteAllButton).exists,
                "an image cannot be pasted together with text"
            )
            settle()
            capture("selection-bar-mixed-\(mode)")
        }
    }

    func test_selectionBar_deleteAsksInsideTheShelf() {
        inBothAppearances { mode in
            pick([0, 2, 3])
            element(AccessibilityID.deleteSelectedButton).click()
            XCTAssertTrue(element(AccessibilityID.deleteConfirmButton).waitForExistence(timeout: 5))
            settle()
            capture("selection-bar-delete-confirm-\(mode)")
            element(AccessibilityID.deleteCancelButton).click()
        }
    }

    func test_selectionBar_onTheTopShelfWithCompactCards_staysInsideThePanel() {
        launch(seed: "marketing", defaults: [
            "hasOnboarded": "true", "cardSize": "compact", "accentColorHex": "brand",
            "linkPreviewsEnabled": "false", "shelfPosition": "underNotch"
        ])
        showOverlay()
        pick([0, 2, 3])
        let bar = element(AccessibilityID.deleteSelectedButton)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(bar.frame.maxY, overlay.frame.maxY, "the bar must not hang below the panel")
        settle()
        capture("selection-bar-top-compact")
    }
}
