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

final class SearchOpeningMotionTests: PestoUITestCase {
    /// Search opens with motion (the field grows from the search button's end, the filters arrive after it), and the
    /// field takes keys from the first frame: a word typed at once must arrive whole.
    func test_whenSearchOpensWithMotion_thenAWordTypedAtOnceIsNotLost() {
        launch(motion: true)
        showOverlay()
        element(AccessibilityID.searchButton).click()
        app.typeText("pine nuts")
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "pine nuts", "keys typed during the opening were lost")
        XCTAssertTrue(element(AccessibilityID.filterChip("Today")).waitForExistence(timeout: 5))
    }
}

final class FilterBarLayoutTests: PestoUITestCase {
    /// The chip groups are one row told apart by dividers, and each is a named group for VoiceOver: "Any time" must
    /// not read as part of the type group.
    func test_filterGroups_areNamedAndHoldTheirChips() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.filterChip("Today")).waitForExistence(timeout: 5))

        for caption in ["Kind", "When", "Other"] {
            XCTAssertTrue(
                element(AccessibilityID.filterGroup(caption)).waitForExistence(timeout: 5),
                "no group named \(caption)"
            )
        }
        let when = element(AccessibilityID.filterGroup("When")).frame
        XCTAssertTrue(when.contains(element(AccessibilityID.filterChip("Today")).frame), "Today is outside When")
    }

    /// Today and Yesterday stay one click; the rest of the ranges are one menu chip, and Ask takes any other date.
    func test_whenHasDayChips_andOneMoreMenu() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.filterChip("Today")).waitForExistence(timeout: 5))
        XCTAssertTrue(element(AccessibilityID.filterChip("Yesterday")).exists)
        XCTAssertFalse(element(AccessibilityID.filterChip("7d")).exists, "7d is still its own chip")

        let more = element(AccessibilityID.filterChip("More time ranges"))
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no More chip in When")
        more.click()
        for title in ["Any Time", "Last 7 Days", "Last 30 Days", "Last Hour", "Last 3 Hours", "On a Day"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 5), "no \(title) in the When menu")
        }
        app.menuItems["Last 3 Hours"].click()

        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isSelected, "the More chip does not show the range in force")
        XCTAssertEqual(more.label, "When, Last 3 hours")
        capture("filter-bar-when-chip")
    }

    /// From is one menu chip with every app and its count; choosing one names the chip.
    func test_fromMenu_listsEveryApp_andChoosingOneNamesTheChip() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let from = element(AccessibilityID.filterChip("Filter by app"))
        XCTAssertTrue(from.waitForExistence(timeout: 5), "no From chip")
        XCTAssertEqual(from.label, "From, any app")

        from.click()
        let mail = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Mail'")).firstMatch
        XCTAssertTrue(mail.waitForExistence(timeout: 5), "Mail is not in the From menu")
        mail.click()

        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertEqual(from.label, "From, Mail")
        XCTAssertTrue(from.isSelected)
    }

    /// Format is one menu chip with Markdown, JSON and the languages in the history.
    func test_formatMenu_offersMarkdownAndJSON_andChoosingOneNamesTheChip() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let format = element(AccessibilityID.filterChip("Filter by format"))
        XCTAssertTrue(format.waitForExistence(timeout: 5), "no Format chip")

        format.click()
        XCTAssertTrue(app.menuItems["Markdown"].waitForExistence(timeout: 5))
        app.menuItems["JSON"].click()

        XCTAssertEqual(format.label, "Format, JSON")
        XCTAssertTrue(format.isSelected)
    }

    /// Typing on the shelf without ⌘F opens the search with what was typed. Keys that arrive before the field has focus
    /// replaced the first one (a ticket number lost its first digits).
    func test_typingFast_onTheShelf_keepsEveryKey() {
        launch()
        showOverlay()

        app.typeText("1234")

        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "1234")
    }

    /// The field took focus with its text selected, so the next key replaced the first one.
    func test_typingSlowly_onTheShelf_appendsToWhatWasTyped() {
        launch()
        showOverlay()

        app.typeText("1")
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        app.typeText("2")

        XCTAssertEqual(field.value as? String, "12")
    }

    /// The keyboard reaches the More chip with Tab, and Return opens its menu (it used to step through presets).
    func test_whenMoreMenu_opensFromTheKeyboard() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()

        // Kind (6), Format, Today, Yesterday, then More.
        for _ in 0..<10 {
            app.typeKey(.tab, modifierFlags: [])
        }
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.menuItems["Last 7 Days"].waitForExistence(timeout: 5), "Return did not open the When menu")
        app.typeKey(.escape, modifierFlags: [])
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
        XCTAssertTrue(element(AccessibilityID.filterChip("Today")).waitForExistence(timeout: 5))

        XCTAssertEqual(element(AccessibilityID.filterChip("Today")).label, "Today")
        XCTAssertEqual(element(AccessibilityID.filterChip("More time ranges")).label, "More time ranges")
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
