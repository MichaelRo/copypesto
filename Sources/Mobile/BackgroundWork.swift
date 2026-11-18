// SPDX-License-Identifier: MIT
import Foundation
import UIKit

/// Asks iOS for time to finish a write the app starts as it leaves the front, so a widget snapshot is not suspended
/// half-written. Every begin is ended exactly once: when the work is done, or when iOS says the time is up.
@MainActor
struct BackgroundWork {
    var begin: @MainActor (_ name: String, _ expired: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
    var end: @MainActor (UIBackgroundTaskIdentifier) -> Void

    static let system = BackgroundWork(
        begin: { name, expired in
            UIApplication.shared.beginBackgroundTask(withName: name) { MainActor.assumeIsolated { expired() } }
        },
        end: { UIApplication.shared.endBackgroundTask($0) }
    )

    /// Begun at once, before any work is scheduled; `finish()` when the work is done.
    func hold(_ name: String) -> Hold {
        let hold = Hold(end: end)
        hold.identifier = begin(name) { [weak hold] in hold?.finish() }
        if hold.expiredEarly { hold.finish() }
        return hold
    }

    @MainActor
    final class Hold {
        fileprivate var identifier = UIBackgroundTaskIdentifier.invalid
        fileprivate var expiredEarly = false
        private var end: (@MainActor (UIBackgroundTaskIdentifier) -> Void)?

        fileprivate init(end: @escaping @MainActor (UIBackgroundTaskIdentifier) -> Void) {
            self.end = end
        }

        func finish() {
            guard identifier != .invalid else {
                expiredEarly = true
                return
            }
            guard let end else { return }
            self.end = nil
            end(identifier)
        }
    }
}
