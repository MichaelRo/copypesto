// SPDX-License-Identifier: MIT
import AppKit
import XCTest

/// The pictures behind the website teaser: settled states of the real shelf on the plain backdrop, one scene per
/// method, attached at 2x as `teaser-<scene>-<nn>@2x` and exported from the result bundle like the marketing pictures.
/// `TEST_RUNNER_PESTO_TEASER_MODE=dark` takes them in dark. Motion is off, so a run gives the same pictures every time; the edit animates between them. What a paste wrote is
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

    /// Scene 2: the backdrop, then the shelf open on the newest clips.
    func test_scene2_shelfOpens() {
        start()
        frame("shelf", 0)
        showOverlay()
        settle()
        frame("shelf", 1)
    }

    /// Scene 3: a tracking number is copied, then the order update snippet fills itself in and pastes, with no window.
    func test_scene3_snippetFillsItself() {
        start()
        copyToClipboard("1Z999AA10123456784")
        settle(2.2)
        showOverlay()
        settle()
        frame("snippet", 0)
        search("order update", frames: "snippet", from: 1)
        frame("snippet", 7)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        XCTAssertFalse(app.windows["Fill in snippet"].exists, "this snippet asks nothing")
        attachPaste("snippet")
    }

    /// Scene 4: a word narrows the shelf to the one clip, and Return pastes it.
    func test_scene4_searchFindsFlight() {
        start()
        showOverlay()
        settle()
        frame("search", 0)
        search("flight", frames: "search", from: 1)
        frame("search", 4)
        overlay.typeKey(.return, modifierFlags: [])
        settle(1.5)
        attachPaste("search")
    }

    /// Scene 5: the masked card, Show, then Hide.
    func test_scene5_secretShowAndHide() {
        start()
        showOverlay()
        let masked = card(containing: "4242")
        XCTAssertTrue(masked.waitForExistence(timeout: 10))
        XCTAssertFalse((masked.value as? String ?? "").contains("4242 4242 4242 4242"), "the card must stay masked")
        masked.click()
        settle()
        frame("secret", 0)
        masked.rightClick()
        settle(1.0)
        frame("secret", 1)
        app.menuItems["Show"].click()
        settle(1.2)
        frame("secret", 2)
        masked.rightClick()
        settle(1.0)
        app.menuItems["Hide"].click()
        settle(1.2)
        frame("secret", 3)
    }

    /// Scene 6: six clips of six kinds are selected one after the other, ready to paste one by one.
    func test_scene6_sixKindsSelected() {
        start()
        showOverlay()
        settle()
        frame("stack", 0)
        overlay.typeKey(.rightArrow, modifierFlags: [])
        settle()
        for index in 0..<6 {
            overlay.typeKey(.space, modifierFlags: [])
            settle(0.7)
            frame("stack", index + 1)
            if index < 5 { overlay.typeKey(.rightArrow, modifierFlags: []) }
            settle(0.5)
        }
        let oneByOne = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Paste One by One")).firstMatch
        XCTAssertTrue(oneByOne.waitForExistence(timeout: 5), "no Paste One by One in the selection bar")
        XCTAssertFalse(element(AccessibilityID.pasteAllButton).exists, "mixed kinds cannot be joined as text")
        settle(1.0)
        frame("stack", 7)
    }
}
