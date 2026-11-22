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

    internal func trackBackgroundTask(
        _ taskID: UUID,
        for itemID: UUID,
        in pool: inout [UUID: Task<Void, Never>],
        task: Task<Void, Never>
    ) {
        pool[taskID] = task
        pendingItemTasks[itemID, default: []].insert(taskID)
    }

    internal func untrackBackgroundTask(_ taskID: UUID, for itemID: UUID) {
        pendingItemTasks[itemID]?.remove(taskID)
        if pendingItemTasks[itemID]?.isEmpty == true {
            pendingItemTasks[itemID] = nil
        }
    }

    internal func cancelBackgroundTasks(for deletedIDs: [UUID]) {
        for itemID in deletedIDs {
            guard let taskIDs = pendingItemTasks.removeValue(forKey: itemID) else { continue }
            for taskID in taskIDs {
                pendingAnalyses[taskID]?.cancel()
                pendingEmbeddings[taskID]?.cancel()
            }
        }
    }

    internal func finishEmbedding(_ id: UUID, for itemID: UUID) {
        pendingEmbeddings[id] = nil
        untrackBackgroundTask(id, for: itemID)
    }
}
