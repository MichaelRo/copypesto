// SPDX-License-Identifier: MIT
import PestoCore

/// The words for what ⌘Z and ⇧⌘Z do, in the banner, the Edit menu and VoiceOver.
enum UndoText {
    /// What was done: "Deleted 3 clips".
    static func action(_ label: UndoLabel) -> String {
        switch label {
        case let .deleteClips(count): String(localized: "Deleted \(CountText.clips(count))")
        case let .deleteCollection(name): String(localized: "Deleted the collection \u{201C}\(name)\u{201D}")
        case let .changeClip(field): change(field)
        case let .createCollection(name): String(localized: "Added the collection \u{201C}\(name)\u{201D}")
        case let .editCollection(name): String(localized: "Changed the collection \u{201C}\(name)\u{201D}")
        case let .duplicateCollection(name): String(localized: "Duplicated the collection \u{201C}\(name)\u{201D}")
        case .reorderCollections: String(localized: "Reordered the collections")
        case let .importCollection(name): String(localized: "Imported the collection \u{201C}\(name)\u{201D}")
        case let .addClips(kind, count): added(kind, count)
        case .editSnippet: String(localized: "Changed a snippet")
        }
    }

    /// The Edit menu's item: "Undo Delete 3 Clips".
    static func menuTitle(undo label: UndoLabel?) -> String {
        guard let label else { return String(localized: "Undo") }
        return String(localized: "Undo \(command(label))")
    }

    static func menuTitle(redo label: UndoLabel?) -> String {
        guard let label else { return String(localized: "Redo") }
        return String(localized: "Redo \(command(label))")
    }

    /// What the person is told after ⌘Z or ⇧⌘Z worked.
    static func done(_ outcome: UndoOutcome) -> String {
        switch outcome.direction {
        case .undone: String(localized: "Undone: \(command(outcome.label))")
        case .redone: String(localized: "Redone: \(command(outcome.label))")
        }
    }

    private static func command(_ label: UndoLabel) -> String {
        switch label {
        case let .deleteClips(count): String(localized: "Delete \(CountText.clips(count))")
        case let .deleteCollection(name): String(localized: "Delete \u{201C}\(name)\u{201D}")
        case let .changeClip(field): change(field)
        case .createCollection: String(localized: "Add Collection")
        case .editCollection: String(localized: "Collection Change")
        case .duplicateCollection: String(localized: "Duplicate Collection")
        case .reorderCollections: String(localized: "Reorder Collections")
        case .importCollection: String(localized: "Import Collection")
        case let .addClips(kind, _):
            if kind == .snippet {
                String(localized: "Add Snippet")
            } else {
                String(localized: "Import")
            }
        case .editSnippet: String(localized: "Edit Snippet")
        }
    }

    private static func added(_ kind: AddedClipsKind, _ count: Int) -> String {
        switch (kind, count) {
        case (.snippet, 1): String(localized: "Added a snippet")
        case (.snippet, _): String(localized: "Added \(CountText.clips(count)) as snippets")
        case (.imported, _), (.collection, _): String(localized: "Imported \(CountText.clips(count))")
        }
    }

    private static func change(_ field: ClipField) -> String {
        switch field {
        case .title: String(localized: "Rename")
        case .note: String(localized: "Edit Note")
        case .tags: String(localized: "Edit Tags")
        case .icon: String(localized: "Change Icon")
        case .collection: String(localized: "Move to Collection")
        case .pinned: String(localized: "Pin or Unpin")
        case .shortcut: String(localized: "Change Shortcut")
        case .sensitive: String(localized: "Change Sensitive Mark")
        case .expiry: String(localized: "Change Expiry")
        case .order: String(localized: "Reorder")
        }
    }
}
