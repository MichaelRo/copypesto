// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("The AI result panel can be used without a mouse")
@MainActor
struct AIResultPanelAccessibilityTests {
    @Test("it can take keyboard focus, and Escape closes it")
    func whenShown_thenKeyAndEscapeCloses() {
        var closed = false
        let panel = AIResultPanel(size: NSSize(width: 200, height: 100), onEscape: { closed = true })

        #expect(panel.canBecomeKey)
        panel.cancelOperation(nil)

        #expect(closed)
    }

    @Test("VoiceOver hears a labelled floating window")
    func whenCreated_thenLabelled() {
        let panel = AIResultPanel(size: NSSize(width: 200, height: 100), onEscape: {})

        #expect(panel.accessibilitySubrole() == .floatingWindow)
        #expect(panel.accessibilityLabel() == "AI result")
    }

    @Test("an error is worded as an error, not only coloured red")
    func whenError_thenTitleSaysFailed() {
        #expect(AIResultTitle.text(action: "Summarize", isError: true) == "Summarize failed")
        #expect(AIResultTitle.text(action: "Summarize", isError: false) == "Summarize")
    }

    @Test("a partly read clip says how much was read, in words a person can check")
    func whenPartial_thenNoteNamesBothNumbers() {
        let note = AIResultTitle.coverageNote(.init(shown: 8688, total: 90_000))

        #expect(note.contains(8688.formatted()))
        #expect(note.contains(90_000.formatted()))
        #expect(note.hasSuffix("characters."))
    }
}
