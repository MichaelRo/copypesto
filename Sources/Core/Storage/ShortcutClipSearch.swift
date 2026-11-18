// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// A clip as Shortcuts may see it: its id, a line of preview text and its kind. Never a secret's text.
public struct ShortcutClip: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let type: ClipboardType

    public var kindLabel: String {
        type.presentation.label
    }
}

/// What a Shortcuts action or an entity query may hand out (ADR 0003, ADR 0047). A clip holding a secret is masked
/// on screen, so a shortcut must not be a way round the mask: it is never matched and never returned, nor is a clip
/// still being judged or one the content filter covers.
public enum ShortcutClipSearch {
    public static let scanLimit = 500

    /// The Mac's Copy from Pesto rule: no secret, and the preview contains the query.
    public static func matches(_ item: ClipboardItem, query: String) -> Bool {
        item.sensitivityRaw == nil && item.displayPreviewText.localizedCaseInsensitiveContains(query)
    }

    public static func isOffered(_ item: ClipboardItem, nsfwMode: NSFWMode) -> Bool {
        !CardConcealment(
            screenShareBlur: false, nsfwBlurred: item.isNSFW && nsfwMode != .show,
            maskedSecret: item.sensitivityRaw != nil, secretShown: false, pendingAnalysis: item.analysisPending
        ).isConcealed && item.sensitivityRaw == nil
    }

    /// What may be kept ready for another app to insert without Pesto on screen (AutoFill, ADR 0051): what Shortcuts
    /// may have, but never a clip the content filter flagged whatever the filter's setting, nor one that expires,
    /// since the copy kept for insertion would outlive it.
    public static func isOfferedOutsidePesto(_ item: ClipboardItem) -> Bool {
        isOffered(item, nsfwMode: .hide) && !item.isNSFW && item.expiresAt == nil
    }

    public static func clip(for item: ClipboardItem, nsfwMode: NSFWMode) -> ShortcutClip? {
        guard isOffered(item, nsfwMode: nsfwMode) else { return nil }
        let preview = item.customTitle ?? item.displayPreviewText
        let line = preview.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = line.trimmingCharacters(in: .whitespaces)
        return ShortcutClip(
            id: item.id, title: String((title.isEmpty ? item.type.presentation.label : title).prefix(200)),
            type: item.type
        )
    }

    /// The newest offered clips whose preview or title contains `query` (all of them for an empty query).
    public static func search(
        _ query: String, in context: ModelContext, nsfwMode: NSFWMode, limit: Int = 20
    ) throws
    -> [ShortcutClip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try newest(in: context).lazy.filter { item in
            trimmed.isEmpty || item.displayPreviewText.localizedCaseInsensitiveContains(trimmed)
                || (item.customTitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        .compactMap { clip(for: $0, nsfwMode: nsfwMode) }.prefix(limit).map(\.self)
    }

    public static func clips(ids: [UUID], in context: ModelContext, nsfwMode: NSFWMode) throws -> [ShortcutClip] {
        let wanted = Set(ids)
        let found = try context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { wanted.contains($0.id) }))
        let byID = Dictionary(found.compactMap { clip(for: $0, nsfwMode: nsfwMode) }.map { ($0.id, $0) }) { a, _ in a }
        return ids.compactMap { byID[$0] }
    }

    private static func newest(in context: ModelContext) throws -> [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = scanLimit
        return try context.fetch(descriptor)
    }
}
