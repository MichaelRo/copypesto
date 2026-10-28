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

        var recentDesc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                $0.pasteCount >= 1 && $0.sensitivityRaw == nil && $0.isNSFW == false && $0.analysisPending == false
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentDesc.fetchLimit = 10
        let recent = try modelContext.fetch(recentDesc)

        let shortcutDesc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.pinnedHotkeyIndex != nil }
        )
        let shortcutHolders = try modelContext.fetch(shortcutDesc)

        var clipsByID: [UUID: ShelfClipFacts] = [:]

        let windowStart = ItemMetadata.dayNumber(of: .now) - ItemMetadata.pasteDayWindow
        func toFacts(_ item: ClipboardItem) -> ShelfClipFacts {
            let family = familyFacts(of: item)
            return ShelfClipFacts(
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
                shelfPastesThisRun: 0,
                pasteDaysInWindow: (item.metadata.pasteDays ?? []).count(where: { $0 > windowStart }),
                familySize: family.size,
                familyDays: family.days,
                familyRepresentative: family.representative
            )
        }

        for item in frequent + recent where clipsByID[item.id] == nil {
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

    /// How many clips look like `item` (itself included), over how many days they were copied, and the clip that stands
    /// for them all (the smallest id), so one answer silences the family.
    private func familyFacts(of item: ClipboardItem) -> FamilyFacts {
        let alone = FamilyFacts(size: 1, days: 1, representative: nil)
        guard item.type == .text || item.type == .code else { return alone }
        let matches = lookalikes(of: item.id)
        guard !matches.isEmpty else { return alone }
        let ids = matches.map(\.id) + [item.id]
        let members = (try? modelContext.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { ids.contains($0.id) }
        ))) ?? []
        let days = Set(members.map { ItemMetadata.dayNumber(of: $0.timestamp) }).count
        let representative = ids.min { $0.uuidString < $1.uuidString }
        return FamilyFacts(size: ids.count, days: max(1, days), representative: representative)
    }

    private struct FamilyFacts {
        let size: Int
        let days: Int
        let representative: UUID?
    }
}
