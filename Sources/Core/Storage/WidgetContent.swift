// SPDX-License-Identifier: MIT
import Foundation

/// What one widget draws from the snapshot it opened (ADR 0052): no snapshot is "Open Pesto to show your clips", a
/// locked one is "Locked", an
/// empty one is "No clips yet", otherwise the newest clips its family has room for.
public struct WidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case unavailable
        case locked
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
        state = if snapshot == nil { .unavailable } else if snapshot?.isLocked == true { .locked } else if clips
            .isEmpty { .empty } else { .clips }
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
