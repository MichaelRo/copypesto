// SPDX-License-Identifier: MIT
import Foundation

/// Reads the dates a person types into Ask beyond the five presets: the last few hours or minutes, a named day and a
/// range between two days. It works on the lowercased words of the question and says how many it used.
struct DateRangeParser {
    let now: Date
    let calendar: Calendar

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
        "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]

    private static let connectors: Set<String> = ["and", "to", "until", "through", "-"]

    func parse(_ words: [String], at index: Int) -> (range: SearchDateFilter, used: Int)? {
        if let span = parseBetween(words, at: index) { return span }
        if let relative = parseRelative(words, at: index) { return relative }
        if let day = parseDay(words, at: index) { return (.custom(day.interval), day.used) }
        return nil
    }

    /// Two days joined by "and", "to", "until" or a dash, after an optional "between" or "from".
    private func parseBetween(_ words: [String], at index: Int) -> (range: SearchDateFilter, used: Int)? {
        let lead = ["between", "from"].contains(words[index]) ? 1 : 0
        guard let first = parseDay(words, at: index + lead) else { return nil }
        let connector = index + lead + first.used
        guard connector < words.count, Self.connectors.contains(words[connector]),
              let second = parseDay(words, at: connector + 1) else { return nil }
        let range = DateInterval(
            start: min(first.interval.start, second.interval.start), end: max(first.interval.end, second.interval.end)
        )
        return (.custom(range), lead + first.used + 1 + second.used)
    }

    private func parseRelative(_ words: [String], at index: Int) -> (range: SearchDateFilter, used: Int)? {
        let word = words[index]
        let next = index + 1 < words.count ? words[index + 1] : ""
        // "last minute" is an idiom ("a last minute deal"); "last hour" is a range.
        if ["last", "past"].contains(word), next == "hour" { return (.last(3600), 2) }
        let count = Int(word) ?? RuleBasedQueryInterpreter.numberWords[word] ?? (["a", "an"].contains(word) ? 1 : nil)
        if let count, count > 0, let unit = Self.seconds(per: next) { return (.last(Double(count) * unit), 2) }
        return nil
    }

    private static func seconds(per word: String) -> TimeInterval? {
        switch word {
        case "hour", "hours", "hr", "hrs": 3600
        case "minute", "minutes", "min", "mins": 60
        default: nil
        }
    }

    private func parseDay(_ words: [String], at index: Int) -> (interval: DateInterval, used: Int)? {
        guard index < words.count else { return nil }
        let word = words[index]
        if let iso = isoDay(word) { return (iso, 1) }
        if let month = Self.months[word], index + 1 < words.count, let day = dayNumber(words[index + 1]) {
            return resolve(month: month, day: day, year: year(in: words, at: index + 2), used: 2)
        }
        if let day = dayNumber(word), index + 1 < words.count, let month = Self.months[words[index + 1]] {
            return resolve(month: month, day: day, year: year(in: words, at: index + 2), used: 2)
        }
        if let weekday = Self.weekdays[word], index > 0, ["on", "last", "this"].contains(words[index - 1]) {
            return lastWeekday(weekday)
        }
        return nil
    }

    private func year(in words: [String], at index: Int) -> (value: Int, used: Int)? {
        guard index < words.count, words[index].count == 4, let value = Int(words[index]),
              (1990...2100).contains(value) else { return nil }
        return (value, 1)
    }

    private func dayNumber(_ word: String) -> Int? {
        let digits = word.prefix(while: \.isNumber)
        let suffix = word.dropFirst(digits.count)
        guard !digits.isEmpty, ["", "st", "nd", "rd", "th"].contains(String(suffix)),
              let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    private func isoDay(_ word: String) -> DateInterval? {
        let parts = word.split(separator: "-").map { Int($0) }
        guard parts.count == 3, word.count == 10, let year = parts[0], let month = parts[1], let day = parts[2] else {
            return nil
        }
        return interval(year: year, month: month, day: day)
    }

    private func resolve(
        month: Int, day: Int, year: (value: Int, used: Int)?, used: Int
    )
    -> (interval: DateInterval, used: Int)? {
        if let year {
            return interval(year: year.value, month: month, day: day).map { ($0, used + year.used) }
        }
        let thisYear = calendar.component(.year, from: now)
        guard let candidate = interval(year: thisYear, month: month, day: day) else { return nil }
        if candidate.start > now {
            return interval(year: thisYear - 1, month: month, day: day).map { ($0, used) }
        }
        return (candidate, used)
    }

    private func interval(year: Int, month: Int, day: Int) -> DateInterval? {
        let components = DateComponents(year: year, month: month, day: day)
        guard let start = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: start) == components,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func lastWeekday(_ weekday: Int) -> (interval: DateInterval, used: Int)? {
        let today = calendar.startOfDay(for: now)
        for back in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  calendar.component(.weekday, from: day) == weekday,
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            return (DateInterval(start: day, end: end), 1)
        }
        return nil
    }
}
