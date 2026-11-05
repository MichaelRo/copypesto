// SPDX-License-Identifier: MIT
import Foundation

extension SearchDateFilter {
    /// How the filter chip and the spoken summary name the range.
    public func label(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .all: "Any time"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case let .custom(range): Self.customLabel(range, now: now, calendar: calendar)
        }
    }

    private static func customLabel(_ range: DateInterval, now: Date, calendar: Calendar) -> String {
        let startsAtMidnight = calendar.startOfDay(for: range.start) == range.start
        guard startsAtMidnight else { return relativeLabel(range.duration) }
        let last = range.end.addingTimeInterval(-1)
        let first = dayText(range.start, now: now, calendar: calendar)
        guard !calendar.isDate(range.start, inSameDayAs: last) else { return first }
        return first + " \u{2013} " + dayText(last, now: now, calendar: calendar)
    }

    private static func relativeLabel(_ duration: TimeInterval) -> String {
        let hours = Int((duration / 3600).rounded())
        if duration >= 3600 {
            return hours == 1 ? "Last hour" : "Last \(hours) hours"
        }
        let minutes = max(1, Int((duration / 60).rounded()))
        return minutes == 1 ? "Last minute" : "Last \(minutes) minutes"
    }

    private static func dayText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
