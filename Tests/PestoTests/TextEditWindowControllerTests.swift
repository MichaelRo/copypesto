// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The one Edit Text window and its draft", .serialized)
    @MainActor
    struct TextEditWindowControllerTests {
        private let state = AppState()

        private func controller(closed: @escaping () -> Void = {}) -> TextEditWindowController {
            TextEditWindowController(appState: state, present: { _ in }, didClose: closed)
        }

        @Test("opening makes one titled, resizable window that the controller keeps and AppKit does not release")
        func whenOpened_thenOneRetainedWindow() throws {
            let editor = controller()
            let id = UUID()

            editor.open(clipID: id, text: "hello", isMonospaced: true)

            let window = try #require(editor.window)
            #expect(window.title == "Edit Text")
            #expect(window.identifier?.rawValue == AccessibilityID.textEditWindow)
            #expect(window.styleMask.contains(.resizable))
            #expect(window.styleMask.contains(.titled))
            #expect(!window.isReleasedWhenClosed)
            #expect(window.contentView is SafeHostingView)
            #expect(editor.model?.clipID == id)
            #expect(editor.model?.draft == "hello")
            #expect(editor.model?.isMonospaced == true)
            editor.close()
        }

        @Test("asking for another clip with nothing typed gives the same window the new clip")
        func whenOpenedAgainUntouched_thenTheSameWindowTakesTheNewClip() throws {
            let editor = controller()
            editor.open(clipID: UUID(), text: "first", isMonospaced: false)
            let window = try #require(editor.window)
            let second = UUID()

            editor.open(clipID: second, text: "second", isMonospaced: false)

            #expect(editor.window === window)
            #expect(editor.model?.clipID == second)
            #expect(editor.model?.draft == "second")
            editor.close()
        }

        @Test("asking for another clip while a draft is unsaved keeps the draft and its clip")
        func whenOpenedAgainWithADraft_thenTheDraftStays() {
            let editor = controller()
            let first = UUID()
            editor.open(clipID: first, text: "first", isMonospaced: false)
            editor.model?.draft = "first, changed"

            editor.open(clipID: UUID(), text: "second", isMonospaced: false)

            #expect(editor.model?.clipID == first)
            #expect(editor.model?.draft == "first, changed")
            editor.close()
        }

        @Test("Cancel closes the window, drops the draft and lets the Dock icon go")
        func whenCanceled_thenClosedAndForgotten() {
            var closes = 0
            let editor = controller { closes += 1 }
            editor.open(clipID: UUID(), text: "text", isMonospaced: false)
            editor.model?.draft = "unsaved"

            editor.model?.cancel()

            #expect(editor.window == nil)
            #expect(editor.model == nil)
            #expect(closes == 1)
        }

        @Test("the window's own close button forgets it as Cancel does")
        func whenClosedByTheWindow_thenForgotten() throws {
            var closes = 0
            let editor = controller { closes += 1 }
            editor.open(clipID: UUID(), text: "text", isMonospaced: false)

            try #require(editor.window).performClose(nil)

            #expect(editor.window == nil)
            #expect(closes == 1)
        }

        @Test("a refused save keeps the window open with the words")
        func whenSaveRefused_thenTheWindowStaysWithAMessage() async throws {
            let editor = controller()
            editor.open(clipID: UUID(), text: "text", isMonospaced: false)
            let model = try #require(editor.model)
            model.draft = "new text"

            await model.commit()

            #expect(editor.window != nil)
            #expect(model.message == TextEditPolicy.failedMessage)
            editor.close()
        }
    }
}

@Suite("The Edit Text draft")
@MainActor
struct TextEditModelTests {
    @Test("Save is ready only for a changed, non-blank text, and a save closes the window")
    func whenDraftChangesAndSaves_thenItCloses() async {
        var saved: [String] = []
        var closed = false
        let model = TextEditModel(clipID: UUID(), text: "old", isMonospaced: false) { _, text in
            saved.append(text)
            return .saved
        }
        model.onClose = { closed = true }
        #expect(!model.canSave)
        model.draft = "   "
        #expect(!model.canSave)
        model.draft = "new"
        #expect(model.canSave)

        await model.commit()

        #expect(saved == ["new"])
        #expect(closed)
        #expect(model.message == nil)
    }

    @Test("an unchanged draft is never sent")
    func whenUnchanged_thenNothingIsSent() async {
        var calls = 0
        let model = TextEditModel(clipID: UUID(), text: "same", isMonospaced: false) { _, _ in
            calls += 1
            return .saved
        }
        await model.commit()
        #expect(calls == 0)
    }
}
