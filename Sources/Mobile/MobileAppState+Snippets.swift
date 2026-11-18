// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// Snippets in the library (ADR 0017): a snippet that asks for values is copied from a small sheet, and a text clip
/// can be saved as a snippet.
extension MobileAppState {
    private static let snippetLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileSnippets")

    /// Copies a snippet the sheet filled in, remembers the values (unless the person turned that off) and moves the
    /// clip to the front.
    @discardableResult
    func copyFilled(_ request: SnippetFillRequest, fills: SnippetFills, pastedClipboard: String) -> Bool {
        pendingFill = nil
        guard let item = historyStore?.item(for: request.id) else { return false }
        let text = request.expanded(fills: fills, pastedClipboard: pastedClipboard, at: clock())
        if AppDefaults.store.value(for: Setting.rememberFillIns) {
            let memory = FillInMemory.remembered(from: fills, fields: request.plan.fields)
            let id = request.id
            Task {
                do {
                    try await storageService?.rememberFillIns(id: id, memory: memory)
                } catch {
                    Self.snippetLogger
                        .error("Remembering fill-ins failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return finishCopy(item, content: .text(text))
    }

    /// Whether the card's menu offers Save as Snippet: a plain text or code clip that is not already a snippet.
    func canSaveAsSnippet(_ item: ClipboardItem) -> Bool {
        (item.type == .text || item.type == .code) && !item.isPinned && item.sensitivityRaw == nil
            && !item.analysisPending && !secretReveal.concealment(for: item).isConcealed
    }

    /// Saves the clip's text as a snippet through Core's snippet path: pinned, filed in Snippets, and `{name}`
    /// placeholders turned into fill-ins.
    func saveAsSnippet(_ item: ClipboardItem) async {
        guard canSaveAsSnippet(item), let text = ClipContent.of(item)?.plainText, let service = storageService else {
            return
        }
        let converted = FillInParser.convertingAllVariables(in: text)
        var saved = false
        await reportAsync("Couldn\u{2019}t save the snippet.") {
            saved = try await service.addSnippet(converted, title: item.customTitle) != nil
        }
        if saved { tell(String(localized: "Saved as a snippet")) }
    }
}
