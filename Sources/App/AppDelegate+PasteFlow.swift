// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftData
import SwiftUI

// MARK: - Paste flow

@MainActor
extension AppDelegate {
    /// Called by `AppState.onOverlayHidden` every time `isOverlayVisible` is set to `false`.
    /// Hides the panel and then does what the close was for (`ShelfExit`): paste a clip, run an action, start a stack,
    /// or nothing.
    func handleOverlayHidden() {
        appState.pasteCoordinator.focusRestoration.markHidden()
        switch appState.takePendingExit() {
        case let .paste(item, payloadKind): hideThenPaste(item, payloadKind)
        case let .afterHide(action): hideShelf(completion: action)
        case .startStack:
            hideShelf(completion: nil)
            pasteNextStackItem()
        case .dismissed:
            Self.pasteLogger.log("[paste] overlay hidden with no chosen clip (no paste expected)")
            hideShelf(completion: nil)
        }
    }

    private func hideShelf(completion: (() -> Void)?) {
        if let controller = overlayWindowController {
            controller.hide(completion: completion)
        } else {
            completion?()
        }
    }

    private func hideThenPaste(_ item: ClipboardItem, _ chosen: PasteCoordinator.PayloadKind) {
        // If the Mac sleeps or locks before the hide animation finishes, this selection is stale.
        let requestedAtEpoch = pasteTasks.interruptionEpoch
        // Fire paste in the hide() completion block, which runs after orderOut(nil).
        // This is deterministic: the target window has already reclaimed key status by
        // the time executePaste runs, so CGEvent Cmd+V always goes to the right app.
        Self.pasteLogger.log("[paste] overlay hidden with a chosen clip — scheduling paste in hide completion")
        let doPaste = { [weak self] in
            guard let self else { return }
            Self.pasteLogger.log("[paste] hide() completion fired — launching paste task")
            // runPasteTask starts the paste through pasteTasks so the wake/lock handler
            // can cancel it before the FocusRestoration sleep completes.
            runPasteTask(.overlaySelect(itemID: item.id), requestedAtEpoch: requestedAtEpoch) { delegate in
                guard let (payloadKind, caretOffset) = await delegate.expandedPayload(from: chosen, of: item) else {
                    return nil
                }
                return await delegate.appState.pasteCoordinator.executePaste(
                    payload: payloadKind, caretOffsetFromEnd: caretOffset
                )
            }
            // deleteIfExpired captures ClipboardItem (non-Sendable); run synchronously
            // here rather than inside the Task to avoid a Sendable crossing.
            deleteIfExpired(item)
        }
        if let controller = overlayWindowController {
            controller.hide(immediately: true, completion: doPaste)
        } else {
            doPaste()
        }
    }

    /// Pastes the current stack item, advances the index, and updates the HUD.
    /// Called both when the stack is first activated (overlay close) and on each subsequent ⌘⇧V.
    func pasteNextStackItem() {
        guard let stack = appState.activeStack, let item = stack.current else {
            cancelStack()
            return
        }
        let position = stack.currentIndex
        writeStackItemToPasteboard(item)
        appState.activeStack?.advance()
        let updatedStack = appState.activeStack
        stackSession.ignoreOwnPaste()
        appState.pasteCoordinator.focusRestoration.capture()
        runPasteTask(.stackAdvance(position: position)) { delegate in
            let outcome = await delegate.appState.pasteCoordinator.executePaste(payload: item.payloadKind)
            delegate.stackAfterFirstPaste(updatedStack)
            return outcome
        }
    }

    func writeStackItemToPasteboard(_ item: PasteStack.Item) {
        appState.writeStackItem(item)
    }

    func deleteIfExpired(_ item: ClipboardItem) {
        guard !item.isPinned, let expiry = item.expiresAt, expiry == .distantPast || expiry <= .now,
              let service = storageService else { return }
        let id = item.id
        Task {
            do {
                try await service.deleteItem(id: id)
            } catch {
                let desc = error.localizedDescription
                Self.logger.error("deleteIfExpired failed for \(id, privacy: .private): \(desc, privacy: .public)")
            }
        }
    }

    /// The payload with a snippet's placeholders filled in, and how far the caret must move back afterwards. A snippet
    /// that asks for values shows the prompt first; nil means the person cancelled it, or the paste was.
    func expandedPayload(
        from payload: PasteCoordinator.PayloadKind,
        of item: ClipboardItem
    )
        async -> (PasteCoordinator.PayloadKind, caretOffset: Int?)?
    {
        let isSnippet = item.isTemplate
        let title = item.metadata.customTitle ?? String(localized: "Snippet")
        let priorClipboard = appState.clipboardBeforeLastItemWrite
        appState.clipboardBeforeLastItemWrite = ""
        guard case let .text(str) = payload, isSnippet, TemplateExpander.containsPlaceholders(str) else {
            return (payload, nil)
        }
        let fields = FillInParser.fields(in: str)
        var fills = SnippetFills.initial(for: fields)
        if !fields.isEmpty {
            guard let asked = await fillInPrompt.ask(title: title, fields: fields, initial: fills) else {
                Self.pasteLogger.notice("[end] outcome=fill-in-cancelled")
                return nil
            }
            fills = asked
        }
        guard let expanded = TemplateExpander.expansionWithCaret(
            of: str,
            isSnippet: true,
            fills: fills,
            targetApp: appState.pasteCoordinator.focusRestoration.targetName,
            clipboardProvider: { priorClipboard }
        ) else {
            return (payload, nil)
        }
        appState.writeText(expanded.text, protected: AppState.isProtected(AppPasteboard.general))
        return (.text(expanded.text), expanded.charactersAfterCursor)
    }
}

