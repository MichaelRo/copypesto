// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Runs `onChange` once a short while after a burst of preference writes ends. Every write to the defaults posts a
/// notification, and a slider drag or a counter that ticks writes many: reacting to each one re-applied appearance,
/// retention and integrations, and made two actor hops, dozens of times a second for no new information.
@MainActor
final class DefaultsChangeObserver {
    /// Held for the life of the app (the delegate owns this object), so the notification is never removed.
    private var tokens: [any NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let delay: Duration
    private let onChange: @MainActor () async -> Void

    init(delay: Duration = .milliseconds(150), onChange: @escaping @MainActor () async -> Void) {
        self.delay = delay
        self.onChange = onChange
        tokens = [UserDefaults.didChangeNotification, ExclusionAllowances.didChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }
        }
    }

    func schedule() {
        pending?.cancel()
        pending = Task { [delay, onChange] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }
}
