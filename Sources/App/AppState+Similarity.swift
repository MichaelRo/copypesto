// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

@MainActor
extension AppState {
    /// Loads the signatures of clips that look alike into memory, then signs clips that have none, a few at a time,
    /// while the Mac is idle. It stops while the history is locked or Low Power Mode is on (ADR 0017).
    func startSimilarityWork() {
        guard LaunchMode.current.usesSystemIntegrations, let service = storageService else { return }
        similarityTask?.cancel()
        similarityTask = Task(priority: .background) { [weak self] in
            do {
                try await service.loadSimilarityIndex()
                while !Task.isCancelled {
                    if self?.isSimilarityWorkPaused() ?? true {
                        try await Task.sleep(for: .seconds(30))
                        continue
                    }
                    guard try await service.signMissingClips(limit: 10) > 0 else { return }
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {
                return
            } catch {
                Self.similarityLogger.error("similarity work stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The history locked or was wiped: nothing derived from clips stays in memory.
    func stopSimilarityWork() {
        similarityTask?.cancel()
        similarityTask = nil
        guard let service = storageService else { return }
        Task { await service.dropSimilarityIndex() }
    }

    private func isSimilarityWorkPaused() -> Bool {
        isHistoryLocked || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
