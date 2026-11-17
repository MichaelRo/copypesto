// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation
import OSLog
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Hotkey conflict detection in hosted process", .serialized)
    @MainActor
    final class HotkeyConflictHostedTests {
        private func hotkeyLogMessages(since date: Date) throws -> [String] {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: date)
            return try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.category == "hotkey" }
                .map(\.composedMessage)
        }

        @Test("claims conflict when ⌃⌥⌘V is already held in Carbon and clears when released")
        func whenHelperClaimsPlainTextHotkey_thenConflictIsLoggedAndNotified() async throws {
            let savedCode = AppDefaults.store.value(for: Setting.pastePlainHotkeyKeyCode)
            let savedMods = AppDefaults.store.value(for: Setting.pastePlainHotkeyModifiers)
            AppDefaults.store.set(0, for: Setting.pastePlainHotkeyKeyCode)
            AppDefaults.store.set(0, for: Setting.pastePlainHotkeyModifiers)
            defer {
                AppDefaults.store.set(savedCode, for: Setting.pastePlainHotkeyKeyCode)
                AppDefaults.store.set(savedMods, for: Setting.pastePlainHotkeyModifiers)
            }

            var holderRef: EventHotKeyRef?
            let holderStatus = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: OSType(0x5445_5354), id: 1),
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &holderRef
            )
            defer {
                if let holderRef { UnregisterEventHotKey(holderRef) }
            }
            #expect(holderStatus == noErr)

            let controller = HotkeyController()
            defer { controller.unregister() }

            var notifications: [[String]] = []
            let observer = NotificationCenter.default.addObserver(
                forName: .hotkeyConflictDetected, object: nil, queue: .main
            ) { note in
                let conflicts = note.userInfo?["conflicts"] as? [String] ?? []
                notifications.append(conflicts)
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let conflictStart = Date()
            controller.register()

            #expect(controller.conflictingHotkeys.contains("Paste as plain text"))
            #expect(notifications.last?.contains("Paste as plain text") == true)
            let conflictLogs = try hotkeyLogMessages(since: conflictStart)
            #expect(conflictLogs.contains("Registered Paste as plain text: status -9878"))

            if let ref = holderRef {
                UnregisterEventHotKey(ref)
                holderRef = nil
            }
            try await Task.sleep(for: .milliseconds(50))

            let clearStart = Date()
            controller.reregisterMain()

            #expect(!controller.conflictingHotkeys.contains("Paste as plain text"))
            #expect(notifications.last?.contains("Paste as plain text") == false)
            let clearLogs = try hotkeyLogMessages(since: clearStart)
            #expect(clearLogs.contains("Registered Paste as plain text: status 0"))
        }
    }
}
