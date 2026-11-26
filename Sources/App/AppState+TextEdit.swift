// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// The one way the Mac saves a clip's new text (ADR 0048, ADR 0050): Core seals and judges it again and records one
/// Undo; this says what happened in words the Edit Text window shows, and offers Undo on the shelf.
extension AppState {
    private static let textEditLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "TextEdit")

    func saveEditedText(id: UUID, text: String) async -> TextEditSaveResult {
        guard let service = storageService else { return .refused(TextEditPolicy.failedMessage) }
        guard await unlockForWindowSave() else { return .refused(TextEditPolicy.lockedMessage) }
        let mark = service.undoHistory.recordedCount
        let before = shownContentHashes(of: [id])
        let result: TextEditSaveResult
        do {
            result = try await TextEditPolicy.result(for: service.updateText(id: id, text: text))
        } catch let refusal as ClipSizePolicy.TooLarge {
            return .refused(refusal.message)
        } catch {
            Self.textEditLogger.error("Editing a clip failed: \(error.localizedDescription, privacy: .public)")
            return .refused(TextEditPolicy.failedMessage)
        }
        if result == .saved {
            offerUndo(since: mark)
            Task { await redrawWhenTextArrives(changedFrom: before) }
        }
        return result
    }

    /// Saves the Clip window's snippet (ADR 0075): an existing snippet is edited, any other text clip becomes one in
    /// place, so one Undo takes back the text and the pin together.
    func saveClipAsSnippet(id: UUID, title: String, text: String) async -> TextEditSaveResult {
        guard let service = storageService else { return .refused(TextEditPolicy.failedMessage) }
        guard await unlockForWindowSave() else { return .refused(TextEditPolicy.lockedMessage) }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : trimmed
        let isSnippet = historyStore?.item(for: id)?.isTemplate == true
        let mark = service.undoHistory.recordedCount
        let before = shownContentHashes(of: [id])
        let result: TextEditSaveResult
        do {
            if isSnippet {
                result = try await service.updateSnippet(id: id, title: name, text: text)
                    ? .saved : .refused(TextEditPolicy.failedMessage)
            } else {
                result = try await TextEditPolicy.snippetResult(for: service.convertToSnippet(
                    id: id,
                    title: name,
                    text: text
                ))
            }
        } catch let refusal as ClipSizePolicy.TooLarge {
            return .refused(refusal.message)
        } catch {
            Self.textEditLogger.error("Making a snippet failed: \(error.localizedDescription, privacy: .public)")
            return .refused(TextEditPolicy.failedMessage)
        }
        if result == .saved {
            offerUndo(since: mark)
            Task { await redrawWhenTextArrives(changedFrom: before) }
        }
        return result
    }

    /// The window keeps the draft: a save asks for the unlock, and goes on once it is given.
    private func unlockForWindowSave() async -> Bool {
        checkAndApplyBiometricLock(closesTextEditor: false)
        if isHistoryLocked { await performBiometricUnlock() }
        return !isHistoryLocked
    }

    /// The content hash of the given clips as the shelf shows them, before a change whose new text must be drawn.
    func shownContentHashes(of ids: [UUID]) -> [UUID: String] {
        var hashes: [UUID: String] = [:]
        for id in ids {
            if let item = historyStore?.item(for: id), item.modelContext != nil, !item.isDeleted {
                hashes[id] = item.contentHash
            }
        }
        return hashes
    }

    /// The storage actor's save reaches the main context's copy of a clip a moment later, and neither that merge nor
    /// the history following the save redrew the card (seen on the shelf after ⌘Z). Once every changed clip's copy
    /// holds its new content, or is gone (two seconds at most), the history is read again, for the search text, and
    /// `textEditGeneration` makes the shelf give the card a new identity.
    func redrawWhenTextArrives(changedFrom hashes: [UUID: String]) async {
        guard let historyStore, !hashes.isEmpty else { return }
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline, !TextArrival.hasArrived(hashes, current: { id in
            historyStore.item(for: id).flatMap { $0.modelContext == nil || $0.isDeleted ? nil : $0.contentHash }
        }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        historyStore.refresh()
        textEditGeneration += 1
    }
}
