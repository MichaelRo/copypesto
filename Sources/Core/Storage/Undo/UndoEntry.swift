// SPDX-License-Identifier: MIT
import Foundation

/// What the person sees named for an undoable action: "Undo Delete 3 Clips".
public enum UndoLabel: Equatable, Sendable {
    case deleteClips(Int)
    case deleteCollection(String)
    case changeClip(ClipField)
    case createCollection(String)
    case editCollection(String)
    case duplicateCollection(String)
    case reorderCollections
    case importCollection(String)
    case addClips(AddedClipsKind, Int)
    case editSnippet
    case makeSnippet
    case editText
}

/// One thing that can be undone and done again.
public struct UndoEntry: Sendable {
    public enum Kind: Sendable {
        case clipsDeleted([ClipSnapshot])
        case collectionDeleted(PinboardSnapshot)
        case clipsEdited([ClipEdit])
        case collectionsChanged(CollectionChangeKind, [CollectionChange])
        case clipsAdded(AddedClips)
        case snippetsReplaced([ClipReplacement])
        /// A clip made a snippet in place: its text and its pin go back together (ADR 0075).
        case snippetsMade([ClipReplacement])
        case textReplaced([ClipReplacement])
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var label: UndoLabel {
        switch kind {
        case let .clipsDeleted(snapshots): .deleteClips(snapshots.count)
        case let .collectionDeleted(snapshot): .deleteCollection(snapshot.name)
        case let .clipsEdited(edits): .changeClip(edits.first?.primaryField ?? .title)
        case let .collectionsChanged(kind, changes): Self.label(of: kind, changes)
        case let .clipsAdded(added): Self.label(of: added)
        case .snippetsReplaced: .editSnippet
        case .snippetsMade: .makeSnippet
        case .textReplaced: .editText
        }
    }

    var replacedClipIDs: [UUID] {
        switch kind {
        case let .snippetsReplaced(replacements), let .snippetsMade(replacements), let .textReplaced(replacements):
            replacements.map(\.id)
        default: []
        }
    }

    public var heldBytes: Int {
        switch kind {
        case let .clipsDeleted(snapshots): snapshots.reduce(0) { $0 + $1.heldBytes }
        case let .collectionDeleted(snapshot): snapshot.heldBytes
        case let .clipsEdited(edits): edits.reduce(0) { $0 + $1.heldBytes }
        case let .collectionsChanged(_, changes): changes.reduce(0) { $0 + $1.heldBytes }
        case let .clipsAdded(added): added.heldBytes
        case let .snippetsReplaced(replacements), let .snippetsMade(replacements), let .textReplaced(replacements):
            replacements.reduce(0) { $0 + $1.heldBytes }
        }
    }

    private static func label(of added: AddedClips) -> UndoLabel {
        if added.kind == .collection { return .importCollection(added.boards.first?.name ?? "") }
        return .addClips(added.kind, added.count)
    }

    private static func label(of kind: CollectionChangeKind, _ changes: [CollectionChange]) -> UndoLabel {
        let name = changes.first?.name ?? ""
        return switch kind {
        case .create: .createCollection(name)
        case .edit: .editCollection(name)
        case .duplicate: .duplicateCollection(name)
        case .reorder: .reorderCollections
        }
    }
}
