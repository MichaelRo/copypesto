// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The iPhone passes for what the polish round added: editing a clip's text, the appearance handed back to the
/// system after Dark, a collection's icon and the offer to add what was copied.
@MainActor
final class LibraryEditingUITests: MobileUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
    }

    /// The relative luminance (0 black, 1 white) of one point of a screenshot, in points.
    private func luminance(of screenshot: XCUIScreenshot, at point: CGPoint) -> CGFloat {
        guard let image = screenshot.image.cgImage else { return -1 }
        let scale = screenshot.image.scale
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let height = CGFloat(image.height)
            context.draw(image, in: CGRect(
                x: -point.x * scale, y: -(height - point.y * scale - 1),
                width: CGFloat(image.width), height: height
            ))
            return true
        }
        guard drawn else { return -1 }
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }

    func test_whenTextEditedInTheDetail_thenTheCardShowsItAndUndoIsOffered() {
        let app = launch()
        let target = card(containing: "Packing list", in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        openDetail(of: target, in: app)

        let edit = element(MobileAccessibilityID.editTextButton, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "a text clip offers Edit Text")
        XCTAssertTrue(edit.isHittable, "Edit Text is within reach at the top of the detail")
        capture("iphone-detail-edit-text")
        edit.tap()
        let editor = element(MobileAccessibilityID.textEditor, in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.tap()
        editor.typeText(" and sunscreen")
        capture("iphone-text-editing")
        let save = element(MobileAccessibilityID.saveTextButton, in: app)
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        save.tap()

        XCTAssertTrue(editor.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.undoButton, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.editTextButton, in: app).waitForExistence(timeout: timeout))
        capture("iphone-text-edited")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(card(containing: "sunscreen", in: app).waitForExistence(timeout: timeout))
    }

    func test_whenDarkIsSetBackToSystem_thenTheControlsAreLightAgain() {
        let app = launch(environment: ["PESTO_UITEST_DEFAULT_appearanceMode": "dark"])
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        let window = app.windows.firstMatch.frame
        let ground = CGPoint(x: 4, y: window.midY)
        XCTAssertLessThan(luminance(of: XCUIScreen.main.screenshot(), at: ground), 0.3, "the launch is dark")

        element(MobileAccessibilityID.settingsButton, in: app).tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        picker.tap()
        let system = app.buttons["System"].firstMatch
        XCTAssertTrue(system.waitForExistence(timeout: timeout))
        system.tap()
        let sheet = XCUIScreen.main.screenshot()
        capture("iphone-settings-after-system", sheet)
        XCTAssertGreaterThan(luminance(of: sheet, at: CGPoint(x: 4, y: window.maxY - 40)), 0.7, "the sheet is light")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        let library = XCUIScreen.main.screenshot()
        capture("iphone-library-after-system", library)
        XCTAssertGreaterThan(luminance(of: library, at: ground), 0.7, "the ground is light")
        let search = app.searchFields.firstMatch
        if search.exists {
            let field = search.frame
            XCTAssertGreaterThan(
                luminance(of: library, at: CGPoint(x: field.minX + 8, y: field.midY)), 0.6, "the search bar is light"
            )
        }
    }

    func test_whenACollectionIsCreated_thenItsIconIsChosenAndShownOnTheChip() {
        let app = launch()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        app.buttons["New Collection"].firstMatch.tap()
        let name = element(MobileAccessibilityID.collectionNameField, in: app)
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.typeText("Recipes")
        let leaf = app.buttons["Leaf"].firstMatch
        XCTAssertTrue(leaf.waitForExistence(timeout: timeout), "Core's icons are offered")
        leaf.tap()
        app.buttons["Orange"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Leaf"].firstMatch.isSelected, "the chosen icon reads as chosen")
        capture("iphone-collection-icon-picker")
        element(MobileAccessibilityID.saveCollectionButton, in: app).tap()

        let chip = element(MobileAccessibilityID.chipRow, in: app).buttons["Recipes"]
        XCTAssertTrue(chip.waitForExistence(timeout: timeout))
        capture("iphone-collection-chip", element(MobileAccessibilityID.chipRow, in: app).screenshot())
    }

    func test_whenSomethingWasCopiedElsewhere_thenItIsOfferedWithThePasteButton() {
        let app = launch(environment: ["PESTO_UITEST_CLIPBOARD": "Copied in another app"])
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        let banner = element(MobileAccessibilityID.clipboardOffer, in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: timeout), "the copy is offered")
        XCTAssertTrue(banner.staticTexts["Add what you copied"].exists)
        capture("iphone-clipboard-offer")
        banner.buttons["Not Now"].tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 2), "Not Now takes the offer down")
    }

    func test_chipRowStaysFixedVertically_andSelectionModeAllowsScrollAndHorizontalSwipe() {
        let app = launch()
        waitForSeededClips(in: app)

        let chips = element(MobileAccessibilityID.chipRow, in: app)
        XCTAssertTrue(chips.exists)
        let chipsMinYBefore = chips.frame.minY
        let firstCardBefore = cards(in: app).element(boundBy: 0).frame.minY

        let chipStart = chips.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let chipDown = chips.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 4.0))
        chipStart.press(forDuration: 0.05, thenDragTo: chipDown)
        XCTAssertEqual(chips.frame.minY, chipsMinYBefore, accuracy: 2.0, "chip row must not drag vertically")
        XCTAssertEqual(
            cards(in: app).element(boundBy: 0).frame.minY,
            firstCardBefore,
            accuracy: 2.0,
            "dragging chip row down must not trigger grid pull-to-refresh"
        )

        element(MobileAccessibilityID.selectClipsButton, in: app).tap()
        XCTAssertTrue(
            app.staticTexts["0 clips selected"].waitForExistence(timeout: timeout),
            "selection bar opens"
        )

        let card0 = cards(in: app).element(boundBy: 0)
        let card1 = cards(in: app).element(boundBy: 1)
        let start = card0.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = card1.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(
            app.staticTexts["2 clips selected"].waitForExistence(timeout: timeout),
            "horizontal swipe selects across cards in selection mode"
        )

        let grid = element(MobileAccessibilityID.clipGrid, in: app)
        let cardYBeforeScroll = card0.frame.minY
        grid.swipeUp()
        XCTAssertLessThan(
            card0.frame.minY,
            cardYBeforeScroll - 20,
            "vertical scroll still moves cards in selection mode"
        )
    }

    func test_whenQuestionFindsNoDirectMatches_thenAskChipAndEmptyStateCTAAreShown() {
        let app = launch()
        waitForSeededClips(in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("links from yesterday")

        XCTAssertTrue(
            element(MobileAccessibilityID.askChip, in: app).waitForExistence(timeout: timeout),
            "Ask chip is immediately visible while searching"
        )
        let askCTA = element(MobileAccessibilityID.emptyStateAskButton, in: app)
        XCTAssertTrue(
            askCTA.waitForExistence(timeout: timeout),
            "No-results empty state offers an Ask Pesto CTA for natural-language queries"
        )
        askCTA.tap()
        XCTAssertTrue(
            element(MobileAccessibilityID.askedChip, in: app).waitForExistence(timeout: timeout),
            "Tapping the empty-state Ask Pesto CTA applies Ask filters"
        )
    }
}
