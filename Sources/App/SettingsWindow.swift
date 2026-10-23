// SPDX-License-Identifier: MIT
import AppKit

/// A plain window does not close on Esc (only panels and sheets do). A text field editing, a sheet and the shortcut
/// recorder take Esc first, so this runs only when nothing else wanted it.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_: Any?) {
        performClose(nil)
    }
}
