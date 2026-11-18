// SPDX-License-Identifier: MIT
import Foundation

/// What a save from the Mac's Edit Text window came to: closed (saved, or nothing to save) or refused with words
/// for the person, shown in the window, which stays open.
public enum TextEditSaveResult: Equatable, Sendable {
    case saved
    case unchanged
    case refused(String)

    public var closesEditor: Bool {
        if case .refused = self { return false }
        return true
    }
}

/// The Mac's rules around `StorageService.updateText` (ADR 0048, ADR 0050): which card offers Edit Text, when Save is
/// ready, and how each refusal is said.
public enum TextEditPolicy {
    /// The editor holds the whole text in a text view on the main thread; past this a clip is not offered.
    public static let maxEditableBytes = 512 * 1024

    /// A covered card offers nothing, and a masked secret is edited only while its Show is running.
    public static func isOffered(
        type: ClipboardType, analysisPending: Bool, hasBlob: Bool, byteSize: Int, concealment: CardConcealment
    )
    -> Bool {
        hasBlob
            && TextEditOutcome.isEditable(type: type, analysisPending: analysisPending)
            && byteSize <= maxEditableBytes
            && !concealment.isConcealed
    }

    public static func canSave(original: String, draft: String) -> Bool {
        draft != original && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func result(for outcome: TextEditOutcome) -> TextEditSaveResult {
        switch outcome {
        case .saved: .saved
        case .unchanged: .unchanged
        case .empty: .refused(String(localized: "A clip can\u{2019}t be empty."))
        case .missing, .notText: .refused(String(localized: "This clip can\u{2019}t be edited."))
        }
    }

    public static var lockedMessage: String {
        String(localized: "Your history is locked. Unlock it, then save again.")
    }

    public static var failedMessage: String {
        String(localized: "Couldn\u{2019}t save the change.")
    }
}
