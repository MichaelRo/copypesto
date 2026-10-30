// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension ModelContext {
    /// Saves, and when that fails drops the pending changes: SwiftData keeps them in the context, so the next unrelated
    /// save would otherwise commit a half-made change. The one save policy, on the actor and on the main context.
    func saveOrRollback() throws {
        SyncJournal.stamp(in: self)
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
