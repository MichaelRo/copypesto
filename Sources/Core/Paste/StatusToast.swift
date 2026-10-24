// SPDX-License-Identifier: MIT
import Foundation

/// A small notice Pesto floats over the screen without taking focus. Its words and symbol are the view's.
public enum StatusToast: Equatable, Sendable {
    case manualPaste(ManualPasteToast)
    case updatesUnavailable
    /// A manual Check for Updates found nothing newer.
    case upToDate
    /// A paste found every file of the clip gone, and wrote nothing (the shelf has closed by then, so its banner is not
    /// seen).
    case filesGone

    public enum Placement: Equatable, Sendable {
        case aboveDock
        case belowMenuBar
    }

    public var isClickable: Bool {
        switch self {
        case let .manualPaste(toast): toast.isClickable
        case .updatesUnavailable, .upToDate, .filesGone: false
        }
    }

    public var visibleSeconds: Double {
        switch self {
        case let .manualPaste(toast): toast.visibleSeconds
        case .updatesUnavailable, .upToDate, .filesGone: 4
        }
    }

    /// The update notice answers a click in the menu bar, so it appears there; a paste notice belongs to the app
    /// the person is pasting into.
    public var placement: Placement {
        switch self {
        case .manualPaste, .filesGone: .aboveDock
        case .updatesUnavailable, .upToDate: .belowMenuBar
        }
    }
}
