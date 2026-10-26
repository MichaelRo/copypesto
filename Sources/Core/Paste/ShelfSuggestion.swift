// SPDX-License-Identifier: MIT
import Foundation

public enum ShelfSuggestionKind: String, CaseIterable, Sendable {
    case shortcutOffer, shortcutReminder, shortcutRelease, snippet
}

public enum ShelfSuggestion: Equatable, Sendable {
    case shortcutOffer(clip: UUID, slot: Int, pasteCount: Int, isPinned: Bool)
    case shortcutReminder(clip: UUID, slot: Int)
    case shortcutRelease(clip: UUID, slot: Int, idleWeeks: Int)
    case snippet(clip: UUID, pasteCount: Int)

    public var clipID: UUID {
        switch self {
        case let .shortcutOffer(clip, _, _, _): clip
        case let .shortcutReminder(clip, _): clip
        case let .shortcutRelease(clip, _, _): clip
        case let .snippet(clip, _): clip
        }
    }

    public var kind: ShelfSuggestionKind {
        switch self {
        case .shortcutOffer: .shortcutOffer
        case .shortcutReminder: .shortcutReminder
        case .shortcutRelease: .shortcutRelease
        case .snippet: .snippet
        }
    }

    public var hasDecline: Bool {
        switch self {
        case .shortcutReminder: false
        default: true
        }
    }
}
