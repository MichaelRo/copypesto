// SPDX-License-Identifier: MIT
import Foundation

/// A span of recent history the user can clear. Resolves to a start time: everything from then until now.
public enum ClearRange: String, CaseIterable, Sendable {
    case lastFiveMinutes
    case lastHour
    case today
    case all

    public init?(automationName: String?) {
        switch automationName {
        case "hour": self = .lastHour
        case "today": self = .today
        case "all": self = .all
        default: return nil
        }
    }

    /// The earliest timestamp the range covers, or nil when it covers the whole history.
    public func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastFiveMinutes: now.addingTimeInterval(-300)
        case .lastHour: now.addingTimeInterval(-3600)
        case .today: calendar.startOfDay(for: now)
        case .all: nil
        }
    }

    public var summary: String {
        switch self {
        case .lastFiveMinutes: "everything copied in the last 5 minutes"
        case .lastHour: "everything copied in the last hour"
        case .today: "everything copied today"
        case .all: "your entire clipboard history"
        }
    }
}
