// SPDX-License-Identifier: MIT
import AppIntents
import Foundation

struct OpenShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pesto"
    static let description = IntentDescription("Shows the clipboard shelf.", categoryName: "Clipboard")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let open = ScriptingContext.openShelf else { throw ShelfIntentError.notReady }
        open(nil)
        return .result()
    }
}

struct SearchPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Pesto"
    static let description = IntentDescription(
        "Shows the clipboard shelf with your search already typed in.",
        categoryName: "Clipboard"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Search", description: "What to look for in your clipboard history.") var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let open = ScriptingContext.openShelf else { throw ShelfIntentError.notReady }
        open(query)
        return .result()
    }
}

enum ShelfIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady

    var localizedStringResource: LocalizedStringResource {
        "Pesto is not ready. Open Pesto and try again."
    }
}
