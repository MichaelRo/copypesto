// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What an exchange needs from sync, so pull to refresh and the background task are tested on one path.
@MainActor
protocol SyncExchanging: AnyObject {
    var isEnabled: Bool { get }
    func activate()
    func syncNow() async
    func deactivate()
}

extension MobileSync: SyncExchanging {}

/// The one exchange the app runs without a button: on pull to refresh (sync is already open while the app is in
/// front) and in a background refresh (open the folder, exchange once, let it go).
@MainActor
enum SyncExchange {
    static func onPull(_ sync: (any SyncExchanging)?) async {
        guard let sync, sync.isEnabled else { return }
        await sync.syncNow()
    }

    /// Returns false when nothing was exchanged (sync off, the folder not reachable).
    @discardableResult
    static func inBackground(_ sync: any SyncExchanging) async -> Bool {
        sync.activate()
        defer { sync.deactivate() }
        guard sync.isEnabled else { return false }
        await sync.syncNow()
        return true
    }
}

/// When to ask iOS for a background refresh: only with sync on, a history that opened and a normal launch.
enum BackgroundSyncPolicy {
    static let interval: TimeInterval = 30 * 60

    static func shouldSchedule(syncEnabled: Bool, historyAvailable: Bool, mode: LaunchMode) -> Bool {
        syncEnabled && historyAvailable && mode == .normal
    }

    static func earliestBegin(after now: Date) -> Date {
        now.addingTimeInterval(interval)
    }
}
