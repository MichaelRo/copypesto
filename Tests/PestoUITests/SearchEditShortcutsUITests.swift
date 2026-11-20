// SPDX-License-Identifier: MIT
import XCTest

final class SearchEditShortcutsUITests: PestoUITestCase {
    private func assertFieldValue(
        _ field: XCUIElement,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date.now.addingTimeInterval(2)
        while (field.value as? String ?? "") != expected, Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        }
        XCTAssertEqual(field.value as? String ?? "", expected, file: file, line: line)
    }

    func test_whenUsingTextEditShortcutsInSearchField_thenTextUpdatesWithoutClobberingShelf() {
        launch()
        showOverlay()

        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitUntilExists(timeout: 5), "search field did not appear")
        field.click()
        field.typeText("hello world pesto")
        XCTAssertTrue(overlay.exists, "overlay closed after typeText")
        assertFieldValue(field, equals: "hello world pesto")

        // ⌥← moves back one word ("pesto"), ⌥⌫ deletes "world "
        field.typeKey(.leftArrow, modifierFlags: .option)
        field.typeKey(.delete, modifierFlags: .option)
        XCTAssertEqual(field.value as? String, "hello pesto")
        XCTAssertTrue(overlay.exists, "shelf closed during ⌥← / ⌥⌫")

        // ⌘← moves to start, → moves one char, ← moves back
        field.typeKey(.leftArrow, modifierFlags: .command)
        field.typeKey(.rightArrow, modifierFlags: [])
        field.typeKey(.leftArrow, modifierFlags: [])

        // ⌘→ moves to end, ⌥→ stays at end
        field.typeKey(.rightArrow, modifierFlags: .command)
        field.typeKey(.rightArrow, modifierFlags: .option)

        // Select all, ⌘X cuts, ⌘V pastes back
        field.typeKey("a", modifierFlags: .command)
        field.typeKey("x", modifierFlags: .command)
        assertFieldValue(field, equals: "")
        XCTAssertTrue(overlay.exists, "shelf closed on ⌘X")

        field.typeKey("v", modifierFlags: .command)
        assertFieldValue(field, equals: "hello pesto")
        XCTAssertTrue(overlay.exists, "shelf closed on ⌘V")

        // ⌘⌫ deletes to line start
        field.typeKey(.delete, modifierFlags: .command)
        assertFieldValue(field, equals: "")
        XCTAssertTrue(overlay.exists, "shelf closed on ⌘⌫")
    }
}
