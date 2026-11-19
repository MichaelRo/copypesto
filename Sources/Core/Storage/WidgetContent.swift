// SPDX-License-Identifier: MIT
import Foundation

/// What one widget draws from the snapshot it opened (ADR 0052): no snapshot is "Open Pesto to show your clips", a
/// locked one is "Locked", a hidden one (the Mac covering clip contents, ADR 0059) "Clip contents hidden", an empty
/// one "No clips yet", otherwise the newest clips its family has room for. A widget set to a collection the snapshot
/// does not carry (none chosen yet, deleted, or past `WidgetSnapshotPolicy.maxCollections`) is "Choose a collection"
/// (ADR 0060).
public struct WidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case unavailable
        case locked
        case hidden
        case noCollection
        case empty
        case clips
    }

    public let state: State
    public let clips: [WidgetClip]
    public let theme: WidgetSnapshot.Theme

    public let source: WidgetClipSource
    /// The collection a widget set to one shows, while the snapshot carries it.
    public let collection: WidgetCollection?

    public init(
        snapshot: WidgetSnapshot?, size: WidgetSize, source: WidgetClipSource = .recent, accessibilityText: Bool = false
    ) {
        self.source = source
        theme = snapshot?.theme ?? .brand
        if case let .collection(id) = source, let id {
            collection = snapshot?.collection(id: id)
        } else {
            collection = nil
        }
        let all = snapshot?.clips(from: source) ?? []
        clips = Array(all.prefix(size.clipCount(accessibilityText: accessibilityText)))
        state = Self.state(of: snapshot, source: source, collection: collection, showing: clips)
    }

    private static func state(
        of snapshot: WidgetSnapshot?, source: WidgetClipSource, collection: WidgetCollection?,
        showing clips: [WidgetClip]
    )
    -> State {
        guard let snapshot else { return .unavailable }
        if snapshot.isLocked { return .locked }
        if snapshot.isHidden { return .hidden }
        if case .collection = source, collection == nil { return .noCollection }
        return clips.isEmpty ? .empty : .clips
    }

    /// The moments after `now` when an age the widget shows (`CardAge.text`) reads differently, soonest first, at most
    /// `limit` of them: the timeline's entries, so the ages move without the widget being asked again.
    public static func refreshDates(for clips: [WidgetClip], after now: Date, limit: Int = 60) -> [Date] {
        var dates: Set<Date> = []
        for clip in clips {
            var moment = now
            for _ in 0..<limit {
                moment += CardAge.untilNextChange(interval: moment.timeIntervalSince(clip.date))
                dates.insert(moment)
            }
        }
        return Array(dates.sorted().prefix(limit))
    }
}
