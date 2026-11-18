// SPDX-License-Identifier: MIT
import Foundation

/// When a card whose text changed in the storage actor can be drawn again: once the main context's copy of every
/// changed clip holds a new content hash. `current` returns nil for a clip that is gone, which never holds anything up.
public enum TextArrival {
    public static func hasArrived(_ old: [UUID: String], current: (UUID) -> String?) -> Bool {
        old.allSatisfy { id, hash in current(id).map { $0 != hash } ?? true }
    }
}
