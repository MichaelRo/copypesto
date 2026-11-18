// SPDX-License-Identifier: MIT
import Foundation

/// The words a decoded token's times are shown in, on the Mac's popover and the iOS sheet alike.
public enum JWTDecodingText {
    /// In the given calendar and locale, so a snapshot draws the same on any device; on a person's own those are
    /// theirs.
    public static func dateText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(
            date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone
        ))
    }

    public static func validityText(
        _ validity: JWTDecoding.Validity,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    )
    -> String? {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        switch validity {
        case let .expired(date):
            return String(localized: "Expired \(relative.localizedString(for: date, relativeTo: now))")
        case let .notYetValid(date):
            return String(localized: "Not valid until \(dateText(date, calendar: calendar, locale: locale))")
        case let .validUntil(date):
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.day, .hour, .minute, .second]
            let span = formatter.string(from: now, to: date) ?? ""
            return String(localized: "Valid for \(span)")
        case .noExpiry:
            return nil
        }
    }
}
