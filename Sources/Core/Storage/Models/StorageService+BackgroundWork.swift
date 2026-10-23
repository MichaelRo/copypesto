// SPDX-License-Identifier: MIT
import Foundation

public extension StorageService {
    /// Returns when every clip an earlier `ingest` saved before judging it has been judged, and every vector it
    /// started computing has been stored.
    func waitForBackgroundWork() async {
        while !pendingAnalyses.isEmpty || !pendingEmbeddings.isEmpty {
            for task in Array(pendingAnalyses.values) {
                await task.value
            }
            for task in Array(pendingEmbeddings.values) {
                await task.value
            }
        }
    }

    internal func finishEmbedding(_ id: UUID) {
        pendingEmbeddings[id] = nil
    }
}
