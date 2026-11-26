// SPDX-License-Identifier: MIT
public enum ShelfEmptyState: Equatable, Sendable {
    case storageUnavailable
    /// A collection locked on this Mac and not opened since the shelf opened (ADR 0081).
    case lockedCollection
    case noResults
    case emptyCollection
    case emptyAppFilter(appName: String)
    case captureBlocked
    case paused
    case noClips

    public struct Context: Sendable {
        public var hasStorage: Bool
        public var visibleCount: Int
        public var isSearching: Bool
        public var inCollection: Bool
        public var selectedAppName: String?
        public var isPaused: Bool
        public var captureBlocked: Bool
        public var collectionIsLocked: Bool

        public init(
            hasStorage: Bool,
            visibleCount: Int,
            isSearching: Bool,
            inCollection: Bool,
            selectedAppName: String? = nil,
            isPaused: Bool,
            captureBlocked: Bool,
            collectionIsLocked: Bool = false
        ) {
            self.hasStorage = hasStorage
            self.visibleCount = visibleCount
            self.isSearching = isSearching
            self.inCollection = inCollection
            self.selectedAppName = selectedAppName
            self.isPaused = isPaused
            self.captureBlocked = captureBlocked
            self.collectionIsLocked = collectionIsLocked
        }
    }

    /// What the person can press to get out of this state, when there is something to press.
    public enum Action: Equatable, Sendable {
        case openPrivacySettings
        case resumeCapturing
        case unlockCollection
    }

    public var action: Action? {
        switch self {
        case .captureBlocked: .openPrivacySettings
        case .paused: .resumeCapturing
        case .lockedCollection: .unlockCollection
        case .storageUnavailable, .noResults, .emptyCollection, .emptyAppFilter, .noClips: nil
        }
    }

    public static func evaluate(_ context: Context) -> ShelfEmptyState? {
        guard context.visibleCount == 0 else { return nil }
        if !context.hasStorage { return .storageUnavailable }
        if context.inCollection, context.collectionIsLocked { return .lockedCollection }
        if context.isSearching { return .noResults }
        if context.inCollection { return .emptyCollection }
        if let app = context.selectedAppName, !app.isEmpty {
            return .emptyAppFilter(appName: app)
        }
        if context.captureBlocked { return .captureBlocked }
        if context.isPaused { return .paused }
        return .noClips
    }
}
