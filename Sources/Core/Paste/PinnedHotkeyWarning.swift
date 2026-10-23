// SPDX-License-Identifier: MIT
import Foundation

/// Words for a ⌃1–⌃9 shortcut that Pesto could not claim because another app already holds it, while a pinned clip
/// is assigned to it.
public enum PinnedHotkeyWarning {
    public static func message(for slots: Set<Int>) -> String? {
        guard !slots.isEmpty else { return nil }
        let names = ListFormatter.localizedString(byJoining: slots.sorted().map { "\u{2303}\($0)" })
        if slots.count == 1 {
            return String(
                localized: "\(names) is taken by another app, so its pinned clip can\u{2019}t be pasted with it."
            )
        }
        return String(
            localized: "\(names) are taken by other apps, so their pinned clips can\u{2019}t be pasted with them."
        )
    }

    /// The slots to warn about now: unavailable ones not warned about yet. `warned` keeps only the slots that are still
    /// unavailable, so one that is freed and taken again is reported again.
    public static func fresh(unavailable: Set<Int>, warned: inout Set<Int>) -> Set<Int> {
        let new = unavailable.subtracting(warned)
        warned = unavailable
        return new
    }
}
