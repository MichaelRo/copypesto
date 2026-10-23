// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// Handles `tell application "Pesto" to list pinboards` AppleScript commands.
/// Returns the collection names in display order, as an AppleScript list.
@objc(ListCollectionsCommand)
final class ListCollectionsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let result: [String] = MainActor.assumeIsolated {
            guard ScriptingContext.historyIsAccessible,
                  let container = ScriptingContext.modelContainer else { return [] }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)])
            guard let boards = try? context.fetch(descriptor) else { return [] }
            return boards.map(\.name)
        }
        return result
    }
}
