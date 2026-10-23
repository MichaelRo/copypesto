// SPDX-License-Identifier: MIT
import XCTest

final class SearchAndCollectionsTests: PestoUITestCase {
    func test_searching_filtersTheGrid() {
        launch()
        showOverlay()
        let before = cards.count

        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field did not appear")
        field.click()
        field.typeText("Quarterly")

        let match = card(containing: "Quarterly report draft")
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertLessThan(cards.count, before, "the grid should narrow while searching")
        capture("search-results")
    }

    func test_commandBracket_cyclesToTheNextCollection() {
        launch()
        showOverlay()
        element(AccessibilityID.newCollectionButton).click()
        let name = element(AccessibilityID.collectionNameField)
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Work\r")
        let chip = element(AccessibilityID.collectionChip("Work"))
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        parkPointer()
        overlay.typeKey("[", modifierFlags: .command)
        expectation(for: NSPredicate(format: "isSelected == false"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)

        overlay.typeKey("]", modifierFlags: .command)

        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: chip)
        waitForExpectations(timeout: 5)
        overlay.typeKey("[", modifierFlags: .command)
        expectation(for: NSPredicate(format: "isSelected == false"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)
    }

    func test_searchingForNothing_showsNoCards() {
        launch()
        showOverlay()

        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("zzzz-no-such-clip")

        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(cards.count, 0)
        XCTAssertTrue(element(AccessibilityID.shelfEmptyState).exists, "no explanation for an empty search")
        capture("search-no-results")
    }

    func test_creatingACollection_addsAChip() {
        launch()
        showOverlay()

        element(AccessibilityID.newCollectionButton).click()
        let name = element(AccessibilityID.collectionNameField)
        XCTAssertTrue(name.waitForExistence(timeout: 5), "inline creator did not appear")
        name.click()
        name.typeText("Work\r")

        XCTAssertTrue(element(AccessibilityID.collectionChip("Work")).waitForExistence(timeout: 5))
        capture("collection-created")
    }

    /// The name takes keyboard focus on its own: typing at the app, with no click on the field, names the collection.
    func test_creatingACollection_takesTheNameWithoutAClick() {
        launch()
        showOverlay()

        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
        app.typeText("Work\r")

        XCTAssertTrue(element(AccessibilityID.collectionChip("Work")).waitForExistence(timeout: 5))
    }

    /// A name that is taken is numbered, as a folder is in Finder; nothing silently fails.
    func test_creatingACollectionWithATakenName_numbersIt() {
        launch()
        showOverlay()
        for _ in 0..<2 {
            element(AccessibilityID.newCollectionButton).click()
            XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
            app.typeText("Work\r")
            XCTAssertTrue(element(AccessibilityID.collectionChip("Work")).waitForExistence(timeout: 5))
        }

        XCTAssertTrue(element(AccessibilityID.collectionChip("Work 2")).waitForExistence(timeout: 5))
    }

    /// The chip's right-click menu offers Export Collection…, the same command Settings has. The save panel itself is
    /// not opened here (a modal panel would hold the test); `CollectionExporterTests` cover the file.
    func test_rightClickOnACollectionChip_offersExport() {
        launch()
        showOverlay()
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
        app.typeText("Work\r")
        let chip = element(AccessibilityID.collectionChip("Work"))
        XCTAssertTrue(chip.waitForExistence(timeout: 5))

        chip.rightClick()

        XCTAssertTrue(
            app.menuItems["Export Collection\u{2026}"].waitForExistence(timeout: 5),
            "the collection chip's menu has no Export Collection\u{2026}"
        )
        capture("collection-chip-menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Escape ends the creator, so the next click on + opens a fresh one instead of doing nothing.
    func test_escapeOnTheCreator_leavesRoomForANewOne() {
        launch()
        showOverlay()
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
        overlay.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 1))

        element(AccessibilityID.newCollectionButton).click()

        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
    }

    /// Empty search field, focused: the last searches are offered, newest first.
    func test_recentSearches_areOfferedWhenTheFieldIsEmpty() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Quarterly")
        // Cancel saves the query to history (Return now pastes the top result instead).
        element(AccessibilityID.searchCancelButton).click()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Recent searches"].waitForExistence(timeout: 5), "no recent searches offered")
        XCTAssertTrue(
            app.buttons["Quarterly"].exists || app.staticTexts["Quarterly"].exists,
            "the search is not listed"
        )
    }
}

final class FilterBarLayoutTests: PestoUITestCase {
    /// The four chip groups were told apart by hairlines only, and "Any time" read as part of the type group.
    func test_filterGroups_areCaptioned() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.filterChip("Any time")).waitForExistence(timeout: 5))

        for caption in ["Kind", "When", "Other"] {
            XCTAssertTrue(
                element(AccessibilityID.filterGroup(caption)).waitForExistence(timeout: 5),
                "no caption \(caption)"
            )
        }
        let when = element(AccessibilityID.filterGroup("When")).frame
        XCTAssertTrue(when.contains(element(AccessibilityID.filterChip("Today")).frame), "Today is outside When")
    }

    /// The clear button sat after the field, away from the text it clears.
    func test_clearButton_sitsInsideTheField_andEmptiesIt() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(element(AccessibilityID.searchClearButton).exists)
        field.click()
        field.typeText("report")

        let clear = element(AccessibilityID.searchClearButton)
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let frame = element(AccessibilityID.searchFieldFrame).frame
        XCTAssertTrue(frame.contains(clear.frame), "clear \(clear.frame) is outside the field \(frame)")
        XCTAssertTrue(frame.contains(field.frame), "text \(field.frame) is outside the field \(frame)")

        clear.click()

        XCTAssertFalse(clear.waitForExistence(timeout: 1))
        XCTAssertTrue((field.value as? String ?? "").isEmpty)
    }
}

final class ChipLabelTests: PestoUITestCase {
    /// Two chips were both spoken as "All", and "7d" is read as "7 d".
    func test_filterChips_haveDistinctSpokenLabels() {
        launch()
        showOverlay()
        XCTAssertTrue(element(AccessibilityID.collectionChip("All")).waitForExistence(timeout: 5))
        XCTAssertEqual(element(AccessibilityID.collectionChip("All")).label, "All collections")

        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.filterChip("7d")).waitForExistence(timeout: 5))

        XCTAssertEqual(element(AccessibilityID.filterChip("Any time")).label, "Any time")
        XCTAssertEqual(element(AccessibilityID.filterChip("7d")).label, "Last 7 days")
        XCTAssertEqual(element(AccessibilityID.filterChip("30d")).label, "Last 30 days")
    }
}

final class SettingsSidebarSemanticsTests: PestoUITestCase {
    func test_sidebarIsOneLabelledGroup_andMarksTheSelectedSection() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        XCTAssertTrue(
            settingsWindow.descendants(matching: .any)["Settings sections"].waitForExistence(timeout: 5),
            "the sidebar should be one labelled list"
        )
        element(AccessibilityID.settingsSidebar("Privacy")).click()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: element(AccessibilityID.settingsSidebar("Privacy"))
        )
        waitForExpectations(timeout: 5)
    }
}

final class ShelfNamingTests: PestoUITestCase {
    /// The list of cards says how many clips it holds.
    func test_theCardListSaysHowManyClipsItHolds() {
        launch()
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))

        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Clips'")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(((list.value as? String) ?? "").hasSuffix(" clips"), "the list should say how many clips")
    }
}
