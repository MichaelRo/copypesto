// SPDX-License-Identifier: MIT
import AppIntents
import Foundation

/// Adds text or a picture to the history, through ingest, in Pesto's own process.
struct AddToPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Pesto"
    static let description = IntentDescription(
        "Adds text or a picture to your Pesto history.", categoryName: "Clipboard"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String?
    @Parameter(title: "Picture", supportedContentTypes: [.image]) var picture: IntentFile?
    @Dependency private var state: MobileAppState

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await state.addFromShortcut(text: text, file: picture?.data, fileType: picture?.type)
        return .result(dialog: "Added to Pesto.")
    }
}
