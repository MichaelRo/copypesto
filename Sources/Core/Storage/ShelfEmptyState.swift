// SPDX-License-Identifier: MIT
public enum ShelfEmptyState: Equatable, Sendable {
    case storageUnavailable
    case noResults
    case emptyCollection
    case captureBlocked
    case paused
    case noClips

    public struct Context: Sendable {
        public var hasStorage: Bool
        public var visibleCount: Int
        public var isSearching: Bool
        public var inCollection: Bool
        public var isPaused: Bool
        public var captureBlocked: Bool

        public init(
            hasStorage: Bool,
            visibleCount: Int,
            isSearching: Bool,
            inCollection: Bool,
            isPaused: Bool,
            captureBlocked: Bool
        ) {
            self.hasStorage = hasStorage
            self.visibleCount = visibleCount
            self.isSearching = isSearching
            self.inCollection = inCollection
            self.isPaused = isPaused
            self.captureBlocked = captureBlocked
        }
    }

    /// What the person can press to get out of this state, when there is something to press.
    public enum Action: Equatable, Sendable {
        case openPrivacySettings
        case resumeCapturing
    }

    public var action: Action? {
        switch self {
        case .captureBlocked: .openPrivacySettings
        case .paused: .resumeCapturing
        case .storageUnavailable, .noResults, .emptyCollection, .noClips: nil
        }
    }

    public static func evaluate(_ context: Context) -> ShelfEmptyState? {
        guard context.visibleCount == 0 else { return nil }
        if !context.hasStorage { return .storageUnavailable }
        if context.isSearching { return .noResults }
        if context.inCollection { return .emptyCollection }
        if context.captureBlocked { return .captureBlocked }
        if context.isPaused { return .paused }
        return .noClips
    }
}
