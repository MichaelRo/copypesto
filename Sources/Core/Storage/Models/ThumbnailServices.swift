// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// The one `ThumbnailService` of a store, made off the main thread. A `@ModelActor` built on the main actor runs its
/// methods there (SwiftData uses the thread that made it), so a card that wrote `ThumbnailService(modelContainer:)` in
/// its
/// loading task decrypted, decoded and PNG-encoded every picture on the main thread, in the middle of a scroll; a
/// profile
/// of a collection switch over an imported history put 30% of the card bodies' time there. One service per store also
/// replaces the context each card used to make for itself.
public actor ThumbnailServices {
    public static let shared = ThumbnailServices()

    private var services: [ObjectIdentifier: ThumbnailService] = [:]

    public func service(for container: ModelContainer) -> ThumbnailService {
        let key = ObjectIdentifier(container)
        if let existing = services[key] { return existing }
        let made = ThumbnailService(modelContainer: container)
        services[key] = made
        return made
    }
}
