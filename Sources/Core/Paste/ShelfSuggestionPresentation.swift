// SPDX-License-Identifier: MIT
import Foundation

public struct ShelfSuggestionPresentation: Equatable, Sendable {
    public let suggestion: ShelfSuggestion?
    public let targetClipID: UUID?
    public let targetSlot: Int?
    public let isNotice: Bool

    public init(
        suggestion: ShelfSuggestion?,
        targetClipID: UUID? = nil,
        targetSlot: Int? = nil,
        isNotice: Bool = false
    ) {
        self.suggestion = suggestion
        self.targetClipID = targetClipID ?? suggestion?.clipID
        if case let .shortcutOffer(_, slot, _, _) = suggestion {
            self.targetSlot = slot
        } else {
            self.targetSlot = targetSlot
        }
        self.isNotice = isNotice
    }

    public static var offNotice: Self {
        Self(suggestion: nil, isNotice: true)
    }
}
