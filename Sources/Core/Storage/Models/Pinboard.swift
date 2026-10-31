// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// User-curated organizational container — shown as a **Collection** in the UI.
///
/// The SwiftData entity name is kept as `Pinboard` (historical) so existing local
/// stores load without migration. New code may use the
/// `ClipCollection` typealias for clarity. See ADR 0007 for the naming rationale.
///
/// Static collections are referenced by `ClipboardItem.collectionID` (scalar FK).
/// Smart collections compute membership at query time via `smartPredicateData`.
@Model
public final class Pinboard {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// SF Symbol name, e.g. "link", "doc.text", "swift".
    public var symbolName: String
    /// Hex color "#RRGGBB" — drives the card's collection accent dot.
    public var colorHex: String
    public var sortOrder: Int

    public var isSmart: Bool
    /// Archived NSPredicate (or our typed `PredicateRule` envelope). Compiled at query time.
    public var smartPredicateData: Data?

    /// Schema version of the smart predicate, so a v2 sync layer can ignore unknowns.
    public var schemaVersion: Int

    /// Bundle ID of the app that auto-selects this collection when it becomes frontmost.
    /// Nil means no workspace trigger (default). Only one collection should claim a given bundle ID.
    public var triggerBundleID: String?

    /// Sync (ADR 0018); see `ClipboardItem.changeClock`.
    public var changeClock: String?
    public var syncOrigin: String?
    public var syncFingerprint: String?
    public var syncDirty: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        colorHex: String,
        sortOrder: Int,
        isSmart: Bool = false,
        smartPredicateData: Data? = nil,
        schemaVersion: Int = 1,
        triggerBundleID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isSmart = isSmart
        self.smartPredicateData = smartPredicateData
        self.schemaVersion = schemaVersion
        self.triggerBundleID = triggerBundleID
    }
}

/// User-facing alias. New code may refer to a collection as `ClipCollection` — the
/// canonical `Pinboard` name is retained only for SwiftData entity-name continuity.
public typealias ClipCollection = Pinboard
