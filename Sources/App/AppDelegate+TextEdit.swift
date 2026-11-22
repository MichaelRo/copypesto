// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

@MainActor
extension AppDelegate {
    /// Settings opens from the shelf after it has closed; Edit Text opens above the shelf.
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
            didClose: { [weak self] in
                guard let self else { return }
                self.appState.isTextEditorOpen = false
                self.updateActivationPolicy()
                self.appState.onRestoreKeyFocus?()
            }
        )
    }

    /// The text is read while the card that offered Edit Text is still what the person saw (a secret only while its
    /// Show runs). Edit Text opens above the shelf without closing it.
    func requestTextEdit(of item: ClipboardItem) {
        guard !appState.isHistoryLockedNow(),
              TextEditOutcome.isEditable(type: item.type, analysisPending: item.analysisPending),
              item.byteSize <= TextEditPolicy.maxEditableBytes,
              let text = item.blob?.decryptedText() else { return }
        appState.isTextEditorOpen = true
        textEditController.open(
            clipID: item.id,
            text: text,
            isMonospaced: item.type == .code || item.type == .color
        )
    }

    func presentTextEditor(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        if !appState.isOverlayVisible {
            NSApp.setActivationPolicy(.regular)
        }
        bringToFront(window)
    }
}
