// SPDX-License-Identifier: MIT
import Foundation

public struct ShelfSuggestionContext: Equatable, Sendable {
    public var now: Date
    public var isEnabled: Bool
    public var hasOnboarded: Bool
    public var armedAt: Date?
    public var lastShownAt: Date?
    public var hotkeysLive: Bool
    public var hasAccessibility: Bool
    public var isHistoryLocked: Bool
    public var isContentCovered: Bool
    public var isStackActive: Bool
    public var isSearching: Bool
    public var otherBannerVisible: Bool

    public init(
        now: Date = .now,
        isEnabled: Bool = true,
        hasOnboarded: Bool = true,
        armedAt: Date? = nil,
        lastShownAt: Date? = nil,
        hotkeysLive: Bool = true,
        hasAccessibility: Bool = true,
        isHistoryLocked: Bool = false,
        isContentCovered: Bool = false,
        isStackActive: Bool = false,
        isSearching: Bool = false,
        otherBannerVisible: Bool = false
    ) {
        self.now = now
        self.isEnabled = isEnabled
        self.hasOnboarded = hasOnboarded
        self.armedAt = armedAt
        self.lastShownAt = lastShownAt
        self.hotkeysLive = hotkeysLive
        self.hasAccessibility = hasAccessibility
        self.isHistoryLocked = isHistoryLocked
        self.isContentCovered = isContentCovered
        self.isStackActive = isStackActive
        self.isSearching = isSearching
        self.otherBannerVisible = otherBannerVisible
    }
}
