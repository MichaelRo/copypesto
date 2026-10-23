// SPDX-License-Identifier: MIT
import Foundation

/// What a collection change was, for its name in the banner and the Edit menu.
public enum CollectionChangeKind: Sendable {
    case create, edit, duplicate, reorder
}

/// One collection before and after an action. Nil `before` is a collection the action created; nil `after` is one it
/// removed. Undo sets the collection to `before`, redo to `after`.
public struct CollectionChange: Sendable {
    public let id: UUID
    let before: PinboardSnapshot?
    let after: PinboardSnapshot?

    public init(id: UUID, before: PinboardSnapshot?, after: PinboardSnapshot?) {
        self.id = id
        self.before = before
        self.after = after
    }

    var name: String {
        (after ?? before)?.name ?? ""
    }

    var heldBytes: Int {
        (before?.heldBytes ?? 0) + (after?.heldBytes ?? 0)
    }
}

public enum AddedClipsKind: Equatable, Sendable {
    case snippet, imported, collection
}

/// Clips an action added (a snippet, an import). While they are in the history the entry knows only their ids; once
/// undone it holds their sealed snapshots so that redo can put them back.
public struct AddedClips: Sendable {
    enum State {
        case present([UUID])
        case absent([ClipSnapshot])
    }

    public let kind: AddedClipsKind
    let state: State
    /// The collections the same import created, removed and restored with the clips.
    let boards: [PinboardSnapshot]

    public init(kind: AddedClipsKind, ids: [UUID], boards: [PinboardSnapshot] = []) {
        self.kind = kind
        state = .present(ids)
        self.boards = boards
    }

    init(kind: AddedClipsKind, snapshots: [ClipSnapshot], boards: [PinboardSnapshot]) {
        self.kind = kind
        state = .absent(snapshots)
        self.boards = boards
    }

    var count: Int {
        switch state {
        case let .present(ids): ids.count
        case let .absent(snapshots): snapshots.count
        }
    }

    var heldBytes: Int {
        let clips = switch state {
        case let .present(ids): ids.count * 32
        case let .absent(snapshots): snapshots.reduce(0) { $0 + $1.heldBytes }
        }
        return clips + boards.reduce(0) { $0 + $1.heldBytes }
    }
}

/// A clip whose content an action replaced (a snippet's text), before and after.
public struct ClipReplacement: Sendable {
    public let id: UUID
    let before: ClipSnapshot
    let after: ClipSnapshot

    public init(before: ClipSnapshot, after: ClipSnapshot) {
        id = before.id
        self.before = before
        self.after = after
    }

    var heldBytes: Int {
        before.heldBytes + after.heldBytes
    }
}
