// SPDX-License-Identifier: MIT
import AppKit
import XCTest

final class BackdropContrastUITests: PestoUITestCase {
    private func luminance(of image: NSImage, at point: CGPoint) -> Double? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let color = rep.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB) else
        {
            return nil
        }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    private func assertShelfEdgeSeparation(in screenshot: XCUIScreenshot, step: String) {
        let image = screenshot.image
        let size = image.size
        XCTAssertGreaterThan(size.width, 20)
        XCTAssertGreaterThan(size.height, 20)

        let centerLum = luminance(of: image, at: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
        let edgeLum = luminance(of: image, at: CGPoint(x: size.width * 0.5, y: 2))
        guard let centerLum, let edgeLum else {
            XCTFail("could not sample luminance for \(step)")
            return
        }
        // Shelf must never collapse to an invisible pure-white/black void and must maintain visible bounds.
        XCTAssertGreaterThanOrEqual(centerLum, 0.0, "invalid center luminance for \(step)")
        XCTAssertLessThanOrEqual(centerLum, 1.0, "invalid center luminance for \(step)")
        if step.contains("-solid-") {
            XCTAssertGreaterThan(
                abs(centerLum - edgeLum), 0.002,
                "solid shelf edge should separate from interior for \(step) (center=\(centerLum), edge=\(edgeLum))"
            )
        }
    }

    func test_whenRenderingSolidAndGlassAcrossBackdropsThemesAndAppearances_thenContrastAndEdgeHold() {
        let themes = ["basil", "parmesan", "pineNut", "mortar"]
        let backdrops = ["white", "busy"]
        let surfaces = ["solid", "glass"]

        for backdrop in backdrops {
            for surface in surfaces {
                for theme in themes {
                    for appearance in ["light", "dark"] {
                        launch(
                            defaults: [
                                "hasOnboarded": "true",
                                "shelfSurface": surface,
                                "appTheme": theme,
                                "appearanceMode": appearance
                            ],
                            backdrop: backdrop
                        )
                        showOverlay()
                        let step = "\(backdrop)-\(surface)-\(theme)-\(appearance)"
                        capture(step)
                        captureScreen("\(step)-screen")
                        assertShelfEdgeSeparation(in: overlay.screenshot(), step: step)
                        app.terminate()
                    }
                }
            }
        }
    }

    func test_whenReduceTransparencyIsEnabled_thenGlassFallsBackToSolid() throws {
        try XCTSkipIf(
            !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "System Reduce Transparency is off"
        )
        launch(defaults: ["hasOnboarded": "true", "shelfSurface": "glass"], backdrop: "busy")
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let glassTile = element(AccessibilityID.settingsChoice("shelfSurface", "glass"))
        XCTAssertTrue(glassTile.waitUntilExists(timeout: 5))
        XCTAssertFalse(glassTile.isEnabled, "Glass tile should be disabled under Reduce Transparency")
    }
}
