// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

extension AppDelegate {
    /// Builds the sync controller and, if the person had sync on, starts it again. Normal launches only, and only once
    /// sync is available (ADR 0018).
    func startSyncIfNeeded() {
        guard SyncAvailability.isAvailable, LaunchMode.current.usesSystemIntegrations,
              let container = appState.historyContainer, let storage = appState.storageService else { return }
        let deviceID = DeviceIdentity.current()
        guard deviceID != "unknown" else { return }
        let saved: String = AppDefaults.store.value(for: Setting.syncFolderPath)
        let folder = saved.isEmpty
            ? (AutoBackupSettings.iCloudDriveFolder() ?? AppPaths.supportDirectory)
            .appendingPathComponent("Pesto Sync", isDirectory: true)
            : URL(fileURLWithPath: saved, isDirectory: true)
        var environment = SyncController.Environment(
            container: container, storage: storage, folder: folder, keyStore: SyncEntitlement.keyStore(),
            deviceKeys: KeychainDeviceKeyStore(),
            highWater: SealedHighWaterStore(url: AppPaths.supportDirectory
                .appendingPathComponent("sync-highwater.sealed")),
            defaults: AppDefaults.store, deviceID: deviceID, deviceName: Host.current().localizedName ?? "This Mac"
        )
        let state = appState
        environment.isLocked = { state.isHistoryLocked }
        let controller = SyncController(environment)
        appState.syncController = controller
        controller.resumeIfEnabled()
    }
}
