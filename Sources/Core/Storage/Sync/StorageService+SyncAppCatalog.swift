// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    /// The apps the newest synced clips came from, newest first, each with the name, icon and color this Mac
    /// resolves for it (ADR 0068). Apps it cannot draw an icon for are left out; an iPhone resolves none, so it
    /// writes no catalog.
    func syncAppCatalogEntries(scanning limit: Int = 2000) async throws -> [SyncAppCatalog.Entry] {
        // A device that cannot resolve an app (an iPhone) writes nothing, so it need not read a page of clips.
        guard !(resolver is UnknownSourceApps) else { return [] }
        var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = limit
        descriptor.propertiesToFetch = [\.sourceBundleID, \.syncEmittedClock]
        var bundleIDs: [String] = []
        var seen = Set<String>()
        for item in try modelContext.fetch(descriptor) {
            // Only apps of clips the other devices already have: a local-only clip, a credential or a secret kept
            // here must not name its app to them.
            guard item.syncEmittedClock != nil, let bundleID = item.sourceBundleID, !bundleID.isEmpty,
                  seen.insert(bundleID).inserted else
            {
                continue
            }
            bundleIDs.append(bundleID)
            if bundleIDs.count == SyncAppCatalog.maxEntries { break }
        }
        var entries: [SyncAppCatalog.Entry] = []
        for bundleID in bundleIDs {
            let record = await resolver.resolve(bundleID: bundleID)
            guard !record.iconData.isEmpty, record.displayName != SourceAppRecord.unknownDisplayName else { continue }
            entries.append(.init(
                bundleID: bundleID, name: record.displayName, colorHex: record.dominantColorHex, icon: record.iconData
            ))
        }
        return SyncAppCatalog.bounded(entries)
    }

    /// The source color a record carries, adopted by a clip that has none of its own (a device that cannot sample
    /// the app's icon).
    static func adoptedSourceColor(current: String?, arrived: String?) -> String? {
        let placeholder = "#888888"
        guard let arrived, SyncAppCatalog.isColorHex(arrived), arrived.uppercased() != placeholder else {
            return current
        }
        guard let current, current.uppercased() != placeholder else { return arrived }
        return current
    }
}
