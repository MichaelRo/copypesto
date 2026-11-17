// SPDX-License-Identifier: MIT
import XCTest

final class ColorPanelUITests: PestoUITestCase {
    func test_whenOpeningColorPickerFromShelf_thenCustomColorPickerAppears() {
        launch()
        showOverlay()

        element(AccessibilityID.newCollectionButton).click()
        let field = element(AccessibilityID.collectionNameField)
        XCTAssertTrue(field.waitUntilExists(timeout: 5), "collection name field missing")
        field.typeText("Colors\r")

        let colorsChip = element(AccessibilityID.collectionChip("Colors"))
        XCTAssertTrue(colorsChip.waitUntilExists(timeout: 5), "created Colors chip missing")
        colorsChip.rightClick()

        let editItem = app.menuItems["Edit\u{2026}"]
        XCTAssertTrue(editItem.waitUntilExists(timeout: 5), "Edit collection menu item missing")
        editItem.click()

        let otherColor = element(AccessibilityID.collectionOtherColor)
        XCTAssertTrue(otherColor.waitUntilExists(timeout: 5), "Other Color swatch missing in edit popover")
        otherColor.click()

        let pickerAppeared = app.popovers.firstMatch.waitUntilExists(timeout: 5)
            || app.windows["Colors"].waitUntilExists(timeout: 2)
        XCTAssertTrue(pickerAppeared, "custom color picker did not open from shelf")
        XCTAssertTrue(overlay.exists, "shelf should remain open while color picker is shown")
    }
}
