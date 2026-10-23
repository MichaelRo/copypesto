// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData

/// Main-actor bridge between the app's runtime state and NSScriptCommand subclasses.
///
/// NSScriptCommand.performDefaultImplementation() runs on the main thread, but in SwiftUI
/// apps that use @NSApplicationDelegateAdaptor, `NSApp.delegate as? AppDelegate` returns nil
/// because SwiftUI wraps the delegate. This enum provides a static accessor that is populated
/// during AppDelegate.applicationDidFinishLaunching() and is stable for the app's lifetime.
@MainActor
enum ScriptingContext {
    /// Populated by AppDelegate once the synced ModelContainer is ready.
    static var modelContainer: ModelContainer?

    /// Populated by AppDelegate on launch; used by ClearHistoryCommand.
    static var clearHistory: ((ClearRange) async -> Void)?

    /// Populated by AppDelegate on launch; used by PasteItemCommand.
    static var appState: AppState?

    /// Writes the item to the pasteboard and triggers a paste. Populated by AppDelegate on launch.
    /// Centralises the decrypt + write + trigger logic so PasteItemCommand doesn't duplicate it.
    static var pasteItem: ((ClipboardItem) -> Void)?

    // Imports curated items from a Paste-export JSON file; returns the number imported.

    /// Shows the shelf, pre-filled with a search when given. Populated by AppDelegate on launch; used by the
    /// Open Pesto and Search Pesto intents.
    static var openShelf: (@MainActor (String?) -> Void)?

    /// Covers or shows the clip contents (Hide Contents Now). Populated by AppDelegate on launch; used by the Hide Clip
    /// Contents intent and its Focus filter.
    static var setContentHidden: (@MainActor (Bool) -> Void)?

    /// Whether automation may read or paste history right now. False while History Lock is on, and false when the app
    /// has not finished starting, so a caller cannot get in by racing the launch.
    static var historyIsAccessible: Bool {
        appState?.isHistoryLockedNow() == false
    }
}
