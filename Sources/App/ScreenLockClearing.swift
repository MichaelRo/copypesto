// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Clears history when the screen locks, if the user asked for it. The setting is read at the moment of the lock.
/// Observes on the posting thread and hops to the main actor asynchronously (a queue-bound observer makes the poster
/// wait for the main thread).
@MainActor
final class ScreenLockClearing {
    private let center: NotificationCenter
    private var observer: (any NSObjectProtocol)?

    init(
        center: NotificationCenter = DistributedNotificationCenter.default(),
        name: Notification.Name = Notification.Name("com.apple.screenIsLocked"),
        isEnabled: @escaping @Sendable () -> Bool = { AppDefaults.store.value(for: Setting.clearOnScreenLock) },
        clear: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.center = center
        observer = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            guard isEnabled() else { return }
            Task { @MainActor in await clear() }
        }
    }

    func stop() {
        if let observer { center.removeObserver(observer) }
        observer = nil
    }
}
