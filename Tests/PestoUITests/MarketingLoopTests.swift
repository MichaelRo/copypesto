// SPDX-License-Identifier: MIT
import AppKit
import XCTest

/// The frames behind the website's scenes and the launch videos. A scene is a few pictures of the real shelf, each held for
/// a time, in order, and ending where it began (the first and last frames hold a second, so a loop does not jump). Motion is
/// off in a UI-test launch, so each frame is a settled state and a run gives the same frames every time, with no screen
/// recording and no permission to grant. The website plays the frames by scroll (no autoplay, so no pause button is needed);
/// `scripts/encode-marketing-loops.sh` joins them into MP4, WebM and GIF for the README, the launch posts and the press kit.
/// A frame is attached as `loop-<scene>-<mode>-<nn>-<hold in ms>@2x`.
@MainActor
final class MarketingLoopTests: PestoUITestCase {
    private let frameSize = CGSize(width: 1200, height: 400)

    private var backdropWindow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "marketing-backdrop").firstMatch
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func inBothAppearances(_ scene: (String) throws -> Void) throws {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            launch(
                seed: "marketing",
                defaults: [
                    "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                    "linkPreviewsEnabled": "false", "appearanceMode": mode
                ],
                backdrop: "plain"
            )
            XCTAssertTrue(backdropWindow.waitForExistence(timeout: 10), "the backdrop window never appeared")
            try scene(mode)
        }
    }

    /// One frame: the bottom strip of the backdrop, which holds the shelf and the hover card above it.
    private func frame(_ scene: String, _ mode: String, _ number: Int, holdMilliseconds: Int) {
        let backdrop = backdropWindow.frame
        let width = min(frameSize.width, backdrop.width)
        let height = min(frameSize.height, backdrop.height)
        let region = CGRect(x: backdrop.minX, y: backdrop.maxY - height, width: width, height: height)
        let image = backdropWindow.screenshot().image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("no pixels for \(scene) \(number)")
        }
        let scale = CGFloat(cgImage.width) / backdrop.width
        let pixels = CGRect(
            x: ((region.minX - backdrop.minX) * scale).rounded(),
            y: ((region.minY - backdrop.minY) * scale).rounded(),
            width: (region.width * scale).rounded(), height: (region.height * scale).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: pixels) else { return XCTFail("could not crop \(scene) \(number)") }
        let attachment = XCTAttachment(image: NSImage(cgImage: cropped, size: .zero))
        attachment.name = String(format: "loop-%@-%@-%02d-%d@2x", scene, mode, number, holdMilliseconds)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Copy, ⌘⇧V, Return: the shelf opens, a few letters narrow it to one clip, Return pastes it and the shelf goes.
    func test_findAndPaste() throws {
        try inBothAppearances { mode in
            frame("find", mode, 0, holdMilliseconds: 1000)
            showOverlay()
            parkPointer()
            settle()
            frame("find", mode, 1, holdMilliseconds: 1300)
            element(AccessibilityID.searchButton).click()
            XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5), "no search field")
            overlay.typeText("g")
            settle()
            frame("find", mode, 2, holdMilliseconds: 500)
            overlay.typeText("arlic")
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
            settle(1.2)
            frame("find", mode, 3, holdMilliseconds: 1600)
            overlay.typeKey(.return, modifierFlags: [])
            settle(1.2)
            frame("find", mode, 4, holdMilliseconds: 1000)
        }
    }

    /// The hidden card: the arrow keys reach the card number, its hover card opens and still says it is hidden.
    func test_secretStaysMasked() throws {
        try inBothAppearances { mode in
            showOverlay()
            parkPointer()
            settle()
            frame("secret", mode, 0, holdMilliseconds: 1000)
            for _ in 0..<8 { overlay.typeKey(.rightArrow, modifierFlags: []) }
            settle(1.4)
            frame("secret", mode, 1, holdMilliseconds: 2600)
            overlay.typeKey(.escape, modifierFlags: [])
            settle(1.0)
            frame("secret", mode, 2, holdMilliseconds: 1000)
        }
    }
}
