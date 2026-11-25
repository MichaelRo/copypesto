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

    /// A single calendar day or inclusive range of days, normalized regardless of argument order to half-open
    /// `[startOfFirstDay, startOfDayAfterLast)` bounds matching `ShelfFilter` and `HistoryIndex`.
    public static func customRange(from start: Date, to end: Date, calendar: Calendar = .current) -> SearchDateFilter {
        let low = min(start, end)
        let high = max(start, end)
        let startOfLow = calendar.startOfDay(for: low)
        let startOfHigh = calendar.startOfDay(for: high)
        let endOfHigh = calendar.date(byAdding: .day, value: 1, to: startOfHigh)
            ?? startOfHigh.addingTimeInterval(86_400)
        return .custom(DateInterval(start: startOfLow, end: endOfHigh))
    }

    /// The half-open bounds covered by this filter at `now`, or nil for `.all`.
    public func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        case .yesterday:
            let end = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86_400)
            return DateInterval(start: start, end: end)
        case .week:
            return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .month:
            return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case let .custom(range):
            return range
        case let .last(seconds):
            return DateInterval(start: now.addingTimeInterval(-max(0, seconds)), end: now)
        }
    }

    /// How the filter chip and the spoken summary name the range.
    public func label(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .all: String(localized: "Any time")
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .week: String(localized: "Last 7 days")
        case .month: String(localized: "Last 30 days")
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
        if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
            let hours = Int(seconds / 3600)
            return String(localized: "Last \(hours) hours")
        }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return String(localized: "Last \(minutes) minutes")
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
