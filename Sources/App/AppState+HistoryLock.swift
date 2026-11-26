// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

@MainActor
extension AppState {
    /// Unlocks only if the user authenticates; with nothing able to authenticate, history stays locked.
    func performBiometricUnlock() async {
        let unlocked = await withSystemAuthenticationDialog {
            await HistoryLockPolicy.unlock(using: UserAuthenticator.current)
        }
        guard unlocked else { return }
        completeUnlock()
    }

    func completeUnlock(at date: Date = Date()) {
        AuthenticationGrace.shared.record()
        let wasLocked = isHistoryLocked
        isHistoryLocked = false
        lastBiometricUnlock = date
        if wasLocked { startSimilarityWork() }
    }

    /// Immediately locks history and purges decrypted previews from memory.
    func lockHistory() {
        guard AppDefaults.store.value(for: Setting.biometricLockEnabled) else { return }
        cancelAsk()
        lastBiometricUnlock = nil
        isHistoryLocked = true
        openedLockedCollections = []
        closeTextEditor?()
        clipboardBeforeLastItemWrite = ""
        aiResult = nil
        storageService?.undoHistory.clear()
        stopSimilarityWork()
        dismissUndoOffer()
        suppressShelfSuggestions()
        PreviewTextCache.shared.clear()
        historyStore?.dropSearchText()
        ThumbnailCache.shared.clear()
        AuthenticationGrace.shared.clear()
        QuickLookPreviewController.sweepStaleTempFiles()
    }
}
