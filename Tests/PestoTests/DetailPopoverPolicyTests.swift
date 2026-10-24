// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing
@testable import Pesto

@Suite("Card detail popover policy")
struct DetailPopoverPolicyTests {
    private func wants(
        hovered: Bool = false, keyboard: Bool = false, held: Bool = false, suppressed: Bool = false,
        spent: Bool = false
    )
    -> Bool {
        DetailPopoverPolicy.wantsDetail(
            hovered: hovered, keyboardRevealed: keyboard, held: held, suppressed: suppressed, spent: spent
        )
    }

    @Test("a card nobody hovered or navigated to never shows it")
    func whenNothingTargetsTheCard_thenNoDetail() {
        #expect(!wants())
    }

    @Test("hover or a keyboard reveal shows it")
    func whenHoveredOrKeyboardRevealed_thenDetail() {
        #expect(wants(hovered: true))
        #expect(wants(keyboard: true))
    }

    @Test("suppression beats both, so a locked or scrolling shelf shows nothing")
    func whenSuppressed_thenNoDetail() {
        #expect(!wants(hovered: true, keyboard: true, suppressed: true))
    }

    @Test("a popover that has had its turn does not come back until the pointer leaves and returns")
    func whenSpent_thenNoDetail() {
        #expect(!wants(hovered: true, spent: true))
        #expect(!wants(keyboard: true, spent: true))
    }

    @Test("locked, hidden or VoiceOver running suppresses; a visible unlocked shelf does not")
    func whenShelfState_thenSuppression() {
        #expect(DetailPopoverPolicy.isSuppressed(isLocked: true, isShelfVisible: true))
        #expect(DetailPopoverPolicy.isSuppressed(isLocked: false, isShelfVisible: false))
        #expect(DetailPopoverPolicy.isSuppressed(isLocked: false, isShelfVisible: true, voiceOverEnabled: true))
        #expect(!DetailPopoverPolicy.isSuppressed(isLocked: false, isShelfVisible: true))
    }

    @Test("a keyboard reveal belongs to one clip and is gone once cleared")
    func whenRevealIsOneShot_thenOnlyThatClip() {
        let first = UUID()
        let second = UUID()

        #expect(DetailPopoverPolicy.keyboardReveals(itemID: first, revealedID: first))
        #expect(!DetailPopoverPolicy.keyboardReveals(itemID: second, revealedID: first))
        #expect(!DetailPopoverPolicy.keyboardReveals(itemID: first, revealedID: nil))
    }

    @Test("a hovered card stays as long as the pointer is on it; only a keyboard reveal has a safety timeout")
    func whenShown_thenOnlyAForgottenKeyboardRevealTimesOut() {
        #expect(DetailPopoverPolicy.autoCloseDelay(hovered: true) == nil)
        #expect(DetailPopoverPolicy.autoCloseDelay(hovered: false) == .seconds(30))
    }

    @Test("a card the pointer left stays while the pointer is crossing to it or on it")
    func whenHeld_thenDetailOutlastsTheHover() {
        #expect(wants(held: true))
        #expect(!wants(held: true, suppressed: true))
        #expect(!wants(held: true, spent: true))
    }

    @Test("only a card that scrolls waits for the pointer; one with nothing to scroll closes when the pointer leaves")
    func whenPointerLeaves_thenOnlyAScrollingCardWaits() {
        #expect(DetailPopoverPolicy.waitsForPointer(contentScrolls: true))
        #expect(!DetailPopoverPolicy.waitsForPointer(contentScrolls: false))
        #expect(DetailPopoverPolicy.grace == .milliseconds(450))
    }

    @Test("the pointer resting where the shelf opened does not count as hovering a card")
    func whenPointerHasNotMoved_thenHoverIsIgnored() {
        #expect(!DetailPopoverPolicy.hoverCounts(hovered: true, pointerMoved: false))
        #expect(DetailPopoverPolicy.hoverCounts(hovered: true, pointerMoved: true))
        #expect(!DetailPopoverPolicy.hoverCounts(hovered: false, pointerMoved: true))
    }

    @Test("a small jitter is not movement, a real move is")
    func whenPointerJitters_thenNotMoved() {
        let origin = CGPoint(x: 100, y: 100)

        #expect(!DetailPopoverPolicy.pointerMoved(from: origin, to: CGPoint(x: 101, y: 102)))
        #expect(DetailPopoverPolicy.pointerMoved(from: origin, to: CGPoint(x: 110, y: 100)))
    }

    @Test("a card under a pointer that has not moved since the shelf opened does not lift")
    func whenPointerHasNotMoved_thenTheCardUnderItStaysDown() {
        #expect(!DetailPopoverPolicy.isLifted(hovered: true, pointerMoved: false, scrolling: false, focused: false))
        #expect(DetailPopoverPolicy.isLifted(hovered: true, pointerMoved: true, scrolling: false, focused: false))
    }

    @Test("the focused card lifts whatever the pointer does, and a scroll never lifts a hovered one")
    func whenFocusedOrScrolling_thenLiftFollowsFocus() {
        #expect(DetailPopoverPolicy.isLifted(hovered: false, pointerMoved: false, scrolling: false, focused: true))
        #expect(!DetailPopoverPolicy.isLifted(hovered: true, pointerMoved: true, scrolling: true, focused: false))
    }
}
