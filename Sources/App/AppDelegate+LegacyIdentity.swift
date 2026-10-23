// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

extension AppDelegate {
    func migrateLegacyIdentityIfNormalLaunch() {
        guard RuntimeConfiguration.current.mode == .normal,
              let legacyDefaults = UserDefaults(suiteName: AppIdentity.legacyBundleID) else { return }
        let report = LegacyIdentityMigration(
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            legacyDefaults: legacyDefaults,
            currentDefaults: AppDefaults.store,
            secrets: KeychainSecretStore()
        ).run()
        Self.logger.info("""
        Legacy identity migration: store \(String(describing: report.store), privacy: .public), \
        \(report.preferencesCopied) preferences, key \(String(describing: report.key), privacy: .public)
        """)
    }
}
