// SPDX-License-Identifier: MIT
import AppKit
import XCTest

/// The pictures behind the website teaser: settled states of the real shelf on the plain backdrop, taken in the order
/// the film tells its story (one test, so each scene starts from the shelf the scene before left: a copy or a paste
/// moves that clip to the front), attached at 2x as `teaser-<scene>-<nn>@2x` and exported from the result bundle like
/// the marketing pictures. Beside each picture goes `teaser-<scene>-<nn>-layout`: where every card of the row is, so
/// the film can cut the cards out of the picture and move them from one state to the next.
/// `TEST_RUNNER_PESTO_TEASER_MODE=dark` takes them in dark. Motion is off, so a run gives the same pictures every time;
/// the edit animates between them. What a paste wrote is
/// attached as `teaser-<scene>-paste`, because a paste target cannot be a real app in a UI-test launch.
@MainActor
final class TeaserFramesTests: PestoUITestCase {
    /// How the film tells one state's card from the next state's: a clip keeps its spoken label when it moves, but a
    /// covered card speaks differently, so states that only cover the row in place go by position.
    private enum CardKey: String {
        case label, position
    }

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

    /// One state of the shelf: its picture and where its cards are.
    private func frame(_ scene: String, _ number: Int, cardsBy key: CardKey = .label) {
        let attachment = XCTAttachment(image: backdropWindow.screenshot().image)
        attachment.name = String(format: "teaser-%@-%02d@2x", scene, number)
        attachment.lifetime = .keepAlways
        add(attachment)
        layout(scene, number, cardsBy: key)
    }

    /// Card frames are the row's own layout, in the backdrop's points: the lift and the ring of the focused card are
    /// not in them, and the importer finds that card in the picture.
    private func layout(_ scene: String, _ number: Int, cardsBy key: CardKey) {
        let backdrop = backdropWindow.frame
        let row: [[String: Any]] = cards.allElementsBoundByIndex.filter(\.exists).map { card in
            let frame = card.frame
            return [
                "label": card.label,
                "x": frame.minX - backdrop.minX, "y": frame.minY - backdrop.minY,
                "width": frame.width, "height": frame.height
            ]
        }
        let body: [String: Any] = [
            "backdrop": ["width": backdrop.width, "height": backdrop.height], "cardsBy": key.rawValue, "cards": row
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
            attachment.name = String(format: "teaser-%@-%02d-layout", scene, number)
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("no layout for \(scene) \(number): \(error)")
        }
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

    /// Opens search (one frame) and types the word, a frame after every letter, so the film shows the row thinning.
    private func search(_ words: String, frames scene: String, from number: Int) {
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5), "no search field")
        settle(0.6)
        frame(scene, number)
        for (index, character) in words.enumerated() {
            overlay.typeText(String(character))
            settle(0.6)
            frame(scene, number + 1 + index)
        }
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "nothing found for \(words)")
    }

    /// The whole story in order. Mamma Mia asks what time she lands; the flight time and the tracking number were
    /// copied, the tracking number last (the seed). Each scene ends with its clip pasted, and the next one opens on a
    /// shelf with that clip first.
    func test_film_story() {
        start()
        shelfScene()
        findScene()
        secretScene()
        hideScene()
    }

    private func shelfScene() {
        showOverlay()
        settleGlass()
        // The ground keeps a different tint until the focus has moved once: along and back before the first frame.
        overlay.typeKey(.rightArrow, modifierFlags: [])
        settle(0.6)
        overlay.typeKey(.leftArrow, modifierFlags: [])
        settle(1.4)
        frame("shelf", 1)
        overlay.typeKey(.rightArrow, modifierFlags: [])
        settle(0.7)
        frame("shelf", 2)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("shelf")
    }

    private func findScene() {
        showOverlay()
        settleGlass()
        frame("gate", 0)
        search("gate", frames: "gate", from: 1)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("gate")
    }

    /// The card number is copied while the shelf is open, so the film has the row before and after it lands.
    private func secretScene() {
        showOverlay()
        settleGlass()
        frame("secret", 0)
        copyFrom("com.apple.MobileSMS", "5555 5555 5555 4444")
        let masked = card(containing: "4444")
        XCTAssertTrue(masked.waitForExistence(timeout: 10))
        XCTAssertFalse((masked.value as? String ?? "").contains("5555"), "the card must stay masked")
        XCTAssertFalse(masked.label.contains("5555"), "the card must stay masked")
        settleGlass()
        frame("secret", 1)
        masked.doubleClick()
        settle(1.5)
        attachPaste("secret")
    }

    private func hideScene() {
        showOverlay()
        settleGlass()
        frame("hide", 0, cardsBy: .position)
        send(.toggleHideContents)
        settle(1.2)
        frame("hide", 1, cardsBy: .position)
        send(.toggleHideContents)
        settle(1.2)
        frame("hide", 2, cardsBy: .position)
    }
}
