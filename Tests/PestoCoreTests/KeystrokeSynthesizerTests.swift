// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import PestoCore

/// Events go to a recording poster, never the system HID tap: the previous test posted a real
/// ⌘V to whatever app was focused whenever the terminal running the tests had Accessibility.
private final class RecordingPoster: EventPosting {
    struct Recorded: Equatable {
        var keyCode: Int64
        var isKeyDown: Bool
        var flags: CGEventFlags
    }

    private let events = Mutex<[Recorded]>([])

    var recorded: [Recorded] {
        events.withLock { $0 }
    }

    func post(_ event: CGEvent) {
        let entry = Recorded(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            isKeyDown: event.type == .keyDown,
            flags: event.flags
        )
        events.withLock { $0.append(entry) }
    }
}

@Suite("KeystrokeSynthesizer")
struct KeystrokeSynthesizerTests {
    @Test("Cmd+V is posted as a V key-down then key-up, both with the command flag")
    func whenSynthesizingCommandV_thenPostsCommandVDownThenUp() throws {
        let poster = RecordingPoster()

        try KeystrokeSynthesizer(poster: poster, keyCodeForV: { 0x09 }).synthesizeCommandV()

        let recorded = poster.recorded
        #expect(recorded.map(\.keyCode) == [0x09, 0x09])
        #expect(recorded.map(\.isKeyDown) == [true, false])
        #expect(recorded.allSatisfy { $0.flags.contains(.maskCommand) })
    }

    @Test("moving the caret back posts a plain left arrow, down then up, once for each character")
    func whenMovingTheCaretBack_thenLeftArrowsArePosted() throws {
        let poster = RecordingPoster()

        try KeystrokeSynthesizer(poster: poster).synthesizeLeftArrows(count: 3)

        let recorded = poster.recorded
        #expect(recorded.count == 6)
        #expect(recorded.allSatisfy { $0.keyCode == 123 })
        #expect(recorded.map(\.isKeyDown) == [true, false, true, false, true, false])
        #expect(recorded.allSatisfy { $0.flags == [] })
    }

    @Test("no arrows are posted for none, and never more than the cap, so a long text cannot flood the app")
    func whenCountIsOutOfRange_thenNothingOrTheCap() throws {
        let none = RecordingPoster()
        try KeystrokeSynthesizer(poster: none).synthesizeLeftArrows(count: 0)
        let many = RecordingPoster()
        try KeystrokeSynthesizer(poster: many).synthesizeLeftArrows(count: 10_000)

        #expect(none.recorded.isEmpty)
        #expect(many.recorded.count == KeystrokeSynthesizer.maxCaretMoves * 2)
    }

    @Test("the key code comes from the layout, not from the ANSI position")
    func whenLayoutMovesV_thenThatKeyCodeIsPosted() throws {
        let poster = RecordingPoster()

        try KeystrokeSynthesizer(poster: poster, keyCodeForV: { 0x28 }).synthesizeCommandV()

        #expect(poster.recorded.map(\.keyCode) == [0x28, 0x28])
    }

    @Test("the key is found by scanning the layout, case-insensitively")
    func whenLayoutMapsCodeToV_thenKeyCodeIsFound() {
        let layout: [CGKeyCode: String] = [0x09: "k", 0x28: "V", 0x0B: "b"]

        #expect(KeyboardLayoutKeyCode.keyCode(for: "v", translating: { layout[$0] }) == 0x28)
        #expect(KeyboardLayoutKeyCode.keyCode(for: "v", translating: { _ in nil }) == nil)
    }

    @Test("the current layout resolves V to a real key code")
    @MainActor
    func whenReadingTheCurrentLayout_thenVResolves() {
        #expect(KeyboardLayoutKeyCode.current(for: "v") != nil)
    }

    @Test("no other modifier flags leak into the paste")
    func whenSynthesizingCommandV_thenOnlyCommandModifierIsSet() throws {
        let poster = RecordingPoster()

        try KeystrokeSynthesizer(poster: poster, keyCodeForV: { 0x09 }).synthesizeCommandV()

        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        #expect(poster.recorded.allSatisfy { $0.flags.isDisjoint(with: modifiers) })
    }

    @Test("when triggered by a hotkey like ⌃⌥⌘V, Tier 2 waits for Control/Option/Shift release before posting ⌘V")
    func whenConflictingHotkeyModifiersAreHeld_thenPasteWaitsForReleaseBeforePostingCommandV() async {
        let checks = Mutex(0)
        let waited = await PasteCoordinator.waitForConflictingModifiersRelease(
            timeout: .seconds(5),
            pollInterval: .milliseconds(1),
            heldModifiers: {
                let count = checks.withLock { value -> Int in
                    value += 1
                    return value
                }
                return count < 4 ? [.maskControl, .maskAlternate, .maskCommand] : [.maskCommand]
            }
        )

        #expect(waited == true)
        #expect(checks.withLock { $0 } == 4)
    }
}
