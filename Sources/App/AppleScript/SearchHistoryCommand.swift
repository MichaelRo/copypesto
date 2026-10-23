// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// Handles `tell application "Pesto" to search history with query "..."` AppleScript commands.
/// Returns a list of matching item previews (newest first, max 20), an AppleScript list with one text per clip.
@objc(SearchHistoryCommand)
final class SearchHistoryCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let rawQuery: Any? = evaluatedArguments?["query"] ?? directParameter
        guard let query = rawQuery as? String, !query.isEmpty else { return [String]() }
        let result: [String] = MainActor.assumeIsolated {
            guard let container = ScriptingContext.modelContainer,
                  ScriptingContext.appState?.isHistoryLockedNow() == false else { return [] }
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 200
            guard let items = try? context.fetch(descriptor) else { return [] }
            let matches = items
                .filter { $0.displayPreviewText.localizedCaseInsensitiveContains(query) }
                .prefix(20)
                .map(\.displayPreviewText)
            return Array(matches)
        }
        return result
    }
}
