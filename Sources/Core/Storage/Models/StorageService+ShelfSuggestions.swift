// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Records that a ⌃1–9 shortcut was used to paste this clip. Skipped if already set to today.
    func noteShortcutUsed(id: UUID, at now: Date = .now, calendar: Calendar = .current) throws {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first, item.pinnedHotkeyIndex != nil else { return }

        let today = calendar.startOfDay(for: now)
        if item.shortcutLastUsedAt == today { return }

        item.shortcutLastUsedAt = today
        try saveOrRollback()
    }

    /// Gathers lightweight facts needed by ShelfSuggestionPolicy without decrypting any content.
    func shelfSuggestionFacts(unavailableSlots: Set<Int>) throws -> ShelfSuggestionFacts {
        var frequentDesc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                $0.pasteCount >= 3 && $0.sensitivityRaw == nil && $0.isNSFW == false && $0.analysisPending == false
            },
            sortBy: [SortDescriptor(\.pasteCount, order: .reverse)]
        )
        frequentDesc.fetchLimit = 20

        let frequent = try modelContext.fetch(frequentDesc)

        let shortcutDesc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.pinnedHotkeyIndex != nil }
        )
        let shortcutHolders = try modelContext.fetch(shortcutDesc)

        var clipsByID: [UUID: ShelfClipFacts] = [:]

        func toFacts(_ item: ClipboardItem) -> ShelfClipFacts {
            ShelfClipFacts(
                id: item.id,
                pasteCount: item.pasteCount,
                lastUsedAt: item.timestamp,
                isPinned: item.isPinned,
                shortcutSlot: item.pinnedHotkeyIndex,
                shortcutLastUsedAt: item.shortcutLastUsedAt,
                kind: item.type,
                textLength: item.textLength,
                isSensitive: item.sensitivityRaw != nil,
                isNSFW: item.isNSFW,
                analysisPending: item.analysisPending,
                expires: item.expiresAt != nil,
                shelfPastesThisRun: 0
            )
        }

        for item in frequent {
            clipsByID[item.id] = toFacts(item)
        }
        for item in shortcutHolders where clipsByID[item.id] == nil {
            clipsByID[item.id] = toFacts(item)
        }

        let assigned = Set(shortcutHolders.compactMap(\.pinnedHotkeyIndex))
        return ShelfSuggestionFacts(
            clips: Array(clipsByID.values),
            assignedSlots: assigned,
            unavailableSlots: unavailableSlots
        )
    }
}
