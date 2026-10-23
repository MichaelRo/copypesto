// SPDX-License-Identifier: MIT
import Foundation

/// Whether the backup is doing its job, in one word: it used to be implied by which buttons were showing, and a person
/// could not tell if it was on. Paused is what Clear Everything leaves when the backup is kept (ADR 0010): automatic
/// backup waits so the file still holds the old clips.
public enum BackupStatus: Equatable, Sendable {
    case off
    case on
    case paused

    public init(isEnabled: Bool, pausedAfterClear: Bool) {
        guard isEnabled else { self = .off
            return
        }
        self = pausedAfterClear ? .paused : .on
    }

    public var word: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        case .paused: "Paused"
        }
    }

    public var title: String {
        switch self {
        case .off: "Backup is off"
        case .on: "Backup is on"
        case .paused: "Backup is paused"
        }
    }

    public static func lastBackupText(_ date: Date?) -> String {
        guard let date else { return "Not yet" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(.autoupdatingCurrent))
    }
}
