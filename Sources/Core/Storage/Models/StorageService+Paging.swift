// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    /// Visits the clips matching `descriptor` one page at a time, saving after each page and then letting other work
    /// on this actor run, so a launch migration never holds an ingest or a delete for a whole-table pass. The
    /// identifiers are read first and each page is fetched by identifier, so a clip deleted between pages is skipped
    /// and only one page of rows is in memory at a time.
    func forEachClip(
        matching descriptor: FetchDescriptor<ClipboardItem> = FetchDescriptor<ClipboardItem>(),
        pageSize: Int = 50,
        _ visit: (ClipboardItem) throws -> Void
    ) async throws {
        let ids = try modelContext.fetchIdentifiers(descriptor)
        for start in stride(from: 0, to: ids.count, by: pageSize) {
            let page = Array(ids[start..<min(start + pageSize, ids.count)])
            let items = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { page.contains($0.persistentModelID) }
            ))
            do {
                for item in items {
                    try visit(item)
                }
            } catch {
                modelContext.rollback()
                throw error
            }
            try saveOrRollback()
            await Task.yield()
        }
    }
}
