// SPDX-License-Identifier: MIT
import Sparkle

/// Pesto has no Dock icon, so Sparkle's scheduled update window can open behind other windows with nothing to say it
/// exists. This takes over showing a scheduled update when the person is not looking: the status menu gets an
/// "Update Available" item at the top, which opens Sparkle's own window on a click (Sparkle's gentle reminders).
@MainActor
final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    )
    -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in self.appState.availableUpdateVersion = handleShowingUpdate ? nil : version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        Task { @MainActor in self.appState.availableUpdateVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.appState.availableUpdateVersion = nil }
    }
}
