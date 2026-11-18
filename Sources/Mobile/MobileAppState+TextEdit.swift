// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// Editing a clip's text from the detail (ADR 0048): Core seals and judges it again, and Undo is offered as after a
/// delete. A hidden clip is edited only while it is shown.
extension MobileAppState {
    private static let editLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileTextEdit")

    func canEditText(_ item: ClipboardItem) -> Bool {
        item.blob != nil
            && TextEditOutcome.isEditable(type: item.type, analysisPending: item.analysisPending)
            && !secretReveal.concealment(for: item).isConcealed
    }

    @discardableResult
    func editText(of item: ClipboardItem, to text: String) async -> Bool {
        guard let service = storageService, canEditText(item) else { return false }
        let mark = service.undoHistory.recordedCount
        let before = item.contentHash
        do {
            switch try await service.updateText(id: item.id, text: text) {
            case .saved:
                await drawAgain(item, after: before)
                offerUndo(since: mark)
                return true
            case .unchanged:
                return true
            case .empty:
                tell(String(localized: "A clip can\u{2019}t be empty."), isProblem: true)
            case .missing, .notText:
                tell(String(localized: "This clip can\u{2019}t be edited."), isProblem: true)
            }
        } catch let refusal as ClipSizePolicy.TooLarge {
            tell(refusal.message, isProblem: true)
        } catch {
            Self.editLogger.error("Editing a clip failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t save the change."), isProblem: true)
        }
        return false
    }

    /// The actor's save reaches this context's copy of the clip a moment later, and neither that merge nor a new read
    /// of
    /// the history redrew the card (seen in the simulator). So once the copy holds the new content (a second at most)
    /// the history is read again, for the search text, and `textEdits` makes the grid give the card a new identity.
    private func drawAgain(_ item: ClipboardItem, after oldHash: String) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while item.contentHash == oldHash, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        historyStore?.refresh()
        textEdits += 1
    }
}
