// SPDX-License-Identifier: MIT
import PestoCore

/// What the Undo banner says was done ("Deleted 3 clips"), in the same words as the Mac's banner.
enum UndoOfferText {
    static func action(_ label: UndoLabel) -> String {
        switch label {
        case let .deleteClips(count): String(localized: "Deleted \(CountText.clips(count))")
        case let .deleteCollection(name): String(localized: "Deleted the collection \u{201C}\(name)\u{201D}")
        case .changeClip: String(localized: "Changed the clip")
        case let .createCollection(name): String(localized: "Added the collection \u{201C}\(name)\u{201D}")
        case let .editCollection(name): String(localized: "Changed the collection \u{201C}\(name)\u{201D}")
        case let .duplicateCollection(name): String(localized: "Duplicated the collection \u{201C}\(name)\u{201D}")
        case .reorderCollections: String(localized: "Reordered the collections")
        case let .importCollection(name): String(localized: "Imported the collection \u{201C}\(name)\u{201D}")
        case let .addClips(_, count): String(localized: "Added \(CountText.clips(count))")
        case .editSnippet: String(localized: "Changed a snippet")
        }
    }
}
