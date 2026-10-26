// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore

extension AppDelegate {
    /// Every way of clearing history (status menu, `pesto://clear`, AppleScript) comes through here, so
    /// nothing is deleted without the user confirming what will go.
    func requestClearHistory(_ range: ClearRange) {
        guard let service = storageService else { return }
        Task { @MainActor in
            let count = await (try? service.nonPinnedCount(in: range)) ?? 0
            guard count > 0, confirmClear(count: count, range: range) else { return }
            do {
                let ids = try await service.clearNonPinned(in: range)
                AutoBackupSettings().lowerBaseline(by: ids.count)
                if range == .all {
                    appState.clearShelfSuggestions()
                }
            } catch {
                Self.logger.error("Clear history failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func confirmClear(count: Int, range: ClearRange) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Clear \(count) clips?")
        alert.informativeText = String(
            localized: "This deletes \(range.summary). Pinned clips are kept. It can\u{2019}t be undone."
        )
        // Cancel is added first so it is the default button: Return must never delete.
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        let clear = alert.addButton(withTitle: String(localized: "Clear"))
        clear.hasDestructiveAction = true
        cancel.setAccessibilityIdentifier(AccessibilityID.clearConfirmCancel)
        clear.setAccessibilityIdentifier(AccessibilityID.clearConfirmDelete)
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }
}
