// SPDX-License-Identifier: MIT
import XCTest

/// The shelf on what a real clipboard holds (`EverydaySeed`: white screenshots, long links, chat, code, a secret), not
/// the pesto-coloured sample clips of the documentation pictures. A design change is judged on these as well, because
/// the sample clips flatter it. Not in the guide: read them in the gate's screenshots (`docs/pictures.md`).
final class EverydayShelfTests: PestoUITestCase {
    private func capture(mode: String, size: String) {
        launch(
            seed: "everyday",
            defaults: ["hasOnboarded": "true", "appearanceMode": mode, "cardSize": size, "shelfSurface": "solid"],
            backdrop: "plain"
        )
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        parkPointer()
        capture("everyday-\(mode)-\(size)")
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        capture("everyday-\(mode)-\(size)-focused")
    }

    func test_everydayClips_lightLarge() {
        capture(mode: "light", size: "large")
    }

    func test_everydayClips_darkLarge() {
        capture(mode: "dark", size: "large")
    }

    func test_everydayClips_lightCompact() {
        capture(mode: "light", size: "compact")
    }

    func test_everydayClips_darkCompact() {
        capture(mode: "dark", size: "compact")
    }
}
