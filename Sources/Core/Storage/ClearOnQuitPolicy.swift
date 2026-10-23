// SPDX-License-Identifier: MIT
import Foundation

public enum ClearOnQuitPolicy {
    /// An unresolved key means the history is only unreadable, not gone: the person was told to quit and try to restore
    /// the key, so quitting must leave every row in place.
    public static func shouldClear(enabled: Bool, hasStorage: Bool, keyUnresolved: Bool) -> Bool {
        enabled && hasStorage && !keyUnresolved
    }
}
