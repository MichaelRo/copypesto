// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

extension AppDelegate {
    /// Starts automatic backup when the person switched it on (Settings → Data). Normal launches only.
    func startAutoBackupIfNeeded() {
        guard LaunchMode.current.usesSystemIntegrations, let container = appState.historyContainer else { return }
        let service = AutoBackupService(container: container, isPersistentStore: appState.storeIsOnDisk)
        AutoBackupHolder.service = service
        service.refresh()
    }
}
