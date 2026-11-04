// SPDX-License-Identifier: MIT
import AppKit
import XCTest

/// The pictures behind the website teaser: settled states of the real shelf on the plain backdrop, taken in the order
/// the film tells its story (one test, so each scene starts from the shelf the scene before left: a copy or a paste
/// moves that clip to the front), attached at 2x as `teaser-<scene>-<nn>@2x` and exported from the result bundle like
/// the marketing pictures.
/// `TEST_RUNNER_PESTO_TEASER_MODE=dark` takes them in dark. Motion is off, so a run gives the same pictures every time;
/// the edit animates between them. What a paste wrote is
/// attached as `teaser-<scene>-paste`, because a paste target cannot be a real app in a UI-test launch.
@MainActor
final class TeaserFramesTests: PestoUITestCase {
    private var backdropWindow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "marketing-backdrop").firstMatch
    }

    private var appearance: String {
        ProcessInfo.processInfo.environment["PESTO_TEASER_MODE"] == "dark" ? "dark" : "light"
    }

    private func start() {
        launch(
            seed: "lunchRush",
            defaults: [
                "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                "linkPreviewsEnabled": "false", "appearanceMode": appearance, "uitestAuthenticationGranted": "true"
            ],
            backdrop: "plain"
        )
        XCTAssertTrue(backdropWindow.waitForExistence(timeout: 10), "the backdrop window never appeared")
    }

    private func settle(_ seconds: TimeInterval = 0.9) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// The shelf's glass takes a moment after it opens to reach its resting tint: a frame taken sooner is yellower than
    /// the ones that follow, and the film would show the shift.
    private func settleGlass() {
        settle(2.6)
    }

    /// The app the next copy is shown as made in (the card on the shelf prints it).
    private func copyFrom(_ bundleID: String, _ text: String) {
        try? bundleID.write(to: workDirectory.appendingPathComponent("copy-source"), atomically: true, encoding: .utf8)
        copyToClipboard(text)
    }

    private func frame(_ scene: String, _ number: Int) {
        let image = backdropWindow.screenshot().image
        let attachment = XCTAttachment(image: image)
        attachment.name = String(format: "teaser-%@-%02d@2x", scene, number)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPaste(_ scene: String) {
        let log = workDirectory.appendingPathComponent("paste-log.jsonl")
        let last = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").last.map(String.init)
        XCTAssertNotNil(last, "nothing was pasted in \(scene)")
        let attachment = XCTAttachment(string: last ?? "")
        attachment.name = "teaser-\(scene)-paste"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func search(_ words: String, frames scene: String, from number: Int) {
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5), "no search field")
        var shown = ""
        var next = number
        for character in words {
            overlay.typeText(String(character))
            shown.append(character)
            if shown.count % 2 == 0 || shown == words {
                settle(0.5)
                frame(scene, next)
                next += 1
            }
        }
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "nothing found for \(words)")
        settle()
    }

    /// The shelf's first frame on its own: the glass is yellower until the focus has moved once (the story's
    /// later frames all follow a move), so the focus goes one card along and back and the frame matches the ones that
    /// follow.
    func test_shelfFirstFrameMatchesTheRest() {
        start()
        showOverlay()
        settleGlass()
        overlay.typeKey(.rightArrow, modifierFlags: [])
        settle(0.6)
        overlay.typeKey(.leftArrow, modifierFlags: [])
        settle(1.4)
        frame("shelf", 1)
    }

    /// The whole story in order. Mamma Mia asks what time she lands; the flight time and the tracking number were
    /// copied, the tracking number last (the seed). Each scene ends with its clip pasted or copied, and the next one
    /// opens on a shelf with that clip first.
    func test_film_story() {
        start()
        shelfScene()
        findScene()
        snippetScene()
        secretScene()
        hideScene()
    }

    private func shelfScene() {
        frame("shelf", 0)
        showOverlay()
        settleGlass()
        frame("shelf", 1)
        overlay.typeKey(.rightArrow, modifierFlags: [])
        settle(0.7)
        frame("shelf", 2)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("shelf")
        showOverlay()
        settleGlass()
        frame("shelf", 3)
    }

    private func findScene() {
        search("gate", frames: "gate", from: 0)
        frame("gate", 9)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("gate")
        showOverlay()
        settleGlass()
        frame("gate", 10)
        overlay.typeKey(.escape, modifierFlags: [])
        settle(0.8)
    }

    private func snippetScene() {
        copyFrom("com.apple.mail", "1Z999AA10123456784")
        settle(2.2)
        showOverlay()
        settleGlass()
        frame("snippet", 0)
        search("order update", frames: "snippet", from: 1)
        frame("snippet", 7)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        XCTAssertFalse(app.windows["Fill in snippet"].exists, "this snippet asks nothing")
        attachPaste("snippet")
        showOverlay()
        settleGlass()
        frame("snippet", 8)
        overlay.typeKey(.escape, modifierFlags: [])
        settle(0.8)
    }

    private func secretScene() {
        copyFrom("com.apple.MobileSMS", "4242 4242 4242 4242")
        settle(2.2)
        showOverlay()
        let masked = card(containing: "4242")
        XCTAssertTrue(masked.waitForExistence(timeout: 10))
        XCTAssertFalse((masked.value as? String ?? "").contains("4242 4242 4242 4242"), "the card must stay masked")
        settleGlass()
        frame("secret", 0)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("secret")
        showOverlay()
        settleGlass()
    }

    private func hideScene() {
        frame("hide", 0)
        send(.toggleHideContents)
        settle(0.35)
        frame("hide", 1)
        settle(1.0)
        frame("hide", 2)
        send(.toggleHideContents)
        settle(1.2)
        frame("hide", 3)
    }
}
