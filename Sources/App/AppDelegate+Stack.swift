// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// A paste stack (ADR 0009): the first clip is pasted when the shelf closes, then each plain ⌘V, in any app, pastes the
/// next one, because Pesto puts it on the pasteboard as soon as the one before has been read. Without Accessibility
/// Pesto cannot see the keystroke, and ⌘⇧V pastes the next clip as it did before.
@MainActor
extension AppDelegate {
    func stackAfterFirstPaste(_ updated: PasteStack?) {
        guard let updated else { return }
        if updated.isComplete {
            finishStack(showing: updated)
            return
        }
        let watches = AccessibilityAccess.isTrusted
        stackHUDController.onCancel = { [weak self] in self?.cancelStack() }
        stackHUDController.show(stack: updated, pastesWithCommandV: watches)
        guard watches else { return }
        stackSession.watch { [weak self] in self?.stackUserPasted() }
        prepareNextStackItem()
    }

    /// The person pressed ⌘V and the app pasted the clip that was ready: move on to the one after.
    func stackUserPasted() {
        guard appState.activeStack != nil else {
            stackSession.stop()
            return
        }
        appState.activeStack?.advance()
        guard let updated = appState.activeStack else { return }
        if updated.isComplete {
            finishStack(showing: updated)
            return
        }
        stackHUDController.show(stack: updated, pastesWithCommandV: true)
        prepareNextStackItem()
    }

    func cancelStack() {
        appState.activeStack = nil
        stackSession.stop()
        stackHUDController.hide()
    }

    private func finishStack(showing stack: PasteStack) {
        appState.activeStack = nil
        stackSession.stop()
        stackHUDController.update(stack: stack)
    }

    private func prepareNextStackItem() {
        stackSession.prepare { [weak self] in
            guard let self, let next = appState.activeStack?.current else { return }
            writeStackItemToPasteboard(next)
        }
    }

    @objc
    func statusCancelStack() {
        cancelStack()
    }
}
