// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// The tags and apps the command bar offers as chips. Tags are sealed (ADR 0002), so no query can count them: this
    /// opens them page by page on the actor, letting other work run between pages, instead of the main actor holding
    /// every clip in a live query.
    func commandBarSuggestions(tagLimit: Int = 8, appLimit: Int = 5, batchSize: Int = 200) async throws
    -> CommandBarSuggestions {
        var tally = SuggestionTally(
            recentSince: Calendar.current.date(byAdding: .day, value: -AppChips.recentDays, to: clock())
        )
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            let page = try modelContext.fetch(descriptor)
            for item in page {
                tally.add(
                    tags: item.tags, bundleID: item.sourceBundleID, appName: item.sourceAppName,
                    isRemote: item.isRemote,
                    timestamp: item.timestamp
                )
            }
            guard page.count == batchSize else { break }
            offset += batchSize
            await Task.yield()
        }
        return tally.suggestions(tagLimit: tagLimit, appLimit: appLimit, recentAppLimit: AppChips.recentLimit + 3)
    }
}
