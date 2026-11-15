// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("A collection's name, icon and color are chosen and changed as one undoable action")
@MainActor
struct CollectionEditingTests {
    @Test("a new collection keeps the icon and color chosen for it")
    func whenCreatedWithAnIcon_thenItIsStored() async throws {
        let library = try await MobileTestLibrary()
        var draft = CollectionDraft.new(existing: [])
        draft.name = "Recipes"
        draft.symbol = "leaf"
        draft.colorHex = "FF9500"

        let board = try #require(library.state.addCollection(draft, existing: []))

        #expect(board.symbolName == "leaf")
        #expect(board.colorHex == "FF9500")
        #expect(library.state.undoHistory?.undoLabel == .createCollection("Recipes"))
    }

    @Test("changing the icon and color is one edit that Undo takes back")
    func whenIconChanged_thenUndoRestoresIt() async throws {
        let library = try await MobileTestLibrary()
        let board = try #require(library.state.addCollection(named: "Trip", existing: []))
        let symbolBefore = board.symbolName
        let colorBefore = board.colorHex
        var draft = CollectionDraft(board)
        draft.symbol = "globe"
        draft.colorHex = "AF52DE"

        library.state.updateCollection(board, to: draft, existing: [board])
        #expect(board.symbolName == "globe")
        #expect(board.colorHex == "AF52DE")
        #expect(board.name == "Trip")
        #expect(library.state.undoHistory?.undoLabel == .editCollection("Trip"))

        await library.state.undo()
        try await library.refreshed()
        let container = try #require(library.state.historyContainer)
        let restored = try #require(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).first)
        #expect(restored.symbolName == symbolBefore)
        #expect(restored.colorHex == colorBefore)
    }

    @Test("saving what did not change records nothing")
    func whenNothingChanged_thenNothingIsRecorded() async throws {
        let library = try await MobileTestLibrary()
        let board = try #require(library.state.addCollection(named: "Trip", existing: []))
        let recorded = library.state.undoHistory?.recordedCount

        library.state.updateCollection(board, to: CollectionDraft(board), existing: [board])

        #expect(library.state.undoHistory?.recordedCount == recorded)
    }

    @Test("an icon the lists do not hold (an emoji, a symbol the Mac set) is kept among the choices")
    func whenIconIsOutsideTheList_thenItStaysOffered() {
        let draft = CollectionDraft(name: "Fun", symbol: "🎉", colorHex: "#2F8B4C")
        #expect(draft.symbolChoices.first == "🎉")
        #expect(draft.symbolChoices.count == CollectionSymbols.symbols.count + 1)
        #expect(draft.colorChoices.first == "#2F8B4C")
        let listed = CollectionDraft(name: "Work", symbol: "star", colorHex: "007AFF")
        #expect(listed.symbolChoices == CollectionSymbols.symbols)
        #expect(listed.colorChoices == CollectionPalette.colors)
    }
}
