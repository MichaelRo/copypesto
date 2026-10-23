// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Testing
@testable import PestoCore

@Suite("Recording a global shortcut")
struct HotkeyRecordingTests {
    private let command = UInt32(cmdKey)
    private let shift = UInt32(shiftKey)
    private let option = UInt32(optionKey)
    private let control = UInt32(controlKey)
    private let keyV = kVK_ANSI_V

    @Test("global shortcuts are paused while a recorder listens, so the combination in use can be recorded again")
    func whenRecorderBegins_thenShortcutsPauseOnceAndResumeWhenItEnds() {
        var suspension = GlobalHotkeySuspension()

        let paused = suspension.begin()
        #expect(paused, "the first recorder pauses the shortcuts")
        #expect(suspension.isSuspended)
        let resumed = suspension.end()
        #expect(resumed, "the last one to finish resumes them")
        #expect(!suspension.isSuspended)
    }

    @Test("two recorders that overlap pause once and resume only when both are done")
    func whenRecordersOverlap_thenResumeWaitsForTheLast() {
        var suspension = GlobalHotkeySuspension()

        let first = suspension.begin()
        let second = suspension.begin()
        let firstEnd = suspension.end()
        #expect(first)
        #expect(!second, "already paused")
        #expect(!firstEnd, "one is still recording")
        #expect(suspension.isSuspended)
        let lastEnd = suspension.end()
        #expect(lastEnd)
        #expect(!suspension.isSuspended)
    }

    @Test("an end with no begin changes nothing, so a recorder that disappears twice cannot resume early")
    func whenEndHasNoBegin_thenNothingHappens() {
        var suspension = GlobalHotkeySuspension()

        let stray = suspension.end()
        #expect(!stray)
        #expect(!suspension.isSuspended)
        let next = suspension.begin()
        #expect(next, "and the next real recording still pauses")
    }

    @Test("a recorded combination that the policy accepts is taken")
    func whenCombinationIsFine_thenAccepted() {
        let outcome = HotkeyRecording.evaluate(keyCode: keyV, modifiers: command | shift, others: [])

        #expect(outcome == .accepted)
    }

    @Test("Shift alone is not a shortcut, and neither is Command with a system editing key")
    func whenCombinationIsUnsafe_thenRefusedWithAReason() {
        #expect(HotkeyRecording.evaluate(keyCode: keyV, modifiers: shift, others: []) == .needsModifier)
        #expect(HotkeyRecording.evaluate(keyCode: kVK_ANSI_C, modifiers: command, others: []) == .reservedBySystem)
    }

    @Test("a combination another Pesto shortcut already uses is refused, naming that shortcut")
    func whenAnotherPestoShortcutHasIt_thenClash() {
        let others = [
            NamedHotkey(name: "Paste the previous clip", keyCode: keyV, modifiers: command | option)
        ]

        #expect(
            HotkeyRecording.evaluate(keyCode: keyV, modifiers: command | option, others: others)
                == .clash("Paste the previous clip")
        )
        #expect(HotkeyRecording.evaluate(keyCode: keyV, modifiers: command | shift, others: others) == .accepted)
    }

    @Test("Control with a digit belongs to the pinned clip shortcuts")
    func whenControlAndADigit_thenItClashesWithThePinnedSlots() {
        let outcome = HotkeyRecording.evaluate(keyCode: kVK_ANSI_3, modifiers: control, others: [])

        #expect(outcome == .clash("Pinned clip shortcuts"))
        #expect(
            HotkeyRecording.evaluate(keyCode: kVK_ANSI_3, modifiers: control | option, others: []) == .accepted
        )
    }

    @Test("only the four modifier bits count when two combinations are compared")
    func whenExtraBitsAreSet_thenTheyAreIgnored() {
        let others = [NamedHotkey(name: "Open the shelf", keyCode: keyV, modifiers: command | shift)]
        let withNoise = command | shift | 0x10000

        #expect(HotkeyRecording
            .evaluate(keyCode: keyV, modifiers: withNoise, others: others) == .clash("Open the shelf"))
    }
}
