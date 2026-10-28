// SPDX-License-Identifier: MIT
import XCTest

/// The beats of the website's demo video, "The Lunch Rush", one method each, at a human pace with motion on. Each beat
/// is meant to be screen-recorded (`scripts/record-lunch-rush.sh <beat>`); run on its own it is also a check that the
/// beat still works. A beat starts from a fresh launch of the `lunchRush` seed, so beats can be recorded in any order.
@MainActor
final class LunchRushRecordingTests: PestoUITestCase {
    private func beat(authenticationGranted: Bool = true) {
        let dark = ProcessInfo.processInfo.environment["PESTO_LUNCH_RUSH_MODE"] == "dark"
        launch(
            seed: "lunchRush",
            defaults: [
                "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                "linkPreviewsEnabled": "false", "appearanceMode": dark ? "dark" : "light",
                "uitestAuthenticationGranted": authenticationGranted ? "true" : "false"
            ],
            backdrop: "plain",
            motion: true
        )
        showOverlay()
        pause(1.5)
        capture("lunch-rush-shelf")
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func type(_ text: String, perKey: TimeInterval = 0.12) {
        for character in text {
            overlay.typeText(String(character))
            pause(perKey)
        }
    }

    private var pastes: [String] {
        let log = workDirectory.appendingPathComponent("paste-log.jsonl")
        let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n")
        return lines.map { $0.replacingOccurrences(of: "\\/", with: "/") }
    }

    /// The masked card: Show reveals the number for a moment, and Return pastes the real one.
    func test_a_maskedCardPastesTheRealNumber() {
        beat()
        let masked = card(containing: "4242")
        XCTAssertTrue(masked.waitForExistence(timeout: 10))
        XCTAssertFalse((masked.value as? String ?? "").contains("4242 4242 4242 4242"), "the card must stay masked")
        masked.click()
        pause(1.5)
        masked.rightClick()
        pause(1.0)
        app.menuItems["Show"].click()
        pause(2.0)
        overlay.typeKey(.return, modifierFlags: [])
        pause(1.5)
        XCTAssertTrue(pastes.joined().contains("4242 4242 4242 4242"), "Return pastes the real number: \(pastes)")
    }

    private func search(_ words: String) {
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5))
        type(words)
        pause(1.5)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "nothing found for \(words)")
    }

    private var fillInSheet: XCUIElement {
        app.windows["Fill in snippet"]
    }

    private func fill(_ field: Int, with value: String) {
        let box = fillInSheet.textFields.element(boundBy: field)
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no fill-in field \(field)")
        box.click()
        box.typeKey("a", modifierFlags: .command)
        for character in value {
            box.typeText(String(character))
            pause(0.12)
        }
    }

    private func pasteFilledIn() {
        pause(1.0)
        element(AccessibilityID.fillInPasteButton).click()
        pause(1.5)
    }

    /// The support reply: three fill-ins, filled with a name, a count and the default day.
    func test_b_supportReplyAsksThreeQuestions() {
        beat()
        search("order reply")
        overlay.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(fillInSheet.waitForExistence(timeout: 10), "the fill-in sheet did not open")
        pause(1.0)
        fill(0, with: "Priya")
        fill(1, with: "40")
        pasteFilledIn()
        XCTAssertTrue(
            pastes.joined().contains("Thanks Priya, your order of 40 jars ships Thursday."),
            "the filled-in reply should be pasted: \(pastes)"
        )
    }

    /// The QA answer: one word narrows the crowded shelf to the one clip that answers.
    func test_c_auditFindsTheAnswer() {
        beat()
        search("audit")
        XCTAssertTrue(card(containing: "September audit").waitForExistence(timeout: 10))
        pause(2.0)
        overlay.typeKey(.return, modifierFlags: [])
        pause(1.5)
        XCTAssertTrue(pastes.joined().contains("passed the September audit"), "\(pastes)")
    }

    /// The pinned dev command: it carries its ⌃1 badge and pastes on Return.
    func test_d_pinnedCommandPastes() {
        beat()
        search("restart staging")
        XCTAssertTrue(card(containing: "kubectl").exists)
        pause(2.5)
        overlay.typeKey(.return, modifierFlags: [])
        pause(1.5)
        XCTAssertTrue(pastes.joined().contains("kubectl rollout restart deploy/basil-api -n staging"), "\(pastes)")
    }

    /// The supplier links: the smart collection gathers them, one is pasted.
    func test_e_supplierLinksCollection() {
        beat()
        let chip = element(AccessibilityID.collectionChip("Supplier links"))
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "no Supplier links chip")
        chip.click()
        pause(2.0)
        XCTAssertEqual(cards.count, 4, "the collection holds the four links")
        overlay.typeKey(.rightArrow, modifierFlags: [])
        pause(1.2)
        overlay.typeKey(.rightArrow, modifierFlags: [])
        pause(2.0)
        overlay.typeKey(.return, modifierFlags: [])
        pause(1.5)
        XCTAssertFalse(pastes.isEmpty, "a link should have been pasted")
    }

    /// The agent prompt: two fill-ins, one with a starting value that is typed over.
    func test_f_agentPromptFillsIn() {
        beat()
        search("failing test")
        overlay.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(fillInSheet.waitForExistence(timeout: 10))
        pause(1.0)
        fill(0, with: "parseOrder")
        fill(1, with: "BASIL-12")
        pasteFilledIn()
        XCTAssertTrue(
            pastes.joined().contains("Write a failing test for parseOrder that reproduces BASIL-12."), "\(pastes)"
        )
    }

    /// The finale: six copies land on the shelf one by one, then the six clips are selected and Paste All joins them.
    func test_g_pasteAllJoinsTheIngredients() {
        beat()
        let ingredients = [
            "2 cups basil", "1 cup parmesan", "1/2 cup pine nuts", "1/2 cup olive oil", "2 cloves garlic",
            "a pinch of salt"
        ]
        for ingredient in ingredients {
            copyToClipboard(ingredient)
            pause(2.2)
        }
        XCTAssertTrue(card(containing: "a pinch of salt").waitForExistence(timeout: 10), "the last copy never arrived")
        pause(1.0)
        for _ in 0..<5 {
            overlay.typeKey(.rightArrow, modifierFlags: [])
        }
        pause(1.0)
        for index in 0..<6 {
            overlay.typeKey(.space, modifierFlags: [])
            pause(0.7)
            if index < 5 { overlay.typeKey(.leftArrow, modifierFlags: []) }
            pause(0.5)
        }
        XCTAssertTrue(element(AccessibilityID.pasteAllButton).waitForExistence(timeout: 5))
        pause(2.0)
        element(AccessibilityID.pasteAllButton).click()
        pause(2.0)
        let joined = pastes.joined()
        for ingredient in ingredients {
            XCTAssertTrue(joined.contains(ingredient), "\(ingredient) missing from \(joined)")
        }
    }

    /// The optional beat: a sensitive picture stays covered until Show, then covers itself again after a few seconds.
    func test_h_sensitivePictureShowAndHide() {
        beat()
        overlay.typeKey(.rightArrow, modifierFlags: [])
        pause(0.8)
        let picture = cards.matching(NSPredicate(format: "label CONTAINS %@", "sensitive content")).firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        let center = picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.rightClick()
        pause(1.2)
        app.menuItems["Show"].click()
        pause(6.0)
    }

    /// The theme flip: the same shelf in Basil, Parmesan, Pine nut and Mortar, a couple of seconds each. The app
    /// relaunches for each, so the take is cut from the settled shelves.
    func test_i_fourThemes() {
        for theme in ["basil", "parmesan", "pineNut", "mortar"] {
            if theme != "basil" { app.terminate() }
            launch(
                seed: "lunchRush",
                defaults: [
                    "hasOnboarded": "true", "cardSize": "large", "linkPreviewsEnabled": "false",
                    "appearanceMode": ProcessInfo.processInfo.environment["PESTO_LUNCH_RUSH_MODE"] ?? "light",
                    "appTheme": theme
                ],
                backdrop: "plain",
                motion: true
            )
            showOverlay()
            pause(2.5)
            capture("lunch-rush-theme-\(theme)")
        }
    }

    /// The simple snippet: no questions, so it pastes at once, with no window.
    func test_j_quickSnippetPastesAtOnce() {
        beat()
        search("quick thanks")
        pause(1.5)
        overlay.typeKey(.return, modifierFlags: [])
        pause(1.5)
        XCTAssertTrue(pastes.joined().contains("Thanks, I\u{2019}ll get back to you today."), "\(pastes)")
        XCTAssertFalse(fillInSheet.exists, "a snippet without questions asks nothing")
    }
}
