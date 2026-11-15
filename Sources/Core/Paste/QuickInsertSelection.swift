// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the quick-insert set holds (ADR 0051): pinned clips, then snippets that need nothing from the person,
/// then the newest text, each newest first, within `QuickInsertPolicy`. Only text a field can take (text, code, a
/// link as its address, a color as its value), and only what `ShortcutClipSearch.isOfferedOutsidePesto` allows.
public enum QuickInsertSelection {
    private static let insertableTypes: Set<ClipboardType> = [.text, .code, .url, .color]

    @MainActor
    public static func set(in context: ModelContext, now: Date) throws -> QuickInsertSet {
        var pinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        pinned.fetchLimit = QuickInsertPolicy.scanLimit
        var recent = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recent.fetchLimit = QuickInsertPolicy.scanLimit
        let entries = try entries(pinned: context.fetch(pinned), recent: context.fetch(recent)) {
            $0.blob?.decryptedText()
        }
        return QuickInsertSet(createdAt: now, entries: entries)
    }

    /// `pinned` and `recent` come newest first; `text` opens a clip's whole text, and is asked only of clips that
    /// may be offered.
    public static func entries(
        pinned: [ClipboardItem], recent: [ClipboardItem], text: (ClipboardItem) -> String?
    )
    -> [QuickInsertEntry] {
        var budget = QuickInsertPolicy.maxTotalBytes
        var pins: [QuickInsertEntry] = []
        var snippets: [QuickInsertEntry] = []
        var latest: [QuickInsertEntry] = []
        func take(_ item: ClipboardItem, pinned: Bool) {
            guard isEligible(item), let body = text(item), !body.isEmpty,
                  body.utf8.count <= QuickInsertPolicy.maxEntryBytes, body.utf8.count <= budget else { return }
            let isSnippet = pinned && TemplateExpander.containsPlaceholders(body)
            if isSnippet {
                guard snippets.count < QuickInsertPolicy.maxSnippets, TemplateExpander.fillsWithoutAsking(body) else {
                    return
                }
            } else if pinned ? pins.count >= QuickInsertPolicy.maxPinned : latest.count >= QuickInsertPolicy.maxRecent {
                return
            }
            let section: QuickInsertEntry.Section = isSnippet ? .snippets : pinned ? .pinned : .recent
            let entry = QuickInsertEntry(
                id: item.id, section: section, kind: item.type, title: title(of: item, text: body), text: body,
                expandsOnInsert: isSnippet
            )
            budget -= body.utf8.count
            switch section {
            case .pinned: pins.append(entry)
            case .snippets: snippets.append(entry)
            case .recent: latest.append(entry)
            }
        }
        pinned.forEach { take($0, pinned: true) }
        recent.forEach { take($0, pinned: false) }
        return pins + snippets + latest
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        insertableTypes.contains(item.type) && ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func title(of item: ClipboardItem, text: String) -> String {
        let named = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let chosen = named.isEmpty ? line : named
        return String((chosen.isEmpty ? item.type.presentation.label : chosen)
            .prefix(QuickInsertPolicy.maxTitleCharacters))
    }
}
