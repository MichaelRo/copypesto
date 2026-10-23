// SPDX-License-Identifier: MIT
import Foundation
import os

/// What happens to a capture the watcher hands over: appended to the latest clip after a double ⌘C, otherwise stored as
/// a new one; a copy over the size limit is refused with its message. The app supplies the two outlets (a sound, a
/// banner), so the decision can be tested without either.
public struct CapturePipeline: Sendable {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Capture")

    private let storage: StorageService
    private let appendMode: AppendModeCoordinator
    private let didStore: @Sendable () async -> Void
    private let didRefuse: @Sendable (String) async -> Void

    public init(
        storage: StorageService,
        appendMode: AppendModeCoordinator,
        didStore: @escaping @Sendable () async -> Void,
        didRefuse: @escaping @Sendable (String) async -> Void
    ) {
        self.storage = storage
        self.appendMode = appendMode
        self.didStore = didStore
        self.didRefuse = didRefuse
    }

    public func handle(_ capture: PasteboardCapture) async {
        do {
            if await appendMode.shouldAppend() {
                await appendMode.reset()
                try await storage.appendToLatest(capture)
            } else {
                try await storage.ingest(capture)
            }
            await didStore()
        } catch let tooLarge as ClipSizePolicy.TooLarge {
            await didRefuse(tooLarge.message)
        } catch {
            Self.logger.error("Ingest failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
