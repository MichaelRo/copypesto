// SPDX-License-Identifier: MIT
import Foundation

/// Owns "the paste in flight". Every paste goes through `start`, so the wake, sleep and lock handlers always have
/// something to cancel and a paste can never outlive the moment it was meant for.
@MainActor
public final class PasteTaskTracker {
    /// Bumped by every sleep, wake or screen lock. A paste requested under an older epoch is refused.
    public private(set) var interruptionEpoch = 0

    private var current: (id: UUID, task: Task<Void, Never>)?

    public init() {}

    public var isRunning: Bool {
        current != nil
    }

    /// Starts `operation`, cancelling any paste still in flight. Returns false, running nothing, when an
    /// interruption happened after `requestedAtEpoch` was captured (for example the Mac slept between selecting a
    /// card and the overlay finishing its hide animation).
    @discardableResult
    public func start(
        requestedAtEpoch: Int? = nil,
        _ operation: @escaping @MainActor () async -> Void
    )
    -> Bool {
        if let requestedAtEpoch, requestedAtEpoch != interruptionEpoch { return false }
        current?.task.cancel()
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.finish(id)
        }
        current = (id, task)
        return true
    }

    /// Sleep, wake or screen lock: cancel whatever is in flight and invalidate pastes requested earlier.
    public func interrupt() {
        interruptionEpoch += 1
        current?.task.cancel()
        current = nil
    }

    /// A task only ever clears its own entry: an older, cancelled task finishing must not forget the newer one.
    private func finish(_ id: UUID) {
        if current?.id == id { current = nil }
    }
}
