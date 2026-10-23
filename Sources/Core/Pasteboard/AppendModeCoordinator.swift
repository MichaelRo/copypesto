// SPDX-License-Identifier: MIT
import Foundation

/// Tracks whether the next pasteboard capture should be appended to the most recent
/// text item rather than ingested as a new entry.
///
/// AppDelegate detects ⌘C keydown events globally. Two presses within `window` seconds
/// triggers append mode, which PasteboardWatcher's capture handler checks before calling
/// StorageService.ingest() vs. StorageService.appendToLatest().
public actor AppendModeCoordinator {
    private let window: TimeInterval
    private let appendLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private var lastCopyAt: Date?
    private var appendUntil: Date?

    public init(
        window: TimeInterval = 0.5,
        appendLifetime: TimeInterval = 1.0,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.window = window
        self.appendLifetime = appendLifetime
        self.now = now
    }

    /// Called each time a ⌘C keydown event fires. Returns `true` if this press is a
    /// double-copy (fires within `window` of the previous press) and activates append mode.
    @discardableResult
    public func markCopy() -> Bool {
        let pressedAt = now()
        defer { lastCopyAt = pressedAt }
        guard let last = lastCopyAt, pressedAt.timeIntervalSince(last) < window else { return false }
        setAppendMode()
        return true
    }

    /// Activates append mode for the next watcher tick (up to `appendLifetime` from now).
    public func setAppendMode() {
        appendUntil = now().addingTimeInterval(appendLifetime)
    }

    /// Returns `true` if the most recently detected copy was a double-copy and the
    /// append window has not yet expired.
    public func shouldAppend() -> Bool {
        guard let until = appendUntil else { return false }
        if now() > until {
            appendUntil = nil
            return false
        }
        return true
    }

    public func reset() {
        appendUntil = nil
    }
}
