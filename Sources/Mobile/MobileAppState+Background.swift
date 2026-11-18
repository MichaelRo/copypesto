// SPDX-License-Identifier: MIT
import BackgroundTasks
import Foundation
import os
import PestoCore

/// A background refresh that keeps the history in step with the other devices when iOS gives the app a moment: asked
/// for when the app leaves the front with sync on, it opens the folder, runs one exchange through `SyncExchange` (the
/// path pull to refresh takes) and lets the folder go. Never without a history.
extension MobileAppState {
    private static let backgroundLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "BackgroundSync")

    func registerBackgroundRefresh() {
        guard LaunchMode.current == .normal else { return }
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppIdentity.syncRefreshTaskID, using: .main
        ) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let refresh = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.runBackgroundRefresh(refresh)
            }
        }
        if !registered { Self.backgroundLogger.error("The background sync refresh was not registered") }
    }

    func scheduleBackgroundRefresh(now: Date = .now) {
        guard BackgroundSyncPolicy.shouldSchedule(
            syncEnabled: AppDefaults.store.value(for: Setting.syncEnabled),
            historyAvailable: historyContainer != nil,
            mode: LaunchMode.current
        ) else { return }
        let request = BGAppRefreshTaskRequest(identifier: AppIdentity.syncRefreshTaskID)
        request.earliestBeginDate = BackgroundSyncPolicy.earliestBegin(after: now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.backgroundLogger.error("No background sync refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func runBackgroundRefresh(_ task: BGAppRefreshTask) {
        boot()
        guard historyContainer != nil, let sync = madeSync() else {
            task.setTaskCompleted(success: false)
            return
        }
        scheduleBackgroundRefresh()
        let completion = BackgroundTaskCompletion { task.setTaskCompleted(success: $0) }
        let work = Task { await SyncExchange.inBackground(sync) }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                SyncExchange.expire(sync)
                completion.finish(success: false)
            }
        }
        Task {
            let exchanged = await work.value
            completion.finish(success: exchanged)
        }
    }
}

/// Tells iOS a background task is done exactly once, whichever of the work and the expiration ends first.
@MainActor
final class BackgroundTaskCompletion {
    private var complete: ((Bool) -> Void)?

    init(_ complete: @escaping (Bool) -> Void) {
        self.complete = complete
    }

    func finish(success: Bool) {
        complete?(success)
        complete = nil
    }
}
