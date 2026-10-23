// SPDX-License-Identifier: MIT
import Foundation

/// A one-event calendar file (RFC 5545) for "Add to Calendar". Opening the file hands it to the user's calendar app,
/// so Pesto never needs calendar permission.
public enum ICalendarEvent {
    public static func make(
        title: String,
        start: Date,
        hasTime: Bool,
        uid: String = UUID().uuidString,
        now: Date = .now,
        calendar: Calendar = .current
    )
    -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pesto//Clip Action//EN", "BEGIN:VEVENT"]
        lines.append("UID:\(uid)@pesto")
        lines.append("DTSTAMP:\(utc(now))")
        if hasTime {
            lines.append("DTSTART:\(utc(start))")
            lines.append("DTEND:\(utc(start.addingTimeInterval(3600)))")
        } else {
            lines.append("DTSTART;VALUE=DATE:\(day(start, calendar))")
            let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            lines.append("DTEND;VALUE=DATE:\(day(next, calendar))")
        }
        lines.append("SUMMARY:\(escape(title))")
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func utc(_ date: Date) -> String {
        format(date, "yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC") ?? .gmt)
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        format(date, "yyyyMMdd", calendar.timeZone)
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
