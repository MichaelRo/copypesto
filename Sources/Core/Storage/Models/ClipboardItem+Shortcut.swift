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

    func isShortcutIdle(
        days: Int,
        relativeTo now: Date = .now,
        armedAt: Date? = nil,
        calendar: Calendar = .current
    )
    -> Bool {
        guard pinnedHotkeyIndex != nil else { return false }
        let effectiveLastUse = [shortcutLastUsedAt, armedAt].compactMap(\.self).max() ?? .distantPast
        guard let threshold = calendar.date(byAdding: .day, value: -days, to: now) else { return false }
        return effectiveLastUse <= threshold
    }
}
