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
        appState.openTextEditor = { [weak self] item, shown in self?.requestTextEdit(of: item, secretShown: shown) }
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

    /// The Clip window for any clip (ADR 0071), above the shelf without closing it. Its text is editable only when Edit
    /// Text would be (ADR 0050) and the clip is no secret or its secret is shown on its card (that Show already asked
    /// for Touch ID): a hidden clip's text is never read here.
    func requestTextEdit(of item: ClipboardItem, secretShown: Bool) {
        guard !appState.isHistoryLockedNow() else { return }
        let editable = (item.sensitivityRaw == nil || secretShown)
            && TextEditOutcome.isEditable(type: item.type, analysisPending: item.analysisPending)
            && item.byteSize <= TextEditPolicy.maxEditableBytes
        let text = editable ? item.blob?.decryptedText() : nil
        appState.isTextEditorOpen = true
        textEditController.open(
            clipID: item.id,
            text: text ?? "",
            isMonospaced: item.type == .code || item.type == .color,
            isEditable: text != nil
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
