// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    func retentionSnapshot(expiringBefore: Date) throws -> RetentionSnapshot {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let items = try modelContext.fetch(descriptor)
        return RetentionSnapshot(
            candidates: items.map { ($0.id, $0.timestamp, $0.byteSize) },
            // #Predicate optional comparisons are fragile, so the expiry is compared in Swift.
            expired: items.compactMap { item in
                guard let expiry = item.expiresAt, expiry <= expiringBefore else { return nil }
                return item.id
            }
        )
    }
}

public extension StorageService {
    /// Removes the unpinned copies kept from allowed password managers: those made by `apps`, or by any built-in app
    /// when `apps` is nil. An allowance that ended or was revoked takes its copies with it, and none outlives a launch.
    /// A kept copy is a credential, or carries the expiry it was given at ingest (a kept copy that looks like a secret
    /// keeps that category instead), and a burn-after-paste mark is not an expiry.
    @discardableResult
    func removeKeptConcealedCopies(from apps: Set<String>?) throws -> Int {
        // One equality query per app: SQL cannot be generated for an IN over an optional column.
        var candidates: [ClipboardItem] = []
        for app in apps ?? ExclusionRules.defaultExcludedBundleIDs {
            candidates += try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { !$0.isPinned && $0.sourceBundleID == app }
            ))
        }
        var doomed = candidates.filter { item in
            item.sensitivity == .credential || item.expiresAt.map { $0 != .distantPast } ?? false
        }
        if apps == nil {
            let credential = SensitivityCategory.credential.rawValue
            let credentials = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { !$0.isPinned && $0.sensitivityRaw == credential }
            ))
            let known = Set(doomed.map(\.id))
            doomed += credentials.filter { !known.contains($0.id) }
        }
        guard !doomed.isEmpty else { return 0 }
        return try deleteItems(ids: doomed.map(\.id), reason: .retention)
    }
}
