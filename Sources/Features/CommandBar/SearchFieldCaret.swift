// SPDX-License-Identifier: MIT
import AppKit

/// A text field that takes focus selects its text, so the next key would replace what a person had just typed on the
/// shelf. The search field puts its caret at the end once it has focus, and a key that arrives in the moment between
/// the
/// focus and that placement does it first (the search is armed when it opens, and the first of the two to run disarms
/// it).
@MainActor
enum SearchFieldCaret {
    private static var isArmed = false

    static func arm() {
        isArmed = true
    }

    static func placeAtEnd() {
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isKeyWindow }
        guard let editor = window?.firstResponder as? NSTextView else { return }
        isArmed = true
        settle(editor)
    }

    static func settle(_ editor: NSTextView) {
        guard isArmed else { return }
        isArmed = false
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }
}
