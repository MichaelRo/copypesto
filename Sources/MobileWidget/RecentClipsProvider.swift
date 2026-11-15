// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import WidgetKit

struct RecentClipsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// One snapshot per timeline, opened fresh each time; further entries only move the ages, at each moment one reads
/// differently. The app reloads the timeline after every write.
struct RecentClipsProvider: TimelineProvider {
    func placeholder(in _: Context) -> RecentClipsEntry {
        RecentClipsEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentClipsEntry) -> Void) {
        completion(RecentClipsEntry(date: .now, snapshot: context.isPreview ? nil : WidgetSnapshotReader.read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RecentClipsEntry>) -> Void) {
        completion(Self.timeline(snapshot: WidgetSnapshotReader.read(), now: .now))
    }

    static func timeline(snapshot: WidgetSnapshot?, now: Date) -> Timeline<RecentClipsEntry> {
        let shown = Array((snapshot?.clips ?? []).prefix(WidgetSize.large.clipCount(accessibilityText: false)))
        let moments = WidgetContent.refreshDates(for: shown, after: now)
        let entries = [RecentClipsEntry(date: now, snapshot: snapshot)]
            + moments.map { RecentClipsEntry(date: $0, snapshot: snapshot) }
        return Timeline(entries: entries, policy: moments.isEmpty ? .never : .atEnd)
    }
}
