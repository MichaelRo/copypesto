// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// A collection's name, icon and color while the editor is open, from Core's lists (`CollectionSymbols`,
/// `CollectionPalette`), which are the Mac's choices too.
struct CollectionDraft: Equatable {
    var name: String
    var symbol: String
    var colorHex: String

    static func new(existing: [Pinboard]) -> CollectionDraft {
        CollectionDraft(
            name: "", symbol: "folder", colorHex: CollectionPalette.nextUnused(used: existing.map(\.colorHex))
        )
    }

    init(name: String, symbol: String, colorHex: String) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
    }

    init(_ board: Pinboard) {
        self.init(name: board.name, symbol: board.symbolName, colorHex: board.colorHex)
    }

    /// The icons offered: Core's list, with the collection's own first when it is something else (an emoji, or a
    /// symbol the Mac set), so editing never drops it.
    var symbolChoices: [String] {
        CollectionSymbols.symbols.contains(symbol) ? CollectionSymbols.symbols : [symbol] + CollectionSymbols.symbols
    }

    var colorChoices: [String] {
        CollectionPalette.isCustom(colorHex) ? [colorHex] + CollectionPalette.colors : CollectionPalette.colors
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func differs(from board: Pinboard) -> Bool {
        (!trimmedName.isEmpty && trimmedName != board.name) || symbol != board.symbolName
            || !CollectionPalette.isSame(colorHex, board.colorHex)
    }
}
