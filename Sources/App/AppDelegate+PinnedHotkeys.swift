// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

extension AppDelegate {
    func promptForAccessibilityOncePerVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let store = AppDefaults.store
        guard AccessibilityPromptPolicy.shouldPrompt(
            lastPromptedVersion: store.string(forKey: AccessibilityPromptPolicy.defaultsKey),
            currentVersion: version
        ) else { return }
        store.set(version, forKey: AccessibilityPromptPolicy.defaultsKey)
        AccessibilityPermission.requestWithPrompt()
    }

    func startPinnedHotkeyTracking() {
        guard LaunchMode.current.usesSystemIntegrations else { return }
        refreshPinnedHotkeySlots()
        // Lives for the app's lifetime, like the hotkeys it feeds.
        _ = ModelSaveObserver.observe { [weak self] in self?.refreshPinnedHotkeySlots() }
    }

    private func refreshPinnedHotkeySlots() {
        guard let container = appState.historyContainer else { return }
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned && $0.pinnedHotkeyIndex != nil }
        )
        let assigned = (try? ModelContext(container).fetch(descriptor)) ?? []
        appState.hotkeyController.updatePinnedSlots(active: Set(assigned.compactMap(\.pinnedHotkeyIndex)))
        let fresh = PinnedHotkeyWarning.fresh(
            unavailable: appState.hotkeyController.unavailableSlots, warned: &appState.warnedHotkeySlots
        )
        if let message = PinnedHotkeyWarning.message(for: fresh) { appState.showUserMessage(message) }
    }

    func triggerPinnedHotkey(slot: Int) {
        guard let container = appState.historyContainer else { return }
        guard !appState.isHistoryLockedNow() else { return showOverlay() }
        runPasteTask(.pinnedHotkey(slot: slot)) { delegate in
            let ctx = ModelContext(container)
            let targetSlot = slot
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.pinnedHotkeyIndex == targetSlot && $0.isPinned }
            )
            guard let item = try? ctx.fetch(descriptor).first else {
                Self.pasteLogger
                    .notice("[end] source=pinned-hotkey slot=\(slot, privacy: .public) outcome=no-item-in-slot")
                return nil
            }
            guard let rawPayload = delegate.writeItemToPasteboard(item) else { return nil }
            delegate.appState.pasteCoordinator.focusRestoration.capture()
            guard let (payloadKind, caretOffset) = await delegate.expandedPayload(from: rawPayload, of: item) else {
                return nil
            }
            let outcome = await delegate.appState.pasteCoordinator.executePaste(
                payload: payloadKind, caretOffsetFromEnd: caretOffset
            )
            if outcome != .requiresManualPaste {
                delegate.appState.noteShortcutUsed(id: item.id)
            }
            return outcome
        }
    }
}
