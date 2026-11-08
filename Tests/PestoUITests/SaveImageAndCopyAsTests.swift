// SPDX-License-Identifier: MIT
import XCTest

final class SaveImageAndCopyAsTests: PestoUITestCase {
    private var savedFiles: [String] {
        let folder = workDirectory.appendingPathComponent("Downloads", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    func test_imageCard_menuSavesTheImageToTheSessionsDownloads() {
        launch()
        showOverlay()
        let imageCard = card(containing: "image")
        XCTAssertTrue(imageCard.waitForExistence(timeout: 5), "the seed has image cards")
        imageCard.rightClick()

        let save = app.menuItems["Save Image"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "a picture offers Save Image")
        save.click()

        let deadline = Date().addingTimeInterval(5)
        while savedFiles.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(savedFiles.count, 1, "one file in the session's own Downloads folder")
        XCTAssertTrue(savedFiles.first?.hasPrefix("Pesto picture ") ?? false)
    }

    func test_imageCard_copyWritesBothPNGAndTIFFFlavours() {
        launch()
        showOverlay()
        let imageCard = card(containing: "image")
        XCTAssertTrue(imageCard.waitForExistence(timeout: 5), "the seed has image cards")
        imageCard.rightClick()

        let copy = overlay.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3), "a picture offers Copy")
        copy.click()

        let board = NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)"))
        let deadline = Date().addingTimeInterval(5)
        var hasPNG = false
        var hasTIFF = false
        while !hasPNG || !hasTIFF, Date() < deadline {
            hasPNG = board.data(forType: .png) != nil
            hasTIFF = board.data(forType: .tiff) != nil
            if !hasPNG || !hasTIFF {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTAssertTrue(hasPNG, "image copy writes public.png")
        XCTAssertTrue(hasTIFF, "image copy writes public.tiff for sharp Cocoa rendering")
    }

    func test_textCard_offersNeitherSaveImageNorCopyAs() {
        launch()
        showOverlay()
        let textCard = card(containing: "text")
        XCTAssertTrue(textCard.waitForExistence(timeout: 5))
        textCard.rightClick()
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.menuItems["Save Image"].exists)
        XCTAssertFalse(app.menuItems["Copy As"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_commandS_onATextCardSavesNothing() {
        launch()
        showOverlay()
        let textCard = card(containing: "text")
        XCTAssertTrue(textCard.waitForExistence(timeout: 5))
        textCard.click()
        app.typeKey("s", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(savedFiles.isEmpty)
    }
}