// MARK: - Quick paste / workspace helpers

@MainActor
extension AppDelegate {
    func triggerQuickPasteLast() {
        guard let container = appState.historyContainer else { return }
        guard !appState.isHistoryLockedNow() else { return showOverlay() }
        runPasteTask(.quickPasteLast) { delegate in
            let heldUnrecorded = await delegate.appState.pasteboardWatcher?.boardHoldsUnrecordedCopy ?? false
            guard let item = delegate.fetchPreviousClip(
                from: container, boardHoldsUnrecordedCopy: heldUnrecorded
            ) else {
                Self.pasteLogger.notice("[end] source=quick-paste-last outcome=no-prior-item")
                return nil
            }
            guard let rawPayload = delegate.writeItemToPasteboard(item) else { return nil }
            delegate.appState.pasteCoordinator.focusRestoration.capture()
            guard let (payloadKind, caretOffset) = await delegate.expandedPayload(from: rawPayload, of: item) else {
                return nil
            }
            return await delegate.appState.pasteCoordinator.executePaste(
                payload: payloadKind, caretOffsetFromEnd: caretOffset
            )
        }
    }

    /// Pastes what is on the clipboard now, stripped of formatting. It reads the live pasteboard rather than the
    /// history: the newest history entry may be missing (excluded source) or not what the user just copied.
    func triggerPastePlainText() {
        guard let plaintext = AppPasteboard.general.string(forType: .string), !plaintext.isEmpty else {
            Self.pasteLogger.notice("[end] source=paste-plain-text outcome=no-plain-text-on-clipboard")
            NSSound.beep()
            return
        }
        let keepsProtection = AppState.isProtected(AppPasteboard.general)
        runPasteTask(.pastePlainText) { delegate in
            delegate.appState.writeText(plaintext, protected: keepsProtection)
            delegate.appState.pasteCoordinator.focusRestoration.capture()
            return await delegate.appState.pasteCoordinator.executePaste(payload: .text(plaintext))
        }
    }

    /// Pastes an AI answer into the app the person was using. The panel never activated Pesto, so that app is still in
    /// front; the answer leaves the panel first so the keyboard goes back to it. The write goes through the gate (the
    /// watcher must not file the answer as a copy); Copy Result is the button for that.
    func pasteAIResult(_ result: AIResult) {
        guard result.canPaste else { return }
        appState.aiResult = nil
        aiResultController.hide()
        runPasteTask(.aiResult) { delegate in
            delegate.appState.writeText(result.result, protected: result.isProtected)
            delegate.appState.pasteCoordinator.focusRestoration.captureKeepingTargetWhenPestoIsFront()
            let outcome = await delegate.appState.pasteCoordinator.executePaste(payload: .text(result.result))
            if outcome != .requiresManualPaste, let source = result.sourceItemID {
                await delegate.appState.noteAnswerPasted(from: source)
            }
            return outcome
        }
    }

    func fetchPreviousClip(from container: ModelContainer, boardHoldsUnrecordedCopy: Bool) -> ClipboardItem? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.sequenceNumber, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 2
        guard let items = try? context.fetch(descriptor),
              let index = QuickPasteLast.index(
                  historyCount: items.count,
                  boardHoldsUnrecordedCopy: boardHoldsUnrecordedCopy
              ) else { return nil }
        return items[index]
    }

    func updateWorkspacePinboard(for bundleID: String?) {
        guard let container = appState.historyContainer else { return }
        let ctx = ModelContext(container)
        let all = (try? ctx.fetch(FetchDescriptor<Pinboard>())) ?? []
        let match = all.first { $0.triggerBundleID == bundleID }
        appState.selectedCollectionID = match?.id
    }
}

// MARK: - Shared pasteboard helpers (accessible to extensions in other files)

@MainActor
extension AppDelegate {
    @discardableResult
    func writeItemToPasteboard(_ item: ClipboardItem) -> PasteCoordinator.PayloadKind? {
        appState.writeItem(item)
    }

    /// Direct paste path for AppleScript and URL-scheme triggers.
    ///
    /// Bypasses the overlay state machine entirely — no `isOverlayVisible` assignment, no
    /// `ShelfExit` round-trip. Focus is captured synchronously so the target is locked
    /// in before the async write/execute pipeline begins.
    func executePasteItem(_ item: ClipboardItem) {
        appState.pasteCoordinator.focusRestoration.capture()
        runPasteTask(.scriptOrURLScheme(itemID: item.id)) { delegate in
            guard let rawPayload = delegate.writeItemToPasteboard(item) else { return nil }
            guard let (payloadKind, caretOffset) = await delegate.expandedPayload(from: rawPayload, of: item) else {
                return nil
            }
            return await delegate.appState.pasteCoordinator.executePaste(
                payload: payloadKind, caretOffsetFromEnd: caretOffset
            )
        }
    }
}
