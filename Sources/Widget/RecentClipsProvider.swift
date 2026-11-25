// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import WidgetKit

struct RecentClipsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var tapAction: WidgetTapAction = .copy
    var source: WidgetClipSource = .recent
    /// The tile that copied in place a moment ago, which says Copied until the next entry.
    var copiedID: UUID?
    /// The page a medium or large widget shows (ADR 0067).
    var page = 0
}

extension WidgetSize {
    init(family: WidgetFamily) {
        self = switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        default: .medium
        }
    }
}

/// One snapshot per timeline, opened fresh each time; further entries only move the ages, at each moment one reads
/// differently, and end a tile's Copied. The app reloads the timeline after every write; an in-place copy reloads it
/// too.
struct RecentClipsProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> RecentClipsEntry {
        RecentClipsEntry(date: .now, snapshot: nil)
    }

    func snapshot(for configuration: RecentClipsConfiguration, in context: Context) async -> RecentClipsEntry {
        RecentClipsEntry(
            date: .now, snapshot: context.isPreview ? nil : WidgetSnapshotReader.read(),
            tapAction: configuration.tapAction.action, source: configuration.clipSource
        )
    }

    func timeline(
        for configuration: RecentClipsConfiguration,
        in context: Context
    ) async
    -> Timeline<RecentClipsEntry> {
        let snapshot = WidgetSnapshotReader.read()
        let size = WidgetSize(family: context.family)
        let key = WidgetPaging.key(source: configuration.clipSource, size: size)
        let count = snapshot?.clips(from: configuration.clipSource).count ?? 0
        let page = snapshot.map {
            WidgetPageStore.page(
                for: key, snapshotCreatedAt: $0.createdAt,
                pageCount: size.pageCount(of: count, accessibilityText: false), now: .now
            )
        } ?? 0
        return Self.timeline(
            snapshot: snapshot, now: .now, tapAction: configuration.tapAction.action,
            source: configuration.clipSource, copied: WidgetCopyRecord.recent(at: .now), page: page,
            pageResetAt: page > 0 ? WidgetPageStore.resetMoment(for: key) : nil
        )
    }

    static func timeline(
        snapshot: WidgetSnapshot?, now: Date, tapAction: WidgetTapAction = .copy, source: WidgetClipSource = .recent,
        copied: (id: UUID, date: Date)? = nil, page: Int = 0, pageResetAt: Date? = nil
    )
    -> Timeline<RecentClipsEntry> {
        let alreadyLocked = snapshot?.isLockedAt(now) ?? false
        // Every page's clips: a page turned between two entries still shows ages that move.
        let shown = alreadyLocked ? [] : snapshot?.clips(from: source) ?? []
        var moments = WidgetContent.refreshDates(for: shown, after: now)
        if let expiresAt = snapshot?.expiresAt, expiresAt > now {
            moments = moments.filter { $0 < expiresAt } + [expiresAt]
        }
        let copiedUntil = copied.map { $0.date + WidgetSnapshotPolicy.copiedFeedback }
        if let copiedUntil { moments.append(copiedUntil) }
        if let pageResetAt, pageResetAt > now { moments.append(pageResetAt) }
        moments = Array(Set(moments).sorted())
        func entry(_ date: Date) -> RecentClipsEntry {
            let showsCopied = copiedUntil.map { date < $0 } ?? false
            let pageShown = pageResetAt.map { date < $0 } ?? true ? page : 0
            return RecentClipsEntry(
                date: date, snapshot: snapshot, tapAction: tapAction, source: source,
                copiedID: showsCopied ? copied?.id : nil, page: pageShown
            )
        }
        return Timeline(entries: [entry(now)] + moments.map(entry), policy: moments.isEmpty ? .never : .atEnd)
    }
}
