// SPDX-License-Identifier: MIT
import AppIntents
import Foundation

/// Finds clips by their text. A clip holding a secret is never among them (ADR 0003, ADR 0047).
struct SearchPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Pesto"
    static let description = IntentDescription(
        "Finds clips in your Pesto history whose text contains what you type. Clips with secrets are left out.",
        categoryName: "Clipboard"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Search") var query: String
    @Dependency private var state: MobileAppState

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ClipEntity]> {
        try .result(value: state.searchForShortcut(query).map(ClipEntity.init))
    }
}
