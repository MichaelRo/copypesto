// SPDX-License-Identifier: MIT
import XCTest

final class PanelsAndMenuTests: PestoUITestCase {
    func test_quickMenu_showsTheFiveNewestCards() {
        launch()

        send(.showQuickMenu)

        XCTAssertTrue(
            element(AccessibilityID.quickMenuPanel).waitForExistence(timeout: 10),
            "quick menu did not appear"
        )
        if !cards.firstMatch.waitForExistence(timeout: 10) {
            dumpState("quick-menu-no-cards")
            XCTFail("quick menu shows no cards")
        }
        XCTAssertLessThanOrEqual(cards.count, 5)
        capture("quick-menu", of: element(AccessibilityID.quickMenuPanel))
    }

    func test_quickMenu_selectingACard_pastesIt() {
        launch()
        send(.showQuickMenu)
        XCTAssertTrue(element(AccessibilityID.quickMenuPanel).waitForExistence(timeout: 10))
        let newest = card(containing: "Quarterly report draft")
        XCTAssertTrue(newest.waitForExistence(timeout: 10), "the newest item should be in the quick menu")

        newest.click()

        XCTAssertEqual(waitForPaste(count: 1), ["Quarterly report draft — final review pending."])
    }

    func test_pinnedWindow_togglesOnAndOff() {
        launch()

        send(.togglePinnedWindow)
        XCTAssertTrue(
            element(AccessibilityID.pinnedPanel).waitForExistence(timeout: 10),
            "pinned window did not appear"
        )
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        capture("pinned-window", of: element(AccessibilityID.pinnedPanel))

        send(.togglePinnedWindow)
        waitForNonExistence(element(AccessibilityID.pinnedPanel), timeout: 5, "pinned window should hide")
    }

    func test_pinnedWindow_keepsItsCommandBarBelowTheWindowButtons() {
        launch()

        send(.togglePinnedWindow)
        let panel = element(AccessibilityID.pinnedPanel)
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "pinned window did not appear")
        let allChip = element(AccessibilityID.collectionChip("All"))
        XCTAssertTrue(allChip.waitForExistence(timeout: 10), "the All chip did not appear")

        let titlebarClearance = allChip.frame.minY - panel.frame.minY
        XCTAssertGreaterThanOrEqual(
            titlebarClearance, 28,
            "the traffic lights (about 24 pt tall) are drawn over the command bar"
        )
    }

    func test_statusMenu_listsItsActionsAndShowPestoOpensTheOverlay() {
        launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar item")

        statusItem.click()
        let show = app.menuItems.matching(identifier: "statusShowOverlay").firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5), "status menu did not open")
        XCTAssertTrue(app.menuItems.matching(identifier: "statusOpenSettings").firstMatch.exists)
        show.click()

        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "Show Pesto did not open the overlay")
    }

    func test_statusMenu_quitTerminatesTheApp() {
        launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))

        statusItem.click()
        let quit = app.menuItems.matching(identifier: "statusQuit").firstMatch
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        XCTAssertTrue(quit.isEnabled, "the status menu's Quit Pesto is greyed out")
        quit.click()

        let deadline = Date().addingTimeInterval(8)
        while app.state != .notRunning, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(app.state, .notRunning, "Quit Pesto did not quit (enabled: \(quit.isEnabled))")
    }

    func test_statusItem_saysWhenCapturingIsPaused_andWhenItResumes() {
        launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        XCTAssertFalse("\(statusItem.value ?? "")".contains("paused"))

        statusItem.click()
        let pause = app.menuItems.matching(identifier: "statusToggleCapture").firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(
            "\(statusItem.value ?? "")".contains("Capturing paused"),
            "VoiceOver is not told capture is paused"
        )

        statusItem.click()
        let resume = app.menuItems.matching(identifier: "statusToggleCapture").firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse("\(statusItem.value ?? "")".contains("paused"))
    }
}
