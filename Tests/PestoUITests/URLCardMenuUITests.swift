// SPDX-License-Identifier: MIT
import AppKit
import XCTest

final class URLCardMenuUITests: PestoUITestCase {
    func test_whenRightClickingURLCard_thenCopyPageTitleAndPreviewImageSitUnderCopy() {
        launch(
            defaults: ["hasOnboarded": "true", "linkPreviewsEnabled": "true"],
            linkStubMillis: 10
        )
        let board = NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)"))
        board.clearContents()
        board.setString("https://example.com/article", forType: .string)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        showOverlay()

        let urlCard = card(containing: "example.com/article")
        XCTAssertTrue(urlCard.waitUntilExists(timeout: 10), "URL card missing")
        // Allow the 10 ms link preview stub to populate ogTitle and persist ogImageData
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // Reopen overlay so LinkPreviewImageStore-backed urlOGImage is loaded into the card's context menu
        overlay.typeKey(.escape, modifierFlags: [])
        showOverlay()
        let refreshedCard = card(containing: "example.com/article")
        XCTAssertTrue(refreshedCard.waitUntilExists(timeout: 10), "refreshed URL card missing")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        refreshedCard.rightClick()

        let copyItem = app.menuItems["Copy"]
        XCTAssertTrue(copyItem.waitUntilExists(timeout: 5), "Copy menu item missing")
        let copyTitleItem = app.menuItems["Copy Page Title"]
        let copyImageItem = app.menuItems["Copy Preview Image"]
        XCTAssertTrue(copyTitleItem.waitUntilExists(timeout: 5), "Copy Page Title missing")
        XCTAssertTrue(copyImageItem.waitUntilExists(timeout: 5), "Copy Preview Image missing")

        let contextMenu = app.menus.allElementsBoundByIndex.first {
            $0.menuItems["Copy Page Title"].exists
        }
        let titles = (contextMenu ?? app.menus.element(boundBy: max(0, app.menus.count - 1)))
            .menuItems.allElementsBoundByIndex.map(\.title)
        if let copyIndex = titles.firstIndex(of: "Copy"),
           let titleIndex = titles.firstIndex(of: "Copy Page Title"),
           let imageIndex = titles.firstIndex(of: "Copy Preview Image")
        {
            XCTAssertEqual(titleIndex, copyIndex + 1, "Copy Page Title should sit directly under Copy")
            XCTAssertEqual(imageIndex, copyIndex + 2, "Copy Preview Image should sit directly under Copy Page Title")
        } else {
            XCTFail("Expected Copy, Copy Page Title, and Copy Preview Image in menu: \(titles)")
        }
    }
}
