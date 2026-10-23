// SPDX-License-Identifier: MIT
import AppKit
import XCTest

/// A stack pastes its first clip when the shelf closes and then one clip for each ⌘V the person presses (ADR 0009):
/// Pesto makes the next clip ready on the pasteboard. The key monitor is not installed under test, so
/// `UITestCommand.stackUserPaste` stands in for the person's ⌘V.
final class StackPasteTests: PestoUITestCase {
    private func boardText() -> String? {
        NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)")).string(forType: .string)
    }

    private func waitForBoard(toDifferFrom previous: String, timeout: TimeInterval = 8) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = boardText(), text != previous, !text.isEmpty { return text }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    private func selectFirstThreeCards() {
        overlay.typeKey(.space, modifierFlags: [])
        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.space, modifierFlags: [])
        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.space, modifierFlags: [])
    }

    func test_stack_pastesTheFirstClip_thenMakesEachNextOneReady() throws {
        launch()
        showOverlay()
        selectFirstThreeCards()

        element(AccessibilityID.pasteOneByOneButton).click()

        let pasted = waitForPaste(count: 1)
        let first = try XCTUnwrap(pasted.first, "the stack did not paste its first clip when the shelf closed")
        XCTAssertTrue(
            app.staticTexts["Pasting 2/3"].waitForExistence(timeout: 8),
            "the HUD should say which clip is next"
        )
        let second = try XCTUnwrap(waitForBoard(toDifferFrom: first), "the second clip was not made ready")

        send(.stackUserPaste)
        let third = try XCTUnwrap(waitForBoard(toDifferFrom: second), "the third clip was not made ready")
        XCTAssertNotEqual(third, first)
        XCTAssertTrue(app.staticTexts["Pasting 3/3"].waitForExistence(timeout: 8))

        send(.stackUserPaste)
        XCTAssertTrue(
            app.staticTexts["All pasted"].waitForExistence(timeout: 8),
            "the last ⌘V should finish the stack"
        )
        XCTAssertEqual(pastedTexts().count, 1, "only the first clip is pasted by Pesto itself")
    }

    func test_cancelOnTheHUD_endsTheStack() {
        launch()
        showOverlay()
        selectFirstThreeCards()
        element(AccessibilityID.pasteOneByOneButton).click()
        XCTAssertTrue(app.staticTexts["Pasting 2/3"].waitForExistence(timeout: 8))

        element(AccessibilityID.stackCancelButton).click()

        waitForNonExistence(app.staticTexts["Pasting 2/3"], timeout: 5, "Cancel should dismiss the stack HUD")
    }
}
