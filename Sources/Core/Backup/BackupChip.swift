// SPDX-License-Identifier: MIT
import Foundation

public enum BackupProblem: String, Equatable, Sendable {
    case folderMissing
    case failed
    case refused
}

/// What Settings → Data says about the backup in one glance: the summary chip and the fourth stat tile. It is derived
/// from preferences only, so opening the pane never reads the Keychain (`Features/Settings/CLAUDE.md`).
public enum BackupChip: Equatable, Sendable {
    case off
    case waiting
    case upToDate(Date)
    case paused
    case needsYou(BackupProblem)

    public init(status: BackupStatus, lastBackup: Date?, problem: BackupProblem?) {
        switch status {
        case .off: self = .off
        case .paused: self = .paused
        case .on:
            if let problem {
                self = .needsYou(problem)
            } else if let lastBackup {
                self = .upToDate(lastBackup)
            } else {
                self = .waiting
            }
        }
    }

    public func tileValue(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    )
    -> String {
        switch self {
        case .off: "Off"
        case .waiting: "Not yet"
        case .paused: "Paused"
        case .needsYou: "Needs you"
        case let .upToDate(date): Self.when(date, now: now, calendar: calendar, locale: locale)
        }
    }

    public var tileLabel: String {
        if case .upToDate = self { return "Backed up" }
        return "Backup"
    }

    public func summaryText(
        now _: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    )
    -> String {
        switch self {
        case .off: "Backup: Off"
        case .waiting: "Backup: Not written yet"
        case .paused: "Backup: Paused"
        case let .needsYou(problem): "Backup: \(problem.title)"
        case let .upToDate(date):
            "Backup: Up to date, saved at \(Self.timeText(date, calendar: calendar, locale: locale))"
        }
    }

    private static func timeText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(
            date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone
        ))
    }

    private static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return timeText(date, calendar: calendar, locale: locale) }
        return date.formatted(Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone
        ).month(.abbreviated).day())
    }
}

public extension BackupProblem {
    var title: String {
        switch self {
        case .folderMissing: "Folder Missing"
        case .failed: "Could Not Save"
        case .refused: "Needs You"
        }
    }
}
