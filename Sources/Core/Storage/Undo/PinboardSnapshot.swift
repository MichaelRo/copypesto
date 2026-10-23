// SPDX-License-Identifier: MIT
import Foundation

/// A collection as it was stored, kept to put it back (a delete) or to set it back (an edit). Its clips keep their
/// `collectionID`, so putting the collection back with the same id is all it takes for them to belong to it again.
public struct PinboardSnapshot: Equatable, Sendable {
    public let id: UUID
    public let name: String
    let symbolName: String
    let colorHex: String
    let sortOrder: Int
    let isSmart: Bool
    let smartPredicateData: Data?
    let schemaVersion: Int
    let triggerBundleID: String?

    public init(
        id: UUID = UUID(), name: String, symbolName: String = "folder", colorHex: String = "#3DAF60",
        sortOrder: Int = 0, isSmart: Bool = false, smartPredicateData: Data? = nil, schemaVersion: Int = 1,
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

    init(_ board: Pinboard) {
        self.init(
            id: board.id, name: board.name, symbolName: board.symbolName, colorHex: board.colorHex,
            sortOrder: board.sortOrder, isSmart: board.isSmart, smartPredicateData: board.smartPredicateData,
            schemaVersion: board.schemaVersion, triggerBundleID: board.triggerBundleID
        )
    }

    var heldBytes: Int {
        512 + (smartPredicateData?.count ?? 0)
    }

    func makeBoard(named name: String) -> Pinboard {
        Pinboard(
            id: id, name: name, symbolName: symbolName, colorHex: colorHex, sortOrder: sortOrder, isSmart: isSmart,
            smartPredicateData: smartPredicateData, schemaVersion: schemaVersion, triggerBundleID: triggerBundleID
        )
    }

    /// Sets an existing collection back to this state, leaving its clips (which belong by `collectionID`) alone.
    func write(to board: Pinboard) {
        board.name = name
        board.symbolName = symbolName
        board.colorHex = colorHex
        board.sortOrder = sortOrder
        board.isSmart = isSmart
        board.smartPredicateData = smartPredicateData
        board.schemaVersion = schemaVersion
        board.triggerBundleID = triggerBundleID
    }
}
