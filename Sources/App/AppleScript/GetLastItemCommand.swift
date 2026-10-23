// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Handles `tell application "Pesto" to get last item` AppleScript commands.
@objc(GetLastItemCommand)
final class GetLastItemCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let locked: Bool = MainActor.assumeIsolated { ScriptingContext.appState?.isHistoryLockedNow() ?? true }
        return locked ? "" : LastItemStore.read()?.preview ?? ""
    }
}
