// SPDX-License-Identifier: MIT
import Foundation

/// What the Mac's widget snapshot may hold right now (ADR 0058): the clips; or, with the History Lock switched on,
/// Locked (ADR 0055's default, and the Mac has no setting that keeps clips there while it is); or, while clip contents
/// are covered, Hidden. The lock wins over the cover: both hold no clip, and Locked says how to see them again.
public enum WidgetSnapshotGate: Equatable, Sendable {
    case clips
    case locked
    case hidden

    public static func decide(lockEnabled: Bool, isCovered: Bool) -> WidgetSnapshotGate {
        if lockEnabled { return .locked }
        return isCovered ? .hidden : .clips
    }

    /// The snapshot that stands in for the clips, or nil when the clips may be written.
    public func placeholder(theme: WidgetSnapshot.Theme, at date: Date) -> WidgetSnapshot? {
        switch self {
        case .clips: nil
        case .locked: .locked(theme: theme, at: date)
        case .hidden: .hidden(theme: theme, at: date)
        }
    }
}
