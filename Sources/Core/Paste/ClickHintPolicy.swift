// SPDX-License-Identifier: MIT
public enum ClickHintPolicy {
    public static let limit = 3

    public static func shouldShow(timesShown: Int, hasDoubleClickPasted: Bool, tap: ShelfTap) -> Bool {
        tap == .focus && !hasDoubleClickPasted && timesShown < limit
    }

    public static func isDoubleClickPaste(click: ShelfClick, tap: ShelfTap) -> Bool {
        click == .double && tap == .paste
    }
}
