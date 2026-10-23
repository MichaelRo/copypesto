// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// Handles `tell application "Pesto" to paste item id "UUID"` AppleScript commands.
@objc(PasteItemCommand)
final class PasteItemCommand: NSScriptCommand {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Scripting")

    override func performDefaultImplementation() -> Any? {
        guard let idString = evaluatedArguments?["itemID"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        MainActor.assumeIsolated {
            guard ScriptingContext.historyIsAccessible,
                  let container = ScriptingContext.modelContainer else { return }
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else { return }
            Self.logger.notice("[paste] trigger=applescript-paste id=\(id, privacy: .private)")
            // ScriptingContext.pasteItem writes the pasteboard content, captures focus, and triggers
            // the paste flow. This avoids duplicating the decrypt + write logic here.
            ScriptingContext.pasteItem?(item)
        }
        return nil
    }
}
