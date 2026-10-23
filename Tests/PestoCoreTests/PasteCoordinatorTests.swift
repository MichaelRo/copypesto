// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

// NOTE on paste timing
// --------------------
// The overlay hide animation takes 200 ms; `orderOut` fires in the CATransaction
// completion block afterward. Until `orderOut` fires, the overlay panel IS the key
// window. A CGEvent posted before `orderOut` is delivered to the overlay (eaten
// silently), not the target application. AppDelegate.handleOverlayHidden() therefore
// waits 250 ms before calling executePaste(). This invariant is tested at the
// integration level (XCUITest PasteCoverage), not here.

@Suite("PasteCoordinator")
@MainActor
struct PasteCoordinatorTests {
    @Test("whenNoFocusTarget_thenRequiresManualPaste")
    func whenNoFocusTarget_thenRequiresManualPaste() async {
        // FocusRestoration.capture() is never called, so capturedTarget is nil.
        // activate() returns false → executePaste returns .requiresManualPaste.
        let coordinator = PasteCoordinator()
        let outcome = await coordinator.executePaste(payload: .nonText)
        #expect(outcome == .requiresManualPaste)
    }

    @Test("whenNonTextPayload_thenNeverWrittenViaAccessibility")
    func whenNonTextPayload_thenNeverWrittenViaAccessibility() async {
        // Tier 1 (AX direct write) is only attempted for .text payloads, never .nonText.
        let coordinator = PasteCoordinator()
        let outcome = await coordinator.executePaste(payload: .nonText)
        #expect(outcome != .writtenViaAccessibility)
    }

    @Test("whenTextPayload_andNoFocusTarget_thenRequiresManualPaste")
    func whenTextPayload_andNoFocusTarget_thenRequiresManualPaste() async {
        // Both Tier 1 and Tier 2 require a captured focus target to activate.
        // With no target, the coordinator immediately returns .requiresManualPaste.
        let coordinator = PasteCoordinator()
        let outcome = await coordinator.executePaste(payload: .text("hello"))
        #expect(outcome == .requiresManualPaste)
    }

    @Test("whenRecorderConfigured_thenPayloadIsRecordedAndNothingIsPasted")
    func whenRecorderConfigured_thenPayloadIsRecordedAndNothingIsPasted() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-paste-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = PasteRecorder(directory: directory)
        // No focus target was captured: without the recorder this would return .requiresManualPaste.
        let coordinator = PasteCoordinator(recorder: recorder)

        let outcome = await coordinator.executePaste(payload: .text("hello"))

        #expect(outcome == .writtenViaAccessibility)
        #expect(recorder.entries().map(\.text) == ["hello"])
    }

    // MARK: - Tier 2 needs permission to post keystrokes

    //
    // Without Accessibility, macOS silently drops synthetic ⌘V. The coordinator used to report success anyway, so the
    // manual-paste toast never appeared and nothing was pasted.

    @Test(
        "text is written directly into the focused field up to a size, and rich text or a larger clip is pasted with ⌘V"
    )
    func directWrite_isForTextThatTheFieldCanTakeQuickly() {
        #expect(PasteCoordinator.usesDirectWrite(for: .text("a short line")))
        #expect(PasteCoordinator.usesDirectWrite(for: .text(String(repeating: "a", count: 50_000))))
        #expect(!PasteCoordinator.usesDirectWrite(for: .text(String(repeating: "a", count: 300_000))))
        #expect(!PasteCoordinator.usesDirectWrite(for: .richText("formatted line")))
        #expect(!PasteCoordinator.usesDirectWrite(for: .nonText))
    }

    @Test("without permission to post keystrokes the paste falls back to manual and posts nothing")
    func keystrokeTier_withoutPermission_requiresManualPaste() {
        var posted = false

        let outcome = PasteCoordinator.keystrokeTier(canPost: false, targetIsFrontmost: true) { posted = true }

        #expect(outcome == .requiresManualPaste)
        #expect(!posted, "no ⌘V may be posted without permission")
    }

    @Test("with permission the keystroke is posted and reported as written")
    func keystrokeTier_withPermission_postsAndSucceeds() {
        var posted = false

        let outcome = PasteCoordinator.keystrokeTier(canPost: true, targetIsFrontmost: true) { posted = true }

        #expect(outcome == .writtenViaKeystroke)
        #expect(posted)
    }

    @Test("a failed keystroke falls back to manual paste")
    func keystrokeTier_whenPostingFails_requiresManualPaste() {
        struct Boom: Error {}

        let outcome = PasteCoordinator.keystrokeTier(canPost: true, targetIsFrontmost: true) { throw Boom() }

        #expect(outcome == .requiresManualPaste)
    }

    @Test("a paste cancelled during the Accessibility attempt posts no keystroke")
    func keystrokeTier_whenCancelled_requiresManualPaste() {
        var posted = false

        let outcome = PasteCoordinator.keystrokeTier(canPost: true, targetIsFrontmost: true, isCancelled: true) {
            posted = true
        }

        #expect(outcome == .requiresManualPaste)
        #expect(!posted, "a cancelled paste, after sleep or a lock, must not type into whatever is open now")
    }

    @Test("when another app came to the front during the settle delay, no keystroke is posted to it")
    func keystrokeTier_whenTargetLostTheFront_requiresManualPaste() {
        var posted = false

        let outcome = PasteCoordinator.keystrokeTier(canPost: true, targetIsFrontmost: false) { posted = true }

        #expect(outcome == .requiresManualPaste)
        #expect(!posted, "a clip, possibly a secret, must not be typed into the wrong app")
    }

    @Test("outcomes_areExhaustivelyHandled")
    func outcomes_areExhaustivelyHandled() {
        // Compiler-enforced exhaustiveness: if a new Outcome case is added,
        // this switch won't compile, forcing the author to handle all paths in
        // callers (AppDelegate.handleOverlayHidden etc.).
        let outcome = PasteCoordinator.Outcome.requiresManualPaste
        switch outcome {
        case .writtenViaAccessibility: break
        case .writtenViaKeystroke: break
        case .requiresManualPaste: break
        }
        #expect(true)
    }

    @Test("the caret moves back only after a paste that happened, into the app that got it, with a place to go")
    func shouldMoveCaret_needsAPasteAnAppAndAnOffset() {
        func decide(
            _ outcome: PasteCoordinator.Outcome = .writtenViaKeystroke, offset: Int? = 5, cancelled: Bool = false,
            frontmost: Bool = true, canPost: Bool = true
        )
        -> Bool {
            PasteCoordinator.shouldMoveCaret(
                outcome: outcome, offset: offset, isCancelled: cancelled, targetIsFrontmost: frontmost, canPost: canPost
            )
        }

        #expect(decide())
        #expect(!decide(.writtenViaAccessibility))
        #expect(!decide(.requiresManualPaste))
        #expect(!decide(offset: nil))
        #expect(!decide(offset: 0))
        #expect(!decide(cancelled: true))
        #expect(!decide(frontmost: false))
        #expect(!decide(canPost: false))
    }
}
