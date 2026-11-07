// SPDX-License-Identifier: MIT
import AppKit
import XCTest

final class ShelfSurfaceUITests: PestoUITestCase {
    func test_appearance_offersGlassAndSolid_solidIsTheDefault_andChoosingGlassSelectsIt() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let glass = element(AccessibilityID.settingsChoice("shelfSurface", "glass"))
        let solid = element(AccessibilityID.settingsChoice("shelfSurface", "solid"))
        XCTAssertTrue(solid.waitForExistence(timeout: 5), "no Solid tile")
        XCTAssertTrue(glass.exists, "no Glass tile")
        XCTAssertTrue(solid.isSelected, "Solid should be the default")
        capture("settings-shelf-surface-solid", of: settingsWindow)

        glass.click()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: glass)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(solid.isSelected)
        capture("settings-shelf-surface-glass", of: settingsWindow)
    }

    func test_shelf_opensOnEachSurface() {
        for surface in ["solid", "glass"] {
            launch(defaults: ["hasOnboarded": "true", "shelfSurface": surface])
            showOverlay()
            XCTAssertTrue(overlay.waitForExistence(timeout: 5), "the shelf did not open on \(surface)")
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            capture("shelf-\(surface)")
            app.terminate()
        }
    }

    func test_appearance_whenTheSurfaceChanges_thenThePictureOfTheShelfChanges() throws {
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "Reduce Transparency makes both surfaces solid"
        )
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()
        let preview = element(AccessibilityID.settingsPreviewShelf)
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "no picture of the shelf")
        let solidPicture = preview.screenshot().pngRepresentation

        let glass = element(AccessibilityID.settingsChoice("shelfSurface", "glass"))
        glass.click()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: glass)
        waitForExpectations(timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        XCTAssertNotEqual(
            preview.screenshot().pngRepresentation,
            solidPicture,
            "choosing Glass left the picture as it was"
        )
    }
}
