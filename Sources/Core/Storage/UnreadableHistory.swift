// SPDX-License-Identifier: MIT
import SwiftData

/// What is done with clips whose key is gone. The rows cannot be opened without it, so they are removed; collections
/// have no sealed content and stay.
public enum UnreadableHistory {
    public static func discard(in context: ModelContext) throws {
        try context.delete(model: ClipboardItem.self)
        try context.delete(model: ClipboardBlob.self)
        try context.saveOrRollback()
    }
}
