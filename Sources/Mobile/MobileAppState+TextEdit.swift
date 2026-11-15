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
        do {
            switch try await service.updateText(id: item.id, text: text) {
            case .saved:
                offerUndo(since: mark)
                return true
            case .unchanged:
                return true
            case .empty:
                tell(String(localized: "A clip can\u{2019}t be empty."), isProblem: true)
            case .sameAsAnother:
                tell(String(localized: "Another clip already has this text."), isProblem: true)
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
}
