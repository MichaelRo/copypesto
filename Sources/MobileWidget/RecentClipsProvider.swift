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
            tapAction: configuration.tapAction.action, source: configuration.source.source
        )
    }

    func timeline(for configuration: RecentClipsConfiguration, in _: Context) async -> Timeline<RecentClipsEntry> {
        Self.timeline(
            snapshot: WidgetSnapshotReader.read(), now: .now, tapAction: configuration.tapAction.action,
            source: configuration.source.source, copied: WidgetCopyRecord.recent(at: .now)
        )
    }

    static func timeline(
        snapshot: WidgetSnapshot?, now: Date, tapAction: WidgetTapAction = .copy, source: WidgetClipSource = .recent,
        copied: (id: UUID, date: Date)? = nil
    )
    -> Timeline<RecentClipsEntry> {
        let shown = Array((snapshot?.clips(from: source) ?? [])
            .prefix(WidgetSize.large.clipCount(accessibilityText: false)))
        var moments = WidgetContent.refreshDates(for: shown, after: now)
        let copiedUntil = copied.map { $0.date + WidgetSnapshotPolicy.copiedFeedback }
        if let copiedUntil { moments = Array(Set(moments + [copiedUntil]).sorted()) }
        func entry(_ date: Date) -> RecentClipsEntry {
            let showsCopied = copiedUntil.map { date < $0 } ?? false
            return RecentClipsEntry(
                date: date, snapshot: snapshot, tapAction: tapAction, source: source,
                copiedID: showsCopied ? copied?.id : nil
            )
        }
        return Timeline(entries: [entry(now)] + moments.map(entry), policy: moments.isEmpty ? .never : .atEnd)
    }
}
