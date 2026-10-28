// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Keeps what was typed into a snippet's fill-ins for next time. It is not an edit, so Undo does not hold it; the
    /// values are sealed with the clip's metadata and leave with the clip.
    func rememberFillIns(id: UUID, memory: [String: String]) throws {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first, item.metadata.fieldMemory != memory else { return }
        item.updateMetadata { $0.fieldMemory = memory.isEmpty ? nil : memory }
        try saveOrRollback()
    }

    /// Erases every remembered value, when the person turns remembering off.
    func forgetAllFillIns() async throws {
        try await forEachClip { item in
            guard item.metadata.fieldMemory != nil else { return }
            item.updateMetadata { $0.fieldMemory = nil }
        }
    }
}
