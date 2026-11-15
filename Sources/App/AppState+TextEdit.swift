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
        let result: TextEditSaveResult
        do {
            result = try await TextEditPolicy.result(for: service.updateText(id: id, text: text))
        } catch let refusal as ClipSizePolicy.TooLarge {
            return .refused(refusal.message)
        } catch {
            Self.textEditLogger.error("Editing a clip failed: \(error.localizedDescription, privacy: .public)")
            return .refused(TextEditPolicy.failedMessage)
        }
        if result == .saved { offerUndo(since: mark) }
        return result
    }
}
