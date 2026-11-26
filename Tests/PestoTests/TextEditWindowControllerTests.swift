// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import SwiftData
import SwiftUI
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
            #expect(window.title == "Clip")
            #expect(window.level.rawValue > NSWindow.Level.floating.rawValue)
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

        @Test("unmodified Esc while the text view is first responder cancels and closes the editor")
        func whenEscapePressedInTextView_thenCanceledAndClosed() throws {
            var closes = 0
            let editor = controller { closes += 1 }
            editor.open(clipID: UUID(), text: "hello", isMonospaced: false)
            let window = try #require(editor.window)
            window.orderBack(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let textView = try #require(firstTextView(in: window.contentView))
            window.makeFirstResponder(textView)
            #expect(window.firstResponder === textView)

            let escape = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            ))
            window.sendEvent(escape)

            #expect(editor.window == nil)
            #expect(editor.model == nil)
            #expect(closes == 1)
        }

        @Test("Esc during IME marked text composition keeps the editor open")
        func whenEscapePressedWithMarkedText_thenEditorStaysOpen() throws {
            var closes = 0
            let editor = controller { closes += 1 }
            editor.open(clipID: UUID(), text: "hello", isMonospaced: false)
            let window = try #require(editor.window)
            window.orderBack(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let textView = try #require(firstTextView(in: window.contentView))
            window.makeFirstResponder(textView)
            textView.setMarkedText(
                "あ",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            #expect(textView.hasMarkedText())

            let escape = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            ))
            window.sendEvent(escape)

            #expect(editor.window != nil)
            #expect(editor.model != nil)
            #expect(closes == 0)
            editor.close()
        }

        private func firstTextView(in view: NSView?) -> NSTextView? {
            guard let view else { return nil }
            if let textView = view as? NSTextView { return textView }
            for subview in view.subviews {
                if let match = firstTextView(in: subview) { return match }
            }
            return nil
        }

        @Test("History Lock closes the open editor and drops its unsaved draft")
        func whenHistoryLocks_thenEditorClosesAndDropsDraft() {
            let lockState = AppState()
            var closes = 0
            let editor = TextEditWindowController(appState: lockState, present: { _ in }, didClose: { closes += 1 })
            lockState.closeTextEditor = { editor.close() }

            let savedEnabled = AppDefaults.store.value(for: Setting.biometricLockEnabled)
            let savedSwitched = AppDefaults.store.value(for: Setting.historyLockSwitchedOnAt)
            defer {
                AppDefaults.store.set(savedEnabled, for: Setting.biometricLockEnabled)
                AppDefaults.store.set(savedSwitched, for: Setting.historyLockSwitchedOnAt)
            }
            AppDefaults.store.set(true, for: Setting.biometricLockEnabled)

            editor.open(clipID: UUID(), text: "original", isMonospaced: false)
            editor.model?.draft = "unsaved draft"

            lockState.lockHistory()
            #expect(editor.window == nil)
            #expect(editor.model == nil)
            #expect(closes == 1)

            editor.open(clipID: UUID(), text: "second", isMonospaced: false)
            editor.model?.draft = "second draft"
            lockState.completeUnlock(at: Date(timeIntervalSince1970: 0))
            HistoryLockPolicy.lockWasSwitchedOn(at: Date().addingTimeInterval(1))
            lockState.checkAndApplyBiometricLock(closesTextEditor: true)

            #expect(editor.window == nil)
            #expect(editor.model == nil)
            #expect(closes == 2)
        }

        @Test(
            "VoiceOver exposes Edit Text on an editable card, omits it when covered or masked, and invokes the action"
        )
        func whenCardHosted_thenEditTextAccessibilityActionMatchesConcealment() throws {
            let container = try ModelContainerSetup.makeInMemory()
            let context = ModelContext(container)
            let blob = ClipboardBlob(
                encryptedData: Data("hello".utf8), nonceData: Data(repeating: 1, count: 12),
                mimeType: "public.utf8-plain-text"
            )
            let editableItem = ClipboardItem(
                type: .text, previewText: "hello", contentHash: "h1", byteSize: 5, deviceID: "t", sequenceNumber: 1
            )
            editableItem.blob = blob
            context.insert(editableItem)
            context.insert(blob)

            let secretBlob = ClipboardBlob(
                encryptedData: Data("4242".utf8), nonceData: Data(repeating: 2, count: 12),
                mimeType: "public.utf8-plain-text"
            )
            let secretItem = ClipboardItem(
                type: .text, previewText: "•••• 4242", sensitivity: .creditCard,
                contentHash: "h2", byteSize: 4, deviceID: "t", sequenceNumber: 2
            )
            secretItem.blob = secretBlob
            context.insert(secretItem)
            context.insert(secretBlob)
            try context.save()

            var editedIDs: [UUID] = []
            var actions = CardActions()
            actions.editText = { editedIDs.append($0.id) }

            let editableCard = try hostedCardElement(
                ClipboardCard(item: editableItem), container: container, actions: actions
            )
            let editAction = try #require(
                customActionNames(of: editableCard).first { $0.hasPrefix("Name:Edit Text\n") || $0 == "Edit Text" },
                "editable card should expose Edit Text custom action"
            )
            #expect(AXUIElementPerformAction(editableCard, editAction as CFString) == .success)
            #expect(editedIDs == [editableItem.id])

            let coveredCard = try hostedCardElement(
                ClipboardCard(item: editableItem, isPrivacyBlurred: true), container: container, actions: actions
            )
            #expect(
                !customActionNames(of: coveredCard).contains { $0.hasPrefix("Name:Edit Text\n") || $0 == "Edit Text" },
                "covered card must not expose Edit Text"
            )

            let maskedSecretCard = try hostedCardElement(
                ClipboardCard(item: secretItem), container: container, actions: actions
            )
            #expect(
                !customActionNames(of: maskedSecretCard)
                    .contains { $0.hasPrefix("Name:Edit Text\n") || $0 == "Edit Text" },
                "masked secret card must not expose Edit Text"
            )
        }

        private func hostedCardElement(
            _ card: ClipboardCard,
            container: ModelContainer,
            actions: CardActions
        ) throws
        -> AXUIElement {
            let view = card
                .environment(\.cardActions, actions)
                .defaultAppStorage(AppDefaults.store)
                .modelContainer(container)
                .frame(width: 220, height: 200)
            let hosting = SafeHostingView(pesto: view)
            let windowID = "test-card-\(UUID().uuidString)"
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 220),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier(windowID)
            window.contentView = hosting
            window.orderBack(nil)
            window.displayIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            defer { window.close() }

            let axApp = AXUIElementCreateApplication(getpid())
            var windowsRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            let axWindow = try #require((windowsRef as? [AXUIElement])?.first { axWin in
                var idRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(axWin, kAXIdentifierAttribute as CFString, &idRef)
                return (idRef as? String) == windowID
            })
            return try #require(findAXElement(in: axWindow, identifier: AccessibilityID.card))
        }

        private func findAXElement(in root: AXUIElement, identifier: String) -> AXUIElement? {
            var idRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &idRef)
            if (idRef as? String) == identifier { return root }
            var childrenRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef)
            for child in (childrenRef as? [AXUIElement]) ?? [] {
                if let match = findAXElement(in: child, identifier: identifier) { return match }
            }
            return nil
        }

        private func customActionNames(of element: AXUIElement) -> [String] {
            var namesRef: CFArray?
            _ = AXUIElementCopyActionNames(element, &namesRef)
            return (namesRef as? [String]) ?? []
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

    @Test("Make Snippet starts from the text as typed, and Esc goes back to it without closing the window")
    func whenSnippetBegunAndCancelled_thenTheTypedTextStays() {
        var closed = false
        let model = TextEditModel(clipID: UUID(), text: "Hi Anna", isMonospaced: false) { _, _ in .saved }
        model.onClose = { closed = true }
        model.draft = "Hi Anna, thanks"

        model.beginSnippet(title: "Reply")

        #expect(model.snippetDraft?.text == "Hi Anna, thanks")
        #expect(model.snippetDraft?.title == "Reply")
        #expect(model.snippetDraft?.clipID == model.clipID)
        model.cancel()
        #expect(model.snippetDraft == nil)
        #expect(!closed)
        #expect(model.draft == "Hi Anna, thanks")
        model.cancel()
        #expect(closed)
    }

    @Test("a snippet save sends the clip, the name and the text, and a refusal keeps the editor open with its words")
    func whenSnippetSaved_thenItClosesOrSaysWhy() async throws {
        struct Sent: Equatable {
            let clip: UUID
            let title: String
            let text: String
        }
        var sent: [Sent] = []
        var answer = TextEditSaveResult.refused("Add a placeholder")
        var closed = false
        let id = UUID()
        let model = TextEditModel(
            clipID: id, text: "Hi Anna", isMonospaced: false,
            saveSnippet: { clip, title, text in
                sent.append(Sent(clip: clip, title: title, text: text))
                return answer
            },
            save: { _, _ in .saved }
        )
        model.onClose = { closed = true }
        model.beginSnippet(title: "")
        var snippet = try #require(model.snippetDraft)
        snippet.text = "Hi {{input:name}}"
        snippet.title = "Greeting"

        await model.commitSnippet(snippet)

        #expect(model.message == "Add a placeholder")
        #expect(!closed)
        #expect(model.snippetDraft?.text == "Hi {{input:name}}", "the typed snippet survives a refusal")

        answer = .saved
        await model.commitSnippet(snippet)

        #expect(closed)
        #expect(sent.count == 2)
        #expect(sent.last == Sent(clip: id, title: "Greeting", text: "Hi {{input:name}}"))
    }

    @Test("another clip never replaces a snippet being made")
    func whenSnippetOpen_thenLoadKeepsIt() {
        let model = TextEditModel(clipID: UUID(), text: "first", isMonospaced: false) { _, _ in .saved }
        model.beginSnippet(title: "")

        model.load(clipID: UUID(), text: "second", isMonospaced: false)

        #expect(model.original == "first")
        #expect(model.snippetDraft != nil)
    }
}
