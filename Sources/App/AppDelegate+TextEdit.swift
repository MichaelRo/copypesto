// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

@MainActor
extension AppDelegate {
    /// Settings and Edit Text open from the shelf after it has closed.
    func wireWindowsOpenedFromShelf() {
        appState.openSettingsFromOverlay = { [weak self] in
            guard let self else { return }
            let shelfFrame = self.overlayWindowController?.overlayWindow.frame
            self.appState.close(.afterHide { [weak self] in self?.openSettingsWindow(shelfFrame: shelfFrame) })
        }
        appState.openTextEditor = { [weak self] item in self?.requestTextEdit(of: item) }
        appState.closeTextEditor = { [weak self] in self?.textEditController.close() }
    }

    func makeTextEditController() -> TextEditWindowController {
        TextEditWindowController(
            appState: appState,
            present: { [weak self] in self?.presentTextEditor($0) },
            didClose: { [weak self] in self?.updateActivationPolicy() }
        )
    }

    /// The text is read before the shelf closes, while the card that offered Edit Text is still what the person saw
    /// (a secret only while its Show runs). The shelf closes first, as it does for Settings (ADR 0050).
    func requestTextEdit(of item: ClipboardItem) {
        guard !appState.isHistoryLockedNow(),
              TextEditOutcome.isEditable(type: item.type, analysisPending: item.analysisPending),
              item.byteSize <= TextEditPolicy.maxEditableBytes,
              let text = item.blob?.decryptedText() else { return }
        let id = item.id
        let isMonospaced = item.type == .code || item.type == .color
        guard appState.isOverlayVisible else {
            textEditController.open(clipID: id, text: text, isMonospaced: isMonospaced)
            return
        }
        appState.close(.afterHide { [weak self] in
            self?.textEditController.open(clipID: id, text: text, isMonospaced: isMonospaced)
        })
    }

    func presentTextEditor(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        bringToFront(window)
    }
}
