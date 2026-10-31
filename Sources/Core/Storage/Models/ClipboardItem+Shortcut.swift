// SPDX-License-Identifier: MIT
import Foundation

public extension ClipboardItem {
    func setShortcut(_ slot: Int?, at now: Date = .now, calendar: Calendar = .current) {
        pinnedHotkeyIndex = slot
        if slot != nil {
            shortcutLastUsedAt = calendar.startOfDay(for: now)
        } else {
            shortcutLastUsedAt = nil
        }
    }
}
