// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Handles `tell application "Pesto" to clear history range "hour"|"today"|"all"`.
/// The range is required, and Pesto asks the user to confirm before deleting anything.
@objc(ClearHistoryCommand)
final class ClearHistoryCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let range = ClearRange(automationName: evaluatedArguments?["range"] as? String) else {
            scriptErrorNumber = errAECoercionFail
            scriptErrorString = "clear history needs a range of \"hour\", \"today\" or \"all\"."
            return nil
        }
        MainActor.assumeIsolated {
            _ = Task { await ScriptingContext.clearHistory?(range) }
        }
        return nil
    }
}
