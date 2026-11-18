// SPDX-License-Identifier: MIT
import Foundation

/// What one widget draws from the snapshot it opened (ADR 0052): no snapshot is "Open Pesto to show your clips", a
/// locked one is "Locked", a hidden one (the Mac covering clip contents, ADR 0059) "Clip contents hidden", an empty
/// one "No clips yet", otherwise the newest clips its family has room for.
public struct WidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case unavailable
        case locked
        case hidden
        case empty
        case clips
    }

    public let state: State
    public let clips: [WidgetClip]
    public let theme: WidgetSnapshot.Theme

    public let source: WidgetClipSource

    public init(
        snapshot: WidgetSnapshot?, size: WidgetSize, source: WidgetClipSource = .recent, accessibilityText: Bool = false
    ) {
        self.source = source
        theme = snapshot?.theme ?? .brand
        let all = snapshot?.clips(from: source) ?? []
        clips = Array(all.prefix(size.clipCount(accessibilityText: accessibilityText)))
        state = Self.state(of: snapshot, showing: clips)
    }

    private static func state(of snapshot: WidgetSnapshot?, showing clips: [WidgetClip]) -> State {
        guard let snapshot else { return .unavailable }
        if snapshot.isLocked { return .locked }
        if snapshot.isHidden { return .hidden }
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
