// SPDX-License-Identifier: MIT
import PestoCore

/// Keeps the running service reachable from Settings; the app delegate is at its size limit.
@MainActor
enum AutoBackupHolder {
    static var service: AutoBackupService?
}
