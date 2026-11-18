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
        guard !isHistoryLockedNow() else { return .refused(TextEditPolicy.lockedMessage) }
        let mark = service.undoHistory.recordedCount
        let before = historyStore?.item(for: id)?.contentHash
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
            if let before { Task { await redrawWhenTextArrives(changedFrom: [id: before]) } }
        }
        return result
    }

    /// The content hash of every clip the history holds, before a change whose new text must be drawn.
    func shownContentHashes() -> [UUID: String] {
        Dictionary(
            (historyStore?.items ?? []).map { ($0.id, $0.contentHash) }, uniquingKeysWith: { first, _ in first }
        )
    }

    /// The storage actor's save reaches the main context's copy of a clip a moment later, and neither that merge nor
    /// the history following the save redrew the card (seen on the shelf after ⌘Z). Once a copy holds new content (a
    /// second at most) the history is read again, for the search text, and `textEditGeneration` makes the shelf give
    /// the card a new identity.
    func redrawWhenTextArrives(changedFrom hashes: [UUID: String]) async {
        guard let historyStore, !hashes.isEmpty else { return }
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline, !hashes.contains(where: { id, hash in
            historyStore.item(for: id).map { $0.contentHash != hash } ?? false
        }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        historyStore.refresh()
        textEditGeneration += 1
    }
}
