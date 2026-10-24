// SPDX-License-Identifier: MIT
import AppKit

/// A plain window does not close on Esc (only panels and sheets do). A text field editing, a sheet and the shortcut
/// recorder take Esc first, so this runs only when nothing else wanted it. When the sidebar search field is empty,
/// Tab moves focus into the pane instead of cycling inside the search field's internal button loop.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_: Any?) {
        performClose(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 48,
           let text = firstResponder as? NSText,
           let searchField = text.superview?.superview as? NSSearchField,
           searchField.stringValue.isEmpty
        {
            let backwards = event.modifierFlags.contains(.shift)
            if backwards {
                selectPreviousKeyView(searchField)
            } else {
                selectNextKeyView(searchField)
            }
            return
        }
        super.sendEvent(event)
    }
}
