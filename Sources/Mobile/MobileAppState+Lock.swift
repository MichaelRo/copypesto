// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What the History Lock does to the app (ADR 0054), as the Mac's `AppState.lockHistory` does: nothing decrypted
/// stays in memory, Undo forgets, Shortcuts find nothing, sync pauses, and what was shared or tapped on a widget
/// waits for the unlock. With the lock on and `showsClipsOutsideWhileLocked` off, outside surfaces lock with the
/// app and expire after the grace window.
extension MobileAppState {
    var isHistoryLocked: Bool {
        historyLock.isLocked
    }

    /// Asks the lock first, so a Shortcut run while Pesto is away past the timeout finds it locked.
    func isHistoryLockedNow() -> Bool {
        if historyLock.lockIfAwayTooLong(at: clock()) { forgetUnlockedState() }
        return historyLock.isLocked
    }

    func lockDidBecomeActive() {
        _ = isHistoryLockedNow()
        historyLock.didBecomeActive()
    }

    func lockHistory() {
        CardMedia.clearAnimationCache()
        guard historyLock.isEnabled else { return }
        historyLock.lock()
        forgetUnlockedState()
    }

    @discardableResult
    func unlockHistory() async -> Bool {
        guard await historyLock.unlock() else { return false }
        didUnlock()
        return true
    }

    /// Where nothing can authenticate the lock protects no one, so the lock screen offers to turn it off (the Mac's
    /// `HistoryLockPolicy.permitsTurningLockOff`).
    func turnOffHistoryLock() async -> Bool {
        guard await HistoryLockPolicy.permitsTurningLockOff(
            using: historyLock.authenticator, reason: String(localized: "Turn off the history lock"),
            grace: historyLock.grace
        ) else { return false }
        AppDefaults.store.set(false, for: Setting.biometricLockEnabled)
        historyLockSettingChanged()
        return true
    }

    func historyLockSettingChanged() {
        if historyLock.isEnabled {
            HistoryLockPolicy.lockWasSwitchedOn()
            offersAutoFillTip = false
            historyLock.lock()
            forgetUnlockedState()
        } else {
            let wasLocked = historyLock.isLocked
            historyLock.lockWasTurnedOff()
            if wasLocked { didUnlock() } else { writeOutsideSurfaces() }
        }
    }

    private func forgetUnlockedState() {
        showsWelcome = false
        syncSetUpRequested = false
        ShareFile.removeAll()
        Self.clearImportStaging()
        secretReveal.hideAll()
        decodedJWT = nil
        closeAI()
        storageService?.undoHistory.clear()
        undoOfferDismissal?.cancel()
        undoOffer = nil
        clipboardOfferCount = nil
        pendingFill = nil
        cancelPendingCollectionImport()
        linkedClip = nil
        shortcutSearchQuery = nil
        historyStore?.setVisible(false)
        historyStore?.dropSearchText()
        stopSimilarityWork()
        PreviewTextCache.shared.clear()
        emptyOutsideSurfaces()
    }

    private func didUnlock() {
        historyStore?.setVisible(true)
        syncDidBecomeActive()
        inboxDidBecomeActive()
        reconcileKeyboardSize()
        writeOutsideSurfaces()
        startSimilarityWork()
        Task { await clipboardDidBecomeActive() }
        if let link = heldLink {
            heldLink = nil
            let priorScoped = heldSecurityScopedURL
            heldSecurityScopedURL = nil
            open(link)
            priorScoped?.stopAccessingSecurityScopedResource()
        }
    }

    /// The toggle under the lock row: with it on the widget and the set are written as without the lock, with it off
    /// they go back to saying Locked and holding nothing.
    func showsClipsOutsideSettingChanged() {
        guard historyLock.isEnabled else { return }
        if historyLock.holdsOutsideSurfaces { emptyOutsideSurfaces() } else { writeOutsideSurfaces() }
    }

    private func emptyOutsideSurfaces() {
        guard historyLock.holdsOutsideSurfaces else { return }
        emptyQuickInsert()
        if let widget, widgetIsInstalled || widget.file.exists { performWidgetEmpty() }
    }

    private func writeOutsideSurfaces() {
        writeQuickInsert()
        Task { await refreshWidgetPresence() }
    }
}
