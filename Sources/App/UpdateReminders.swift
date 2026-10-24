// SPDX-License-Identifier: MIT
import Sparkle

/// Pesto has no Dock icon, so Sparkle's scheduled update window can open behind other windows with nothing to say it
/// exists. This takes over showing a scheduled update when the person is not looking: the status menu gets an
/// "Update Available" item at the top, which opens Sparkle's own window on a click (Sparkle's gentle reminders).
@MainActor
final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private let appState: AppState
    var onUpToDate: (() -> Void)?
    private(set) var hasPendingManualCheck = false

    init(appState: AppState) {
        self.appState = appState
    }

    func beginManualCheck() {
        hasPendingManualCheck = true
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    )
    -> Bool {
        MainActor.assumeIsolated {
            hasPendingManualCheck || immediateFocus
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in
            self.hasPendingManualCheck = false
            self.appState.availableUpdateVersion = handleShowingUpdate ? nil : version
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        Task { @MainActor in self.appState.availableUpdateVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            self.hasPendingManualCheck = false
            self.appState.availableUpdateVersion = nil
        }
    }

    func handleNoUpdateFound(userInitiated: Bool = false) {
        let wasManual = hasPendingManualCheck || userInitiated
        hasPendingManualCheck = false
        if wasManual {
            onUpToDate?()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_: SPUUpdater, error: any Error) {
        let userInitiated = (error as NSError).userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool == true
        Task { @MainActor in
            self.handleNoUpdateFound(userInitiated: userInitiated)
        }
    }
}
