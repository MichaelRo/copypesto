// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// A notification observer registered with a queue makes the poster wait for it. A save on the storage actor's context
/// would then wait for the main thread while the main thread waits for that context, which froze the app when several
/// items were copied quickly. This observes on the posting thread and hops to the main actor without waiting.
public enum ModelSaveObserver {
    public static func observe(_ handler: @escaping @MainActor @Sendable () -> Void) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            Task { @MainActor in handler() }
        }
    }

    /// The same, handing over which clips the save inserted, updated and deleted (nil when the save did not say). A
    /// save in a container other than `container` is not reported, so a store follows only its own history.
    public static func observeChanges(
        in container: ModelContainer,
        _ handler: @escaping @MainActor @Sendable (HistorySaveChange?) -> Void
    )
    -> any NSObjectProtocol {
        let own = ObjectIdentifier(container)
        return NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            if let saved = note.object as? ModelContext, ObjectIdentifier(saved.container) != own { return }
            let change = HistorySaveChange(userInfo: note.userInfo)
            Task { @MainActor in handler(change) }
        }
    }
}
