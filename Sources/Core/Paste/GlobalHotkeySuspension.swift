// SPDX-License-Identifier: MIT

/// Whether Pesto's global shortcuts are paused. A registered Carbon hotkey is taken by the system before any window
/// sees the key, so while a recorder waits for a combination the shortcuts must be unregistered or the combination
/// already in use would fire instead of being recorded. Recorders can overlap, so the pause is counted.
public struct GlobalHotkeySuspension: Sendable {
    private var depth = 0

    public init() {}

    public var isSuspended: Bool {
        depth > 0
    }

    /// True when this call is the one that must unregister the shortcuts.
    public mutating func begin() -> Bool {
        depth += 1
        return depth == 1
    }

    /// True when this call is the one that must register them again. An end with no begin is ignored.
    public mutating func end() -> Bool {
        guard depth > 0 else { return false }
        depth -= 1
        return depth == 0
    }
}
