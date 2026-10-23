// SPDX-License-Identifier: MIT
import AppIntents
import Foundation

/// Covers the shelf's clip contents (or shows them again): for a Shortcut with its own keyboard shortcut, a menu-bar
/// button or Spotlight, so Hide Contents Now has a hotkey without another shortcut recorder in Settings.
struct SetClipContentsHiddenIntent: AppIntent {
    static let title: LocalizedStringResource = "Hide Clip Contents"
    static let description = IntentDescription(
        "Blurs the contents of the clips in Pesto's shelf, for a screen share or a recording, or shows them again.",
        categoryName: "Privacy"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Hide", description: "Hide the contents, or show them again.", default: true) var hide: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let setHidden = ScriptingContext.setContentHidden else { throw ShelfIntentError.notReady }
        setHidden(hide)
        return .result()
    }
}

/// A Focus filter: while the Focus is on, clip contents are covered. When the Focus ends the system runs the filter
/// again with its default, which is off, so the cards come back.
struct HideClipContentsFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Hide Clip Contents"
    static let description: IntentDescription? = IntentDescription(
        "Covers the contents of Pesto's clips while this Focus is on."
    )

    @Parameter(title: "Hide clip contents", default: false) var hideContents: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: hideContents ? "Clip contents hidden" : "Clip contents shown")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let setHidden = ScriptingContext.setContentHidden else { throw ShelfIntentError.notReady }
        setHidden(hideContents)
        return .result()
    }
}
