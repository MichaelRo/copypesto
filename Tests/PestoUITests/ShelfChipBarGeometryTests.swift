// SPDX-License-Identifier: MIT
import XCTest

/// Where the app chips sit on the command bar: right after the last collection while the collections fit, held at the
/// bar's end beside the toolbar when they overflow, and never in the way of the inline name field.
final class ShelfChipBarGeometryTests: PestoUITestCase {
    private func chips(prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    }

    private var appChips: [XCUIElement] {
        chips(prefix: "app-chip-")
    }

    private func openMarketingShelf() {
        launch(seed: "marketing", defaults: ["hasOnboarded": "true"])
        showOverlay()
        let deadline = Date().addingTimeInterval(10)
        while appChips.count < 3, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        parkPointer()
        XCTAssertGreaterThanOrEqual(appChips.count, 3, "the marketing seed should give at least three app chips")
    }

    private func addCollection(named name: String) {
        element(AccessibilityID.newCollectionButton).click()
        let field = element(AccessibilityID.collectionNameField)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no name field for \(name)")
        field.typeText("\(name)\r")
        XCTAssertTrue(
            element(AccessibilityID.collectionChip(name)).waitForExistence(timeout: 5), "\(name) was not added"
        )
        parkPointer()
    }

    func test_whenTheCollectionsFit_thenTheAppChipsFollowTheLastOneAndTheToolbarEndsTheBar() throws {
        openMarketingShelf()
        let collections = chips(prefix: "collection-chip-") + chips(prefix: "tag-chip-")
        let last = try XCTUnwrap(collections.max { $0.frame.maxX < $1.frame.maxX }, "no collection chip")
        let first = try XCTUnwrap(appChips.first)

        XCTAssertEqual(
            first.frame.minX - last.frame.maxX, 17, accuracy: 7,
            "the first app chip should sit right after the last collection or tag chip"
        )
        let search = element(AccessibilityID.searchButton).frame
        let lastToolbarButton = element(AccessibilityID.settingsButton).frame
        XCTAssertGreaterThan(search.minX, appChips.last?.frame.maxX ?? .infinity, "the search button follows the chips")
        XCTAssertLessThan(overlay.frame.maxX - lastToolbarButton.maxX, 32, "the toolbar belongs at the bar's right end")
    }

    func test_whenTheCollectionsOverflow_thenEveryAppChipStaysInReachLeftOfTheToolbar() {
        openMarketingShelf()
        for index in 1...10 {
            addCollection(named: "Quarterly planning notes \(index)")
        }

        let found = appChips
        XCTAssertGreaterThanOrEqual(found.count, 3)
        let search = element(AccessibilityID.searchButton)
        XCTAssertTrue(search.isHittable)
        let panel = overlay.frame
        for chip in found {
            XCTAssertTrue(chip.isHittable, "\(chip.identifier) is out of reach")
            XCTAssertGreaterThanOrEqual(chip.frame.minX, panel.minX, "\(chip.identifier) starts outside the shelf")
            XCTAssertLessThanOrEqual(chip.frame.maxX, panel.maxX, "\(chip.identifier) ends outside the shelf")
            XCTAssertLessThanOrEqual(chip.frame.maxX, search.frame.minX, "\(chip.identifier) is under the toolbar")
        }
        capture("chips-with-many-collections")
    }

    func test_whenTheCreatorIsOpen_thenTheNameFieldTakesClicks() {
        openMarketingShelf()

        element(AccessibilityID.newCollectionButton).click()

        let field = element(AccessibilityID.collectionNameField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable, "the chip row's drop layer must not cover the name field")
    }
}
