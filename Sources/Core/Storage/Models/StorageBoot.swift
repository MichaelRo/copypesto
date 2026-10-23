// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

/// Opens the stores at launch, trying the disk first and the in-memory copy last, and says why each attempt failed.
public enum StorageBoot {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "StorageBoot")

    public struct Openers {
        let synced: () throws -> ModelContainer
        let syncedLocalOnly: () throws -> ModelContainer
        let local: () throws -> ModelContainer
        let inMemory: () throws -> ModelContainer

        public init(
            synced: @escaping () throws -> ModelContainer,
            syncedLocalOnly: @escaping () throws -> ModelContainer,
            local: @escaping () throws -> ModelContainer,
            inMemory: @escaping () throws -> ModelContainer
        ) {
            self.synced = synced
            self.syncedLocalOnly = syncedLocalOnly
            self.local = local
            self.inMemory = inMemory
        }
    }

    public struct Result {
        public let synced: ModelContainer?
        public let local: ModelContainer?
        public let isOnDisk: Bool
    }

    /// `local.store` is best effort: nothing reads it yet, so it must never cost the person their history. With sync
    /// off
    /// the second disk attempt would be identical to the first, so it is skipped.
    public static func run(
        openers: Openers,
        cloudKitEnabled: Bool,
        log customLog: ((String) -> Void)? = nil
    )
        -> Result
    {
        let log = customLog ?? { logger.error("\($0, privacy: .public)") }
        var synced = attempt("clips store", openers.synced, log)
        if synced == nil, cloudKitEnabled {
            synced = attempt("clips store without sync", openers.syncedLocalOnly, log)
        }
        let local = attempt("local store", openers.local, log)
        if let synced { return Result(synced: synced, local: local, isOnDisk: true) }

        log("Opening the history in memory: nothing will be saved this session")
        guard let memory = attempt("in-memory store", openers.inMemory, log) else {
            log("No store could be opened: running without persistent storage")
            return Result(synced: nil, local: nil, isOnDisk: false)
        }
        return Result(synced: memory, local: nil, isOnDisk: false)
    }

    private static func attempt(
        _ name: String, _ open: () throws -> ModelContainer, _ log: (String) -> Void
    )
    -> ModelContainer? {
        do {
            return try open()
        } catch {
            log("The \(name) failed to open: \(error.localizedDescription)")
            return nil
        }
    }
}
