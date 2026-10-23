// SPDX-License-Identifier: MIT
import XCTest

/// Settings that change what the user sees or does, driven through the real app.
final class SettingsEffectsTests: PestoUITestCase {
    private func firstCardWidth(cardSize: String?) -> CGFloat {
        launch(defaults: ["hasOnboarded": "true"].merging(cardSize.map { ["cardSize": $0] } ?? [:]) { _, new in new })
        showOverlay()
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        return card.frame.width
    }

    func test_compactCardSize_makesNarrowerCardsThanLarge() {
        let compact = firstCardWidth(cardSize: "compact")
        XCTAssertEqual(compact, 160, accuracy: 4, "compact cards should be 160 pt wide")
    }

    func test_largeCardSize_makesLargeCards() {
        let large = firstCardWidth(cardSize: "large")
        XCTAssertEqual(large, 200, accuracy: 4, "large cards should be 200 pt wide")
    }

    func test_aCustomCardWidth_setsTheCardsAndKeepsThemReadable() {
        launch(defaults: ["hasOnboarded": "true", "cardWidth": "150"])
        showOverlay()
        let narrow = cards.firstMatch
        XCTAssertTrue(narrow.waitForExistence(timeout: 5))
        XCTAssertEqual(narrow.frame.width, 150, accuracy: 4)
        capture("cards-narrowest", of: overlay)
    }

    func test_theWidthSlider_showsTheStoredWidth() {
        launch(defaults: ["hasOnboarded": "true", "cardWidth": "170"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let slider = element(AccessibilityID.settingsChoice("cardWidth", "slider"))
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no width slider in Appearance")
        XCTAssertEqual(slider.normalizedSliderPosition, (170 - 160) / 80.0, accuracy: 0.03)
        capture("settings-card-width-slider", of: settingsWindow)
    }

    func test_pinnedWindow_pastesOnTapWhenAutoPasteIsOn() {
        launch(defaults: ["hasOnboarded": "true", "pinnedWindowAutoPaste": "true"])
        send(.togglePinnedWindow)
        XCTAssertTrue(element(AccessibilityID.pinnedPanel).waitForExistence(timeout: 10))
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 10))

        target.click()

        XCTAssertEqual(waitForPaste(count: 1), ["Quarterly report draft — final review pending."])
    }

    func test_pinnedWindow_onlyCopiesOnTapWhenAutoPasteIsOff() {
        launch(defaults: ["hasOnboarded": "true", "pinnedWindowAutoPaste": "false"])
        send(.togglePinnedWindow)
        XCTAssertTrue(element(AccessibilityID.pinnedPanel).waitForExistence(timeout: 10))
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 10))

        target.click()
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        XCTAssertEqual(pastedTexts(), [], "with auto-paste off a tap must not paste")
    }

    /// The context menu's Copy went through `NSApp.delegate as? AppDelegate`, which is nil in a SwiftUI app, so it
    /// silently did nothing.
    func test_contextMenuCopy_putsTheCardOnTheClipboard() {
        launch()
        showOverlay()
        let target = card(containing: "Team lunch")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.rightClick()
        let cardMenu = app.menus.containing(.menuItem, identifier: "Mark as Sensitive").firstMatch
        XCTAssertTrue(cardMenu.waitForExistence(timeout: 5), "the card's context menu did not open")
        cardMenu.menuItems["Copy"].firstMatch.click()

        let board = NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)"))
        let deadline = Date().addingTimeInterval(5)
        while board.string(forType: .string) != "Team lunch is at 12:30 on Thursday, booked under Alex.",
              Date() < deadline
        {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(board.string(forType: .string), "Team lunch is at 12:30 on Thursday, booked under Alex.")
    }

    /// The size slider in Settings changes the real cards: its smallest position is the Small size.
    func test_cardSizeSlider_resizesTheShelfCards() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let slider = element(AccessibilityID.settingsChoice("cardWidth", "slider"))
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no card size slider")
        slider.adjust(toNormalizedSliderPosition: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        capture("settings-appearance-slider", of: settingsWindow)

        showOverlay()
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.width, 160, accuracy: 4, "the slider's smallest position should give Small cards")
    }
}
