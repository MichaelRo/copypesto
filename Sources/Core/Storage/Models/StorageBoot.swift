// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

/// Opens the stores at launch, trying the disk first and the in-memory copy last, and says why each attempt failed.
public enum StorageBoot {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "StorageBoot")

    public struct Openers {
        let clips: () throws -> ModelContainer
        let inMemory: () throws -> ModelContainer

        public init(clips: @escaping () throws -> ModelContainer, inMemory: @escaping () throws -> ModelContainer) {
            self.clips = clips
            self.inMemory = inMemory
        }
    }

    public struct Result {
        public let container: ModelContainer?
        public let isOnDisk: Bool
    }

    public static func run(openers: Openers, log customLog: ((String) -> Void)? = nil) -> Result {
        let log = customLog ?? { logger.error("\($0, privacy: .public)") }
        if let clips = attempt("clips store", openers.clips, log) {
            return Result(container: clips, isOnDisk: true)
        }
        log("Opening the history in memory: nothing will be saved this session")
        guard let memory = attempt("in-memory store", openers.inMemory, log) else {
            log("No store could be opened: running without persistent storage")
            return Result(container: nil, isOnDisk: false)
        }
        return Result(container: memory, isOnDisk: false)
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
