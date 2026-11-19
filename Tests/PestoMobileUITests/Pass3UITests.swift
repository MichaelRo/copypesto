// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The iPhone passes for the Mac features pass 3 brought over: Decode JWT, an AI action, Ask Pesto and a smart
/// collection. The model is a fixture here (`PESTO_UITEST_AI_FIXTURE`): a real one is a hand check.
@MainActor
final class Pass3UITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func card(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_whenAHiddenTokenIsDecoded_thenItsPayloadShowsAndCopyPayloadClosesTheSheet() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch(environment: [
            "PESTO_UITEST_JWT": "1", "PESTO_UITEST_DEFAULT_uitestAuthenticationGranted": "true"
        ])
        let token = card(containing: "108 characters hidden", in: app)
        XCTAssertTrue(token.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Ada Lovelace"].exists, "the token is hidden until it is decoded")

        token.press(forDuration: 1.0)
        let decode = app.buttons["Decode JWT"]
        XCTAssertTrue(decode.waitForExistence(timeout: timeout), "a hidden token's menu offers Decode JWT")
        decode.tap()

        XCTAssertTrue(element(MobileAccessibilityID.decodeJWTSheet, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Not verified: Pesto never checks the signature."].exists)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Ada Lovelace")).firstMatch
                .exists,
            "the payload is readable"
        )
        capture("iphone-decode-jwt")

        element(MobileAccessibilityID.decodeJWTCopyPayload, in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.decodeJWTSheet, in: app).waitForNonExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Ada Lovelace"].exists, "the card stays hidden")
    }

    func test_whenAHiddenTokenIsDecodedWithoutAuthentication_thenNothingOpens() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch(environment: [
            "PESTO_UITEST_JWT": "1", "PESTO_UITEST_DEFAULT_uitestAuthenticationGranted": "false"
        ])
        let token = card(containing: "108 characters hidden", in: app)
        XCTAssertTrue(token.waitForExistence(timeout: timeout))
        token.press(forDuration: 1.0)
        let decode = app.buttons["Decode JWT"]
        XCTAssertTrue(decode.waitForExistence(timeout: timeout))
        decode.tap()
        XCTAssertFalse(element(MobileAccessibilityID.decodeJWTSheet, in: app).waitForExistence(timeout: 2))
    }

    func test_whenAnAIActionRuns_thenItsAnswerIsInASheetWithCopy() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch(environment: ["PESTO_UITEST_AI_FIXTURE": "1"])
        let note = card(containing: "Packing list", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.press(forDuration: 1.0)
        let menu = app.buttons["AI Actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: timeout), "a text clip's menu offers AI Actions")
        menu.tap()
        let summarize = app.buttons["Summarize"]
        XCTAssertTrue(summarize.waitForExistence(timeout: timeout))
        summarize.tap()

        let answer = element(MobileAccessibilityID.aiAnswer, in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: timeout))
        XCTAssertTrue((answer.label).contains("Summary:"), "the fixture model answered: \(answer.label)")
        capture("iphone-ai-result")
        XCTAssertTrue(element(MobileAccessibilityID.aiCopy, in: app).isEnabled)
        element(MobileAccessibilityID.aiDone, in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.aiSheet, in: app).waitForNonExistence(timeout: timeout))
    }

    func test_whenTheModelIsOff_thenAIActionsAreGreyedOutWithTheReason() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch(environment: [
            "PESTO_UITEST_AI_FIXTURE": "1", "PESTO_UITEST_DEFAULT_appleIntelligenceEnabled": "false"
        ])
        let note = card(containing: "Packing list", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.press(forDuration: 1.0)
        let menu = app.buttons["AI Actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: timeout))
        menu.tap()
        let summarize = app.buttons["Summarize"]
        XCTAssertTrue(summarize.waitForExistence(timeout: timeout))
        XCTAssertFalse(summarize.isEnabled)
        XCTAssertTrue(
            app.staticTexts["Turned off in Pesto\u{2019}s settings."].exists
                || app.buttons["Turned off in Pesto\u{2019}s settings."].exists,
            "the reason is said"
        )
    }

    func test_whenAskIsChosen_thenTheSentenceBecomesFilters() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("links today")
        let ask = element(MobileAccessibilityID.askChip, in: app)
        XCTAssertTrue(ask.waitForExistence(timeout: timeout), "words in the field offer Ask")
        ask.tap()

        let asked = element(MobileAccessibilityID.askedChip, in: app)
        XCTAssertTrue(asked.waitForExistence(timeout: timeout), "what Ask found is one chip")
        XCTAssertTrue(asked.label.contains("Links"), "\(asked.label)")
        XCTAssertTrue(card(containing: "copypesto.net", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(card(containing: "Packing list", in: app).exists, "only links remain")
        capture("iphone-ask")

        asked.tap()
        XCTAssertFalse(asked.waitForExistence(timeout: 1), "choosing the chip takes the filters off")
    }

    func test_whenASmartCollectionIsMade_thenItFillsItselfFromItsRule() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        app.buttons["New Collection"].firstMatch.tap()
        let name = element(MobileAccessibilityID.collectionNameField, in: app)
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.typeText("Web")
        app.buttons["Smart"].firstMatch.tap()
        let value = element(MobileAccessibilityID.smartRuleValue, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: timeout), "a smart collection asks for a rule")
        capture("iphone-smart-collection-editor")
        value.tap()
        app.buttons["Link"].firstMatch.tap()
        element(MobileAccessibilityID.saveCollectionButton, in: app).tap()

        let chip = element(MobileAccessibilityID.chipRow, in: app).buttons["Web"]
        XCTAssertTrue(chip.waitForExistence(timeout: timeout))
        XCTAssertTrue(card(containing: "copypesto.net", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(card(containing: "Packing list", in: app).exists, "the rule leaves the notes out")
    }

    func test_whenARuleIsRemoved_thenTheOtherRuleKeepsItsValue() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        app.buttons["New Collection"].firstMatch.tap()
        XCTAssertTrue(element(MobileAccessibilityID.collectionNameField, in: app).waitForExistence(timeout: timeout))
        app.buttons["Smart"].firstMatch.tap()
        let values = app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.smartRuleValue)
        XCTAssertTrue(values.firstMatch.waitForExistence(timeout: timeout))
        values.firstMatch.tap()
        app.buttons["Link"].firstMatch.tap()
        element(MobileAccessibilityID.smartAddRule, in: app).tap()
        XCTAssertEqual(values.count, 2)

        app.buttons["Remove Rule"].firstMatch.tap()

        XCTAssertEqual(values.count, 1, "one rule is left")
        let left = values.firstMatch
        XCTAssertTrue(
            left.label.contains("Text") || (left.value as? String)?.contains("Text") == true,
            "the first rule, Link, went and the second, Text, stayed: \(left.label)"
        )
        XCTAssertFalse(app.buttons["Remove Rule"].exists, "a group keeps its last rule")
    }

    func test_onIPad_anAIActionFromTheInlineDetailShowsOneSheetWithItsAnswer() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch(environment: ["PESTO_UITEST_AI_FIXTURE": "1"])
        let note = card(containing: "Packing list", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.press(forDuration: 1.0)
        let details = app.buttons["Edit Details"]
        XCTAssertTrue(details.waitForExistence(timeout: timeout))
        details.tap()
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout))

        app.buttons["More"].firstMatch.tap()
        let menu = app.buttons["AI Actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: timeout))
        menu.tap()
        let summarize = app.buttons["Summarize"]
        XCTAssertTrue(summarize.waitForExistence(timeout: timeout))
        summarize.tap()

        let answer = element(MobileAccessibilityID.aiAnswer, in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: timeout), "the answer opens")
        XCTAssertTrue(answer.label.contains("Summary:"), answer.label)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.aiSheet).count, 1,
            "one sheet, not one from the library and one from the inspector"
        )
        element(MobileAccessibilityID.aiDone, in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.aiSheet, in: app).waitForNonExistence(timeout: timeout))
    }
}
