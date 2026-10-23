// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Counts a paste of something made from this clip (an AI answer) as a use of the clip: it moves to the front of
    /// the history, as a paste of the clip itself does. Returns false when no such clip exists. A use is not an edit,
    /// so Undo does not hold it.
    @discardableResult
    func notePasted(id: UUID, at date: Date = .now) throws -> Bool {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return false }
        item.pasteCount += 1
        item.timestamp = date
        try saveOrRollback()
        return true
    }
}
