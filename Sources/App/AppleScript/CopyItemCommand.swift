// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Handles `tell application "Pesto" to copy item "..."` AppleScript commands.
/// Writes the text to the system pasteboard; the watcher ingests it just like any other copy, unless `concealed`
/// marks it host-only, in which case Pesto drops it like any concealed copy.
@objc(CopyItemCommand)
final class CopyItemCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let text = directParameter as? String else { return nil }
        let concealed = (evaluatedArguments?["concealed"] as? Bool) == true
        MainActor.assumeIsolated {
            PasteboardProtection.beginWrite(on: AppPasteboard.general, protected: concealed)
            AppPasteboard.general.setString(text, forType: .string)
        }
        return text
    }
}
