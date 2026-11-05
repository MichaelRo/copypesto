// SPDX-License-Identifier: MIT
import AppKit

/// A text field that takes focus selects its text, so the next key would replace what a person had just typed on the
/// shelf. The search field puts its caret at the end once it has focus.
@MainActor
enum SearchFieldCaret {
    static func placeAtEnd() {
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isKeyWindow }
        guard let editor = window?.firstResponder as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }
}
