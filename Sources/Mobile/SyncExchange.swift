// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What an exchange needs from sync, so pull to refresh and the background task are tested on one path.
@MainActor
protocol SyncExchanging: AnyObject {
    var isEnabled: Bool { get }
    func activate(for holder: MobileSync.Holder)
    func syncNow() async
    func deactivate(for holder: MobileSync.Holder)
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

    /// Returns false when nothing was exchanged (sync off, the folder not reachable, or the time ran out). The
    /// folder is held as the background's, so the app coming to the front meanwhile keeps it open afterwards.
    @discardableResult
    static func inBackground(_ sync: any SyncExchanging) async -> Bool {
        sync.activate(for: .background)
        defer { sync.deactivate(for: .background) }
        guard sync.isEnabled else { return false }
        await sync.syncNow()
        return !Task.isCancelled
    }

    /// iOS ends the background time: the pass in flight stops and the folder is let go unless the app is in front.
    static func expire(_ sync: any SyncExchanging) {
        sync.deactivate(for: .background)
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
