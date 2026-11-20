// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// Going from the pad's layout to the phone's and back (a window resized in Split View, a foldable iPhone later)
/// keeps what the person was doing. XCUITest cannot resize an iPad window, so a DEBUG-only launch environment forces
/// the library's width class and a small control flips it (`UITestLayout`); the two layouts are torn down and built
/// exactly as a real change of width does.
@MainActor
final class LayoutSwapUITests: MobileUITestCase {
    private func launch(extraClips: Int = 0) -> XCUIApplication {
        var environment = ["PESTO_UITEST_SIZE_CLASS": "regular"]
        if extraClips > 0 { environment["PESTO_UITEST_EXTRA_CLIPS"] = String(extraClips) }
        return launch(environment: environment)
    }

    private func swap(_ app: XCUIApplication, to layout: String) {
        let detail = element("uitest-swap-layout-detail", in: app)
        let control = detail.exists ? detail : element("uitest-swap-layout", in: app)
        XCTAssertTrue(control.waitForExistence(timeout: timeout), "the UI-test swap control is there")
        control.tap()
        let root = element("uitest-swap-layout", in: app)
        let deadline = Date.now.addingTimeInterval(timeout)
        while root.label != layout, Date.now < deadline {
            _ = root.waitForExistence(timeout: 0.3)
        }
        XCTAssertEqual(root.label, layout)
    }

    func test_onIPad_anUnsavedTextEditAndTheSearchSurviveTheSwapThereAndBack() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: timeout))
        search.tap()
        search.typeText("Packing\n")
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))

        openDetail(of: card(containing: "Packing list", in: app), in: app)
        let edit = element(MobileAccessibilityID.editTextButton, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: timeout))
        edit.tap()
        let editor = element(MobileAccessibilityID.textEditor, in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.tap()
        editor.typeText(" ZZ9")
        XCTAssertTrue((editor.value as? String ?? "").contains("ZZ9"))
        capture("ipad-before-swap")

        swap(app, to: "compact")
        let phoneEditor = element(MobileAccessibilityID.textEditor, in: app)
        XCTAssertTrue(
            phoneEditor.waitForExistence(timeout: timeout),
            "the open editor is still open in the phone layout"
        )
        XCTAssertTrue((phoneEditor.value as? String ?? "").contains("ZZ9"), "the draft survived the swap")
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).exists, "the clip is still open")
        capture("ipad-after-swap-compact")

        let hideKeyboard = app.keyboards.buttons["Hide keyboard"]
        if hideKeyboard.exists, hideKeyboard.isHittable { hideKeyboard.tap() }
        swap(app, to: "regular")
        let padEditor = element(MobileAccessibilityID.textEditor, in: app)
        XCTAssertTrue(padEditor.waitForExistence(timeout: timeout), "the editor is open again in the pad layout")
        XCTAssertTrue((padEditor.value as? String ?? "").contains("ZZ9"), "the draft survived the way back")
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Packing", "the search text survived")
        capture("ipad-after-swap-regular")
    }

    func test_onIPad_theGridKeepsItsFirstCardAcrossTheSwap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch(extraClips: 80)
        let grid = element(MobileAccessibilityID.clipGrid, in: app)
        XCTAssertTrue(grid.waitForExistence(timeout: timeout))
        XCTAssertTrue(cards(in: app).firstMatch.waitForExistence(timeout: timeout))
        for _ in 0..<2 {
            grid.swipeUp()
        }

        let anchorLabel = try XCTUnwrap(firstFullyVisibleCardLabel(in: app), "a card is showing after the scroll")
        XCTAssertFalse(anchorLabel.contains("Filler clip 79"), "the grid really scrolled")
        capture("ipad-scrolled")

        swap(app, to: "compact")
        XCTAssertTrue(waitUntilNearTop(label: anchorLabel, in: app), "the same card is at the top in the phone layout")
        capture("ipad-scrolled-after-compact")

        swap(app, to: "regular")
        let back = waitUntilNearTop(label: anchorLabel, in: app)
        capture("ipad-scrolled-after-regular")
        let frames = cardFrames(in: app).map { "\($0.frame.minY)|\($0.label.prefix(30))" }.joined(separator: "; ")
        XCTAssertTrue(back, "and again after the way back; anchor \(anchorLabel); cards \(frames)")
    }

    private func cardFrames(in app: XCUIApplication) -> [(label: String, frame: CGRect)] {
        let window = app.windows.firstMatch.frame
        return cards(in: app).allElementsBoundByIndex.compactMap { card in
            let frame = card.frame
            return card.exists && !frame.isEmpty && window.contains(frame) ? (card.label, frame) : nil
        }
    }

    private func firstFullyVisibleCardLabel(in app: XCUIApplication) -> String? {
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        return cardFrames(in: app).filter { $0.frame.minY >= barBottom }.min { $0.frame.minY < $1.frame.minY }?.label
    }

    private func waitUntilNearTop(label: String, in app: XCUIApplication) -> Bool {
        let stable = label.split(separator: ",").prefix(2).joined(separator: ",")
        let deadline = Date.now.addingTimeInterval(timeout)
        let screenHeight = app.windows.firstMatch.frame.height
        while Date.now < deadline {
            let match = cardFrames(in: app).first { $0.label.hasPrefix(stable) }
            if let match, match.frame.minY < screenHeight * 0.45 { return true }
            _ = app.waitForExistence(timeout: 0.3)
        }
        return false
    }
}
