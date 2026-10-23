// SPDX-License-Identifier: MIT
import AppIntents
import AppKit
import PestoCore

/// Adds arbitrary text to Pesto's clipboard history.
///
/// Writing to `AppPasteboard.general` is the canonical way to add a clipboard entry —
/// the `PasteboardWatcher` detects the change on its next tick (within 1 second) and
/// ingests the item just as it would for any other app copy.
struct CopyToPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Text to Pesto"
    static let description = IntentDescription(
        "Adds the given text to Pesto's clipboard history.",
        categoryName: "Clipboard"
    )

    @Parameter(title: "Text", description: "The text to add to clipboard history.") var text: String

    @Parameter(
        title: "Concealed",
        description: "Keep the copy on this Mac, off Universal Clipboard. Pesto does not record a concealed copy.",
        default: false
    ) var concealed: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (captured, isConcealed) = (text, concealed)
        await MainActor.run {
            PasteboardProtection.beginWrite(on: AppPasteboard.general, protected: isConcealed)
            AppPasteboard.general.setString(captured, forType: .string)
        }
        return .result(value: text)
    }
}
