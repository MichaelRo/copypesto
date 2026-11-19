// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// A collection's name, icon and color while the editor is open, from Core's lists (`CollectionSymbols`,
/// `CollectionPalette`), which are the Mac's choices too.
struct CollectionDraft: Equatable {
    var name: String
    var symbol: String
    var colorHex: String
    /// A smart collection fills itself from rules; `rules` is nil when a collection made elsewhere has rules this
    /// version cannot read, which saving leaves as they are.
    var isSmart = false
    var rules: SmartRulesDraft? = SmartRulesDraft.starter

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
        isSmart = board.isSmart
        rules = board.isSmart ? SmartRulesDraft(data: board.smartPredicateData) : SmartRulesDraft.starter
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

    /// A smart collection can be saved once every rule is filled in (and a plain one always can).
    var canSave: Bool {
        !isSmart || rules?.isComplete != false
    }

    func differs(from board: Pinboard) -> Bool {
        (!trimmedName.isEmpty && trimmedName != board.name) || symbol != board.symbolName
            || !CollectionPalette.isSame(colorHex, board.colorHex) || rulesDiffer(from: board)
    }

    func rulesDiffer(from board: Pinboard) -> Bool {
        guard board.isSmart, isSmart, let rules else { return false }
        return rules != SmartRulesDraft(data: board.smartPredicateData)
    }
}
