// SPDX-License-Identifier: MIT
import Foundation

/// Where a request from another device to join sync is shown: over the library, wherever the person is, unless a sheet
/// is already up (the Sync screen presents the request itself) or a set-up flow is on screen; it waits for them.
enum SyncApprovalPresentation {
    static let pollInterval: Duration = .seconds(5)

    static func presentsOverLibrary(hasPendingJoin: Bool, flowIsIdle: Bool, anotherSheetIsUp: Bool) -> Bool {
        hasPendingJoin && flowIsIdle && !anotherSheetIsUp
    }
}
