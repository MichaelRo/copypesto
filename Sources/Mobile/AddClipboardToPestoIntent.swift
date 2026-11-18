// SPDX-License-Identifier: MIT
import AppIntents
import Foundation

/// Adds what is on the clipboard now. Pesto comes to the front to read it, because iOS lets only an app on screen read
/// what another app copied; iOS may ask to allow the paste.
struct AddClipboardToPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Clipboard to Pesto"
    static let description = IntentDescription(
        "Adds what you copied to your Pesto history. Pesto opens to read it.", categoryName: "Clipboard"
    )
    static let openAppWhenRun = true

    @Dependency private var state: MobileAppState

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await state.addClipboardFromShortcut()
        return .result(dialog: "Added to Pesto.")
    }
}
