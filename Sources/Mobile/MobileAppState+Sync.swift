// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import UIKit

/// Sync's place in the app's life: set up once the history is open, given the folder while the app is in front and
/// stopped when it leaves. A hosted test builds its own; a UI-test launch keeps every key in memory.
extension MobileAppState {
    func syncDidBecomeActive() {
        madeSync()?.activate()
    }

    func syncDidEnterBackground() {
        sync?.deactivate()
        scheduleBackgroundRefresh()
    }

    /// The app's sync, made once the history is open; nil in a hosted test or without a history.
    func madeSync() -> MobileSync? {
        if let sync { return sync }
        let mode = LaunchMode.current
        guard mode != .hostedTests, let container = historyContainer, let storage = storageService else { return nil }
        let created = MobileSync(Self.liveSyncEnvironment(container: container, storage: storage, mode: mode))
        sync = created
        return created
    }

    static var currentDeviceKind: SyncDeviceKind {
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    private static func liveSyncEnvironment(
        container: ModelContainer, storage: StorageService, mode: LaunchMode
    )
    -> MobileSync.Environment {
        let defaults = AppDefaults.store
        let kind = currentDeviceKind
        let memory = InMemorySecretStore()
        let isUITest = mode == .uiTest
        return MobileSync.Environment(
            folder: BookmarkedSyncFolder(defaults: defaults), deviceKind: kind, defaults: defaults,
            authenticator: UserAuthenticator.current, grace: .shared,
            makeController: { root in
                let deviceID = DeviceIdentity.current()
                guard deviceID != "unknown" else { return nil }
                // The Mac's history lock has no counterpart on iOS yet, so `isLocked` keeps its default.
                var environment = SyncController.Environment(
                    container: container, storage: storage, folder: root,
                    keyStore: isUITest ? ThisDeviceSyncKeyStore(secrets: memory) : SyncEntitlement.keyStore(),
                    deviceKeys: isUITest ? KeychainDeviceKeyStore(secrets: memory) : KeychainDeviceKeyStore(),
                    highWater: SealedHighWaterStore(
                        url: AppPaths.supportDirectory.appendingPathComponent("sync-highwater.sealed")
                    ),
                    defaults: defaults, deviceID: deviceID, deviceName: DeviceName.current()
                )
                environment.deviceKind = kind
                return SyncController(environment)
            }
        )
    }
}
