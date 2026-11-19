// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import SwiftData

extension AppDelegate: AutomationHost {
    var isHistoryLocked: Bool {
        appState.isHistoryLockedNow()
    }

    var isContentCovered: Bool {
        appState.isContentCovered(screenSharingPrivacy: AppDefaults.store.value(for: Setting.screenSharingPrivacy))
    }

    var historyContainer: ModelContainer? {
        appState.historyContainer
    }

    func showShelf() {
        showOverlay(from: .link)
    }

    func search(for text: String) {
        appState.noteContextRequested()
        appState.searchText = text
        appState.isSearchActive = true
    }

    func selectCollection(_ id: UUID?) {
        appState.noteContextRequested()
        appState.selectedCollectionID = id
    }

    func paste(_ item: ClipboardItem) {
        executePasteItem(item)
    }

    func togglePin(id: UUID) async {
        await appState.attempt("Couldn’t pin the clip") {
            _ = try await appState.storageService?.togglePinned(id: id)
        }
    }

    func requestClear(_ range: ClearRange) {
        requestClearHistory(range)
    }

    /// The one copy path (`writeItem`: the lock, a secret kept to this Mac, the own-write gate), then the clip moves to
    /// the front as a shelf copy does.
    func copyClip(_ item: ClipboardItem) {
        guard appState.writeItem(item) != nil else { return }
        if let context = item.modelContext { appState.noteCopied(item, in: context) }
        Announcer.announce("Copied")
    }

    func openWebLink(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
