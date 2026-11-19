// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// What only the iPad has, on a seeded, isolated launch: the hardware keyboard's commands, a card's menu reaching the
/// sidebar, the inline inspector and smart collections, and the grid in both orientations.
@MainActor
final class PadLibraryUITests: MobileUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
    }

    /// XCUITest sends a key only to an element with text focus, and a card never has it, so ⌘F from the grid is a hand
    /// check; from the search field, ⌘N and ⌘S reach the app's commands.
    func test_onIPad_withTheKeyboardCommandNWritesANoteThatCommandSSaves() {
        let app = launch()
        waitForSeededClips(in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        app.typeText("keyboard")
        XCTAssertTrue(
            card(containing: "Packing list", in: app).waitForNonExistence(timeout: timeout),
            "the search filters the grid"
        )

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["New Note"].waitForExistence(timeout: timeout), "⌘N opens the composer")
        app.typeText("Written with the keyboard")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["New Note"].waitForNonExistence(timeout: timeout), "⌘S saves and closes")
        XCTAssertTrue(
            card(containing: "Written with the keyboard", in: app).waitForExistence(timeout: timeout),
            "the saved note joins the search it matches"
        )
        capture("ipad-keyboard-note")
    }

    func test_onIPad_aCardsMenuPinsItAndTheSidebarsPinnedShowsIt() {
        let app = launch()
        waitForSeededClips(in: app)
        let sidebar = element(MobileAccessibilityID.sidebar, in: app)
        if !sidebar.exists { app.buttons["Show Sidebar"].firstMatch.tap() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))

        chooseContextMenuItem("Pin", on: card(containing: "Packing list", in: app), in: app)

        sidebar.staticTexts["Pinned"].tap()
        XCTAssertTrue(
            card(containing: "3F7D4E", in: app).waitForNonExistence(timeout: timeout),
            "Pinned leaves out what is not pinned"
        )
        XCTAssertTrue(visibleCard(containing: "Packing list", in: app), "the newly pinned clip is in Pinned")
        XCTAssertTrue(visibleCard(containing: "Gate B7", in: app), "the seeded pin stays")
        pressForContextMenu(card(containing: "Packing list", in: app), in: app)
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: timeout), "the pin was saved")
        capture("ipad-pinned")
    }

    func test_onIPad_theGridFillsBothOrientationsWithMoreThanOneColumn() {
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = launch()
            waitForSeededClips(in: app)
            let grid = element(MobileAccessibilityID.clipGrid, in: app)
            XCTAssertTrue(grid.waitForExistence(timeout: timeout))
            let window = app.windows.firstMatch.frame
            XCTAssertEqual(window.width > window.height, orientation == .landscapeLeft, "the window turned")
            let first = cards(in: app).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: timeout) && first.isHittable, "the grid settled")
            XCTAssertLessThan(first.frame.width, grid.frame.width / 2, "more than one column in \(orientation)")
            capture("ipad-grid-\(orientation == .portrait ? "portrait" : "landscape")")
            app.terminate()
        }
    }

    func test_onIPad_editingTextInTheInspectorUpdatesTheGridAndOffersUndo() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        let target = card(containing: "Packing list", in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        openDetail(of: target, in: app)

        let edit = element(MobileAccessibilityID.editTextButton, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "a text clip offers Edit Text")
        edit.tap()
        let editor = element(MobileAccessibilityID.textEditor, in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.tap()
        editor.typeText(" and sunscreen")
        let save = element(MobileAccessibilityID.saveTextButton, in: app)
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        save.tap()

        XCTAssertTrue(editor.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(card(containing: "sunscreen", in: app).waitForExistence(timeout: timeout), "grid updates inline")
        capture("ipad-inspector-text-edited")

        let undo = element(MobileAccessibilityID.undoButton, in: app)
        XCTAssertTrue(undo.waitForExistence(timeout: timeout), "Undo is offered after saving")
        undo.tap()
        XCTAssertTrue(card(containing: "sunscreen", in: app).waitForNonExistence(timeout: timeout), "Undo reverts edit")
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
    }

    func test_onIPad_aSmartCollectionFromTheSidebarJoinsItAndFiltersTheGrid() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        waitForSeededClips(in: app)
        let sidebar = element(MobileAccessibilityID.sidebar, in: app)
        if !sidebar.exists { app.buttons["Show Sidebar"].firstMatch.tap() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))

        sidebar.buttons["New Collection"].firstMatch.tap()
        let name = element(MobileAccessibilityID.collectionNameField, in: app)
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.typeText("Web")
        app.buttons["Smart"].firstMatch.tap()
        let value = element(MobileAccessibilityID.smartRuleValue, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: timeout), "a smart collection asks for a rule")
        value.tap()
        app.buttons["Link"].firstMatch.tap()
        element(MobileAccessibilityID.saveCollectionButton, in: app).tap()

        XCTAssertTrue(sidebar.staticTexts["Web"].waitForExistence(timeout: timeout), "smart collection joins sidebar")
        XCTAssertTrue(card(containing: "copypesto.net", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(visibleCard(containing: "Packing list", in: app), "the rule leaves the notes out")
        capture("ipad-smart-collection")
    }

    func test_onIPad_decodeJWTFromTheInspectorMoreMenuShowsThePayload() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch(environment: [
            "PESTO_UITEST_JWT": "1", "PESTO_UITEST_DEFAULT_uitestAuthenticationGranted": "true"
        ])
        let token = card(containing: "108 characters hidden", in: app)
        XCTAssertTrue(token.waitForExistence(timeout: timeout))
        openDetail(of: token, in: app)

        app.buttons["More"].firstMatch.tap()
        let decode = app.buttons["Decode JWT"]
        XCTAssertTrue(decode.waitForExistence(timeout: timeout))
        decode.tap()

        XCTAssertTrue(element(MobileAccessibilityID.decodeJWTSheet, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Ada Lovelace")).firstMatch.exists,
            "the payload is readable"
        )
        capture("ipad-decode-jwt")

        element(MobileAccessibilityID.decodeJWTCopyPayload, in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.decodeJWTSheet, in: app).waitForNonExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Ada Lovelace"].exists, "the card stays hidden")
    }
}
