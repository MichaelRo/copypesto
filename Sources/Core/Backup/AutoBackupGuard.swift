// SPDX-License-Identifier: MIT
import Foundation

public enum AutoBackupRefusal: Equatable, Sendable {
    case storeNotOnDisk
    case unreadableClips(Int)
    case muchSmaller(now: Int, before: Int)
    case keptAfterClear
    /// The file in the folder was written under a key this Mac does not have, so replacing it would destroy it.
    case anotherKeyInFolder
}

/// Decides whether a backup may replace the one already in the folder. The file is the person's only way back after a
/// store that will not open, so a history that looks broken must never overwrite it.
public enum AutoBackupGuard {
    static let smallestHistoryJudged = 10

    /// The count the next backup is judged against: the largest history the file has held since the person last
    /// confirmed a smaller one. It follows growth but not shrinkage, because a count that moves down with every backup
    /// lets a history lose a little each run and never be refused (ADR 0010).
    public static func nextBaseline(previous: Int?, written: Int, confirmed: Bool) -> Int {
        if confirmed { return written }
        return max(previous ?? 0, written)
    }

    public static func refusal(
        storeIsOnDisk: Bool,
        unreadable: Int,
        clips: Int,
        lastClips: Int?,
        allowShrink: Bool,
        pausedAfterClear: Bool = false,
        fileUsesAnotherKey: Bool = false
    )
    -> AutoBackupRefusal? {
        if !storeIsOnDisk { return .storeNotOnDisk }
        if fileUsesAnotherKey { return .anotherKeyInFolder }
        if unreadable > 0 { return .unreadableClips(unreadable) }
        if pausedAfterClear, !allowShrink { return .keptAfterClear }
        if !allowShrink, let lastClips, lastClips >= smallestHistoryJudged, clips * 2 < lastClips {
            return .muchSmaller(now: clips, before: lastClips)
        }
        return nil
    }
}
