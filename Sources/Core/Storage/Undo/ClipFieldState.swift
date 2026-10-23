// SPDX-License-Identifier: MIT
import Foundation

/// The clip fields a person changes by hand, which is all an edit's undo touches: a background write to the same clip
/// (a fetched page title, an embedding) is never rolled back with it.
public enum ClipField: String, CaseIterable, Sendable {
    case title, note, tags, icon, collection, pinned, shortcut, sensitive, expiry, order
}

public struct ClipFieldState: Equatable, Sendable {
    public var customTitle: String?
    public var userNote: String?
    public var tags: [String]
    public var customSymbolName: String?
    public var collectionID: UUID?
    public var collectionOrder: Int?
    public var isPinned: Bool
    public var pinnedHotkeyIndex: Int?
    public var isNSFW: Bool
    public var expiresAt: Date?

    public init(_ item: ClipboardItem) {
        let metadata = item.metadata
        customTitle = metadata.customTitle
        userNote = metadata.userNote
        tags = metadata.tags
        customSymbolName = metadata.customSymbolName
        collectionID = item.collectionID
        collectionOrder = metadata.collectionOrder
        isPinned = item.isPinned
        pinnedHotkeyIndex = item.pinnedHotkeyIndex
        isNSFW = item.isNSFW
        expiresAt = item.expiresAt
    }

    public func differences(from other: ClipFieldState) -> Set<ClipField> {
        var fields: Set<ClipField> = []
        if customTitle != other.customTitle { fields.insert(.title) }
        if userNote != other.userNote { fields.insert(.note) }
        if tags != other.tags { fields.insert(.tags) }
        if customSymbolName != other.customSymbolName { fields.insert(.icon) }
        if collectionID != other.collectionID { fields.insert(.collection) }
        if isPinned != other.isPinned { fields.insert(.pinned) }
        if pinnedHotkeyIndex != other.pinnedHotkeyIndex { fields.insert(.shortcut) }
        if isNSFW != other.isNSFW { fields.insert(.sensitive) }
        if expiresAt != other.expiresAt { fields.insert(.expiry) }
        if collectionOrder != other.collectionOrder { fields.insert(.order) }
        return fields
    }
}

/// One clip's edit: the fields that changed, with their value before and after.
public struct ClipEdit: Sendable {
    public let id: UUID
    public let fields: Set<ClipField>
    let before: ClipFieldState
    let after: ClipFieldState

    /// Nil when nothing a person can change differs.
    public init?(id: UUID, before: ClipFieldState, after: ClipFieldState) {
        let fields = after.differences(from: before)
        guard !fields.isEmpty else { return nil }
        self.id = id
        self.fields = fields
        self.before = before
        self.after = after
    }

    /// The field the label names when several moved together (a shortcut also pins the clip).
    var primaryField: ClipField {
        ClipField.allCases.first { fields.contains($0) } ?? .title
    }

    var heldBytes: Int {
        256 + [before, after].reduce(0) { $0 + ($1.userNote?.utf8.count ?? 0) + ($1.customTitle?.utf8.count ?? 0) }
    }
}
