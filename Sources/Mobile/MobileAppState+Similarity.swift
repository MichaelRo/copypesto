// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

private let similarityLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileSimilarity")

/// Loads the in-memory `SimilarityIndex` and signs any unsigned clips while the iOS library is open and unlocked.
extension MobileAppState {
    func startSimilarityWork() {
        guard LaunchMode.current != .hostedTests,
              let service = storageService,
              !isSimilarityWorkPaused() else { return }
        similarityTask?.cancel()
        similarityTask = Task(priority: .background) { [weak self] in
            do {
                try await service.loadSimilarityIndex()
                var cursor: Date?
                var excluding: Set<UUID> = []
                while !Task.isCancelled {
                    if self?.isSimilarityWorkPaused() ?? true {
                        try await Task.sleep(for: .seconds(30))
                        continue
                    }
                    let pass = try await service.signMissingClips(limit: 10, before: cursor, excluding: excluding)
                    if pass.isFinished { return }
                    cursor = pass.nextCursor
                    excluding = pass.skippingIDs
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {
                return
            } catch {
                similarityLogger.error("similarity work stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stopSimilarityWork() {
        similarityTask?.cancel()
        similarityTask = nil
        guard let service = storageService else { return }
        Task { await service.dropSimilarityIndex() }
    }

    private func isSimilarityWorkPaused() -> Bool {
        isHistoryLockedNow() || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
