// SPDX-License-Identifier: MIT
import Foundation

public struct ShelfClipFacts: Equatable, Sendable {
    public let id: UUID
    public let pasteCount: Int
    public let lastUsedAt: Date
    public let isPinned: Bool
    public let shortcutSlot: Int?
    public let shortcutLastUsedAt: Date?
    public let kind: ClipboardType
    public let textLength: Int
    public let isSensitive: Bool
    public let isNSFW: Bool
    public let analysisPending: Bool
    public let expires: Bool
    public var shelfPastesThisRun: Int
    /// On how many different days of the last month the clip was pasted.
    public let pasteDaysInWindow: Int
    /// How many clips look like this one (itself included), on how many days they were copied, and the one that stands
    /// for the family: the same for every member (ADR 0017).
    public let familySize: Int
    public let familyDays: Int
    public let familyRepresentative: UUID?

    public init(
        id: UUID,
        pasteCount: Int,
        lastUsedAt: Date,
        isPinned: Bool,
        shortcutSlot: Int? = nil,
        shortcutLastUsedAt: Date? = nil,
        kind: ClipboardType = .text,
        textLength: Int = 0,
        isSensitive: Bool = false,
        isNSFW: Bool = false,
        analysisPending: Bool = false,
        expires: Bool = false,
        shelfPastesThisRun: Int = 0,
        pasteDaysInWindow: Int = 0,
        familySize: Int = 1,
        familyDays: Int = 1,
        familyRepresentative: UUID? = nil
    ) {
        self.id = id
        self.pasteCount = pasteCount
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
        self.shortcutSlot = shortcutSlot
        self.shortcutLastUsedAt = shortcutLastUsedAt
        self.kind = kind
        self.textLength = textLength
        self.isSensitive = isSensitive
        self.isNSFW = isNSFW
        self.analysisPending = analysisPending
        self.expires = expires
        self.shelfPastesThisRun = shelfPastesThisRun
        self.pasteDaysInWindow = pasteDaysInWindow
        self.familySize = familySize
        self.familyDays = familyDays
        self.familyRepresentative = familyRepresentative
    }
}

public struct ShelfSuggestionFacts: Equatable, Sendable {
    public let clips: [ShelfClipFacts]
    public let assignedSlots: Set<Int>
    public let unavailableSlots: Set<Int>

    public init(
        clips: [ShelfClipFacts],
        assignedSlots: Set<Int>,
        unavailableSlots: Set<Int>
    ) {
        self.clips = clips
        self.assignedSlots = assignedSlots
        self.unavailableSlots = unavailableSlots
    }
}
