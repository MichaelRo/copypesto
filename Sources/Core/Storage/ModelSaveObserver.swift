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
    /// `posted` runs on the saving thread before the hop, so a caller can tell a save that is on its way to the main
    /// actor from one already handled.
    public static func observeChanges(
        in container: ModelContainer,
        posted: @escaping @Sendable () -> Void = {},
        _ handler: @escaping @MainActor @Sendable (HistorySaveChange?) -> Void
    )
        -> any NSObjectProtocol
    {
        NotificationCenter.default
            .addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak container] note in
                guard let container,
                      let saved = note.object as? ModelContext,
                      saved.container === container else { return }
                let change = HistorySaveChange(userInfo: note.userInfo)
                posted()
                Task { @MainActor in handler(change) }
            }
    }
}
