// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    func retentionSnapshot(expiringBefore: Date) throws -> RetentionSnapshot {
        let candidateDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.collectionID == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let candidates = try modelContext.fetch(candidateDescriptor)
        let ttlDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.expiresAt != nil }
        )
        let ttlItems = try modelContext.fetch(ttlDescriptor)
        return RetentionSnapshot(
            candidates: candidates.map { ($0.id, $0.timestamp, $0.byteSize) },
            // #Predicate optional comparisons are fragile, so the expiry is compared in Swift.
            expired: ttlItems.compactMap { item in
                guard let expiry = item.expiresAt, expiry <= expiringBefore else { return nil }
                return item.id
            }
        )
    }

    /// Non-pinned items the range covers: everything from its start until now (all of it for `.all`).
    private func nonPinnedItems(in range: ClearRange, now: Date) throws -> [ClipboardItem] {
        let descriptor: FetchDescriptor<ClipboardItem> = if let start = range.start(now: now) {
            FetchDescriptor(predicate: #Predicate { !$0.isPinned && $0.collectionID == nil && $0.timestamp >= start })
        } else {
            FetchDescriptor(predicate: #Predicate { !$0.isPinned && $0.collectionID == nil })
        }
        return try modelContext.fetch(descriptor)
    }
}

public extension StorageService {
    func nonPinnedCount(in range: ClearRange, now: Date = .now) throws -> Int {
        try nonPinnedItems(in: range, now: now).count
    }

    @discardableResult
    func clearNonPinned(in range: ClearRange, now: Date = .now) throws -> [UUID] {
        let items = try nonPinnedItems(in: range, now: now)
        let ids = items.map(\.id)
        undoHistory.clear()
        items.forEach { modelContext.delete($0) }
        try saveOrRollback()
        ids.forEach { similarity.remove($0) }
        PreviewTextCache.shared.clear()
        linkPreviews.delete(ids: ids)
        recognizedTexts.delete(ids: ids)
        linkPreviewCache.clear()
        lastItemStore.clear()
        if range == .all {
            wipeSuggestionLedger?()
        }
        return ids
    }

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
