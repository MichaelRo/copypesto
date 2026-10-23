// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

extension AppDelegate: AutomationHost {
    var isHistoryLocked: Bool {
        appState.isHistoryLockedNow()
    }

    var historyContainer: ModelContainer? {
        appState.historyContainer
    }

    func showShelf() {
        showOverlay(from: .link)
    }

    func search(for text: String) {
        appState.searchText = text
        appState.isSearchActive = true
    }

    func selectCollection(_ id: UUID?) {
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
}
