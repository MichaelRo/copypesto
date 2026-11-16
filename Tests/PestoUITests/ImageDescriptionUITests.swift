// SPDX-License-Identifier: MIT
import XCTest

final class ImageDescriptionUITests: PestoUITestCase {
    func test_describeImage_showsAResultFromTheOnDeviceModel() throws {
        launch()
        showOverlay()
        let imageCard = card(containing: "image")
        XCTAssertTrue(imageCard.waitUntilExists(timeout: 5), "the seed has image cards")
        imageCard.rightClick()

        let describe = app.menuItems["Describe Image"]
        try XCTSkipUnless(describe.waitUntilExists(timeout: 3), "this Mac's on-device model cannot read images")
        describe.click()

        let title = app.staticTexts["Describe Image"]
        XCTAssertTrue(title.waitUntilExists(timeout: 60), "no result panel appeared")
        capture("image-description")
    }

    func test_textCards_offerNoImageAction() {
        launch()
        showOverlay()
        let textCard = card(containing: "text")
        XCTAssertTrue(textCard.waitUntilExists(timeout: 5))
        textCard.rightClick()
        XCTAssertTrue(app.menuItems["Summarize"].waitUntilExists(timeout: 3) || app.menuItems["Copy"].exists)
        XCTAssertFalse(app.menuItems["Describe Image"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
