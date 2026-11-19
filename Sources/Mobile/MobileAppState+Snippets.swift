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
        if saved {
            tell(String(localized: "Saved as a snippet"))
            clipWasKept()
        }
    }

    func canEditSnippet(_ item: ClipboardItem) -> Bool {
        item.isTemplate && canEditText(item)
    }

    @discardableResult
    func createSnippet(title: String?, text: String) async -> Bool {
        guard let service = storageService else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            tell(String(localized: "A snippet can\u{2019}t be empty."), isProblem: true)
            return false
        }
        let cleanTitle = Self.cleanedTitle(title)
        let mark = service.undoHistory.recordedCount
        do {
            guard let id = try await service.addSnippet(text, title: cleanTitle) else {
                tell(String(localized: "Couldn\u{2019}t save the snippet."), isProblem: true)
                return false
            }
            await waitForCreatedSnippet(id: id)
            textEdits += 1
            offerUndo(since: mark)
            clipWasKept()
            return true
        } catch let refusal as ClipSizePolicy.TooLarge {
            tell(refusal.message, isProblem: true)
        } catch {
            Self.snippetLogger.error("Creating a snippet failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t save the snippet."), isProblem: true)
        }
        return false
    }

    @discardableResult
    func updateSnippet(id: UUID, title: String?, text: String) async -> Bool {
        guard let service = storageService else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            tell(String(localized: "A snippet can\u{2019}t be empty."), isProblem: true)
            return false
        }
        guard let existingItem = historyStore?.item(for: id),
              !secretReveal.concealment(for: existingItem).isConcealed else
        {
            return false
        }
        let oldHash = existingItem.contentHash
        let oldTitle = existingItem.customTitle
        let textChanged = ClipContent.of(existingItem)?.plainText != text
        let cleanTitle = Self.cleanedTitle(title)
        let mark = service.undoHistory.recordedCount
        do {
            guard try await service.updateSnippet(id: id, title: cleanTitle, text: text) else {
                tell(String(localized: "Couldn\u{2019}t save the snippet."), isProblem: true)
                return false
            }
            await waitForUpdatedSnippet(
                existingItem, oldHash: oldHash, oldTitle: oldTitle, cleanTitle: cleanTitle,
                textChanged: textChanged
            )
            textEdits += 1
            await Task.yield()
            offerUndo(since: mark)
            return true
        } catch let refusal as ClipSizePolicy.TooLarge {
            tell(refusal.message, isProblem: true)
        } catch {
            Self.snippetLogger.error("Updating a snippet failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t save the snippet."), isProblem: true)
        }
        return false
    }

    private static func cleanedTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func waitForCreatedSnippet(id: UUID) async {
        historyStore?.refresh()
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline, historyStore?.item(for: id)?.isPinned != true {
            try? await Task.sleep(for: .milliseconds(20))
            historyStore?.refresh()
        }
    }

    private func waitForUpdatedSnippet(
        _ item: ClipboardItem,
        oldHash: String,
        oldTitle: String?,
        cleanTitle: String?,
        textChanged: Bool
    ) async {
        let id = item.id
        let deadline = ContinuousClock.now + .seconds(5)
        if textChanged {
            while ContinuousClock.now < deadline, !TextArrival.hasArrived([id: oldHash], current: { itemID in
                let latest = historyStore?.item(for: itemID) ?? item
                return latest.modelContext == nil || latest.isDeleted ? nil : latest.contentHash
            }) {
                try? await Task.sleep(for: .milliseconds(20))
            }
        } else if oldTitle != cleanTitle {
            while ContinuousClock.now < deadline {
                let latest = historyStore?.item(for: id) ?? item
                if latest.modelContext == nil || latest.isDeleted || latest.customTitle == cleanTitle { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        historyStore?.refresh()
    }
}
