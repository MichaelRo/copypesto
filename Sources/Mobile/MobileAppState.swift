// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftData

/// What the iPhone and iPad app holds for its views: the opened store and the services on it (ADR 0046).
@MainActor
@Observable
final class MobileAppState {
    private(set) var historyContainer: ModelContainer?
    private(set) var historyStore: HistoryStore?
    private(set) var storageService: StorageService?
    /// False when the disk store would not open and the history lives in memory until the app quits.
    private(set) var storeIsOnDisk = false
    private(set) var hasBooted = false
    /// The launch migrations, so a test can wait for them before it removes its store.
    @ObservationIgnored private(set) var launchWork: Task<Void, Never>?

    static var standardOpeners: StorageBoot.Openers {
        .init(
            clips: { try ModelContainerSetup.openClips() },
            inMemory: { try ModelContainerSetup.makeInMemory() }
        )
    }

    func boot(openers: StorageBoot.Openers = MobileAppState.standardOpeners) {
        guard !hasBooted else { return }
        hasBooted = true
        let boot = StorageBoot.run(openers: openers)
        historyContainer = boot.container
        historyStore = boot.container.map { HistoryStore(container: $0) }
        storeIsOnDisk = boot.isOnDisk
        guard let container = boot.container else { return }
        let service = StorageService(
            modelContainer: container, environment: .live(rules: ClipboardRules.fromUserDefaults())
        )
        storageService = service
        launchWork = Task(priority: .utility) { await LaunchMigrator.run(LaunchMigration.standard(service: service)) }
    }
}
