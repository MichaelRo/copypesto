// SPDX-License-Identifier: MIT
import PestoCore

/// Actions that would otherwise be a way round the History Lock from an unattended Mac: while the lock is on, they
/// need Touch ID or the account password first.
enum ProtectedAction {
    static func permitted(reason: String, requireFresh: Bool = false) async -> Bool {
        await HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: AppDefaults.store.value(for: Setting.biometricLockEnabled),
            using: UserAuthenticator.current,
            reason: reason,
            requireFresh: requireFresh
        )
    }
}
