// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftUI

// MARK: - Toast

@MainActor
extension AppDelegate {
    func showManualPasteToast() {
        let toast = ManualPasteToast.choose(
            accessibilityTrusted: AccessibilityAccess.isTrusted,
            declinedAutoPaste: AppDefaults.store.value(for: Setting.declinedAutoPaste),
            alreadyExplained: toastController.hasExplainedAutoPaste
        )
        toastController.show(toast, onClick: toast.isClickable ? { [weak self] in self?.statusOpenAXSettings() } : nil)
        ToastAnnouncement.manualPaste(toast)
    }

    /// Auto-hide the overlay when another app activates, and route the new frontmost app
    /// into the workspace-pinboard logic. Skipped during drag-and-drop so the user can drop
    /// a card into the target app without the overlay cancelling itself mid-drag.
    func setupWorkspaceActivationObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if appState.isOverlayVisible, !appState.isDragging { hideOverlay() }
                updateWorkspacePinboard(for: app.bundleIdentifier)
            }
        }
    }

    /// Refresh Accessibility trust state when the user returns to Pesto (e.g. after granting
    /// AX in System Settings). Together with the overlay's 1 s poll this covers menu-bar
    /// popups, Settings windows, and the overlay banner without forcing a restart.
    func setupAccessibilityRefreshObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.recheckAccessibility()
                self?.applyDoubleCopySetting()
            }
        }
    }
}

// MARK: - Paste task helpers

@MainActor
extension AppDelegate {
    /// Starts a paste through `pasteTasks` (so sleep, wake and lock can interrupt it), logs start/end, and shows the
    /// manual-paste
    /// toast on failure. Using this helper keeps every paste task stored, so the wake and lock handler can
    /// cancel it.
    ///
    /// `body` receives a non-captured `AppDelegate` reference (no retain cycle) and returns the
    /// paste outcome. Return `nil` to signal an early exit that already logged its own `[end]`.
    func runPasteTask(
        _ trigger: PasteTrigger,
        requestedAtEpoch: Int? = nil,
        _ body: @escaping (AppDelegate) async -> PasteCoordinator.Outcome?
    ) {
        Self.pasteLogger.notice("[start] source=\(trigger.logLabel, privacy: .public)")
        let started = pasteTasks.start(requestedAtEpoch: requestedAtEpoch) { [weak self] in
            guard let self else { return }
            if let outcome = await body(self) {
                let outcomeStr = String(describing: outcome)
                Self.pasteLogger.notice(
                    "[end] source=\(trigger.logLabel, privacy: .public) outcome=\(outcomeStr, privacy: .public)"
                )
                if outcome == .requiresManualPaste { self.showManualPasteToast() }
                if SoundEffectPolicy.pasteSoundFor(outcomeRequiredManualPaste: outcome == .requiresManualPaste) {
                    SoundEffects.play(.paste)
                }
            }
        }
        if !started {
            Self.pasteLogger
                .notice("[skip] source=\(trigger.logLabel, privacy: .public) reason=interrupted-since-selection")
        }
    }
}
