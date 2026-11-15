// SPDX-License-Identifier: MIT
import Foundation

/// What one widget draws from the snapshot it opened (ADR 0052): no snapshot is "Open Pesto to show your clips", an
/// empty one is "No clips yet", otherwise the newest clips its family has room for.
public struct WidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case unavailable
        case empty
        case clips
    }

    public let state: State
    public let clips: [WidgetClip]
    public let theme: WidgetSnapshot.Theme

    public init(snapshot: WidgetSnapshot?, size: WidgetSize, accessibilityText: Bool = false) {
        theme = snapshot?.theme ?? .brand
        clips = Array((snapshot?.clips ?? []).prefix(size.clipCount(accessibilityText: accessibilityText)))
        state = snapshot == nil ? .unavailable : clips.isEmpty ? .empty : .clips
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
