// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

extension AppDelegate {
    /// Runs once, when a new install finishes onboarding. Anyone who onboarded before this existed never sees it, and a
    /// clip the user deletes is not brought back.
    func seedFirstRunSamples() {
        guard RuntimeConfiguration.current.mode == .normal,
              !AppDefaults.store.value(for: Setting.samplesSeeded),
              let container = appState.historyContainer else { return }
        AppDefaults.store.set(true, for: Setting.samplesSeeded)
        let shortcut = HotkeyDescription.overlay(
            storedKeyCode: AppDefaults.store.value(for: Setting.overlayHotkeyKeyCode),
            storedModifiers: AppDefaults.store.value(for: Setting.overlayHotkeyModifiers)
        )
        let records = FirstRunSamples.records(shortcut: shortcut)
        Task {
            do {
                let summary = try await PasteMigrator(modelContainer: container).migrate(records: records)
                Self.logger.info("First-run samples added: \(summary.imported)")
            } catch {
                Self.logger.error("First-run samples failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
