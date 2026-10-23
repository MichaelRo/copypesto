// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The small menu at the cursor can be turned off")
struct QuickMenuSettingTests {
    @Test("it is off by default: the shortcut opens the shelf that the guide shows and the keyboard drives")
    func whenNeverSet_thenOff() {
        #expect(Setting.opensQuickMenuAtCursor.defaultValue == false)
        #expect(ThrowawayDefaults.make().value(for: Setting.opensQuickMenuAtCursor) == false)
    }

    @Test("it is a registered preference, so it is exported, restored and searchable like the others")
    func whenRegistered_thenListed() {
        #expect(Setting.allNames.contains(Setting.opensQuickMenuAtCursor.name))
        #expect(SettingsIndex.entries.contains { $0.title == "Open a small menu at the cursor" })
    }
}
