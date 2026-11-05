// SPDX-License-Identifier: MIT
import Foundation

/// The date range chosen in the filter bar, or asked for in plain words. `custom` is a day or a range of days;
/// `last` is a rolling span back from now, worked out each time the filter is applied, so a clip copied after the
/// range was chosen is still in it.
public enum SearchDateFilter: Sendable, Hashable {
    case all, today, yesterday, week, month
    case custom(DateInterval)
    case last(TimeInterval)

    public var id: String {
        switch self {
        case .all: "all"
        case .today: "today"
        case .yesterday: "yesterday"
        case .week: "week"
        case .month: "month"
        case .custom: "custom"
        case .last: "last"
        }
    }

    /// A range someone spelled out, which wins over a preset when a question holds both.
    public var isExact: Bool {
        switch self {
        case .custom, .last: true
        default: false
        }
    }

    /// A preset the model or a person named, or nil.
    public static func preset(named name: String) -> SearchDateFilter? {
        [SearchDateFilter.all, .today, .yesterday, .week, .month].first { $0.id == name }
    }

    /// How the filter chip and the spoken summary name the range.
    public func label(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .all: "Any time"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case let .custom(range): Self.customLabel(range, now: now, calendar: calendar, locale: locale)
        case let .last(seconds): Self.relativeLabel(seconds)
        }
    }

    private static func customLabel(_ range: DateInterval, now: Date, calendar: Calendar, locale: Locale) -> String {
        let last = range.end.addingTimeInterval(-1)
        let first = dayText(range.start, now: now, calendar: calendar, locale: locale)
        guard !calendar.isDate(range.start, inSameDayAs: last) else { return first }
        return first + " \u{2013} " + dayText(last, now: now, calendar: calendar, locale: locale)
    }

    private static func relativeLabel(_ seconds: TimeInterval) -> String {
        let wholeHours = seconds >= 3600 && seconds.truncatingRemainder(dividingBy: 3600) == 0
        if wholeHours {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "Last hour" : "Last \(hours) hours"
        }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? "Last minute" : "Last \(minutes) minutes"
    }

    private static func dayText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}
