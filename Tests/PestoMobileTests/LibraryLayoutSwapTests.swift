// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
@testable import PestoMobile

@Suite("What the library holds survives a change of layout, and a narrow regular width starts without the sidebar")
@MainActor
struct LibraryLayoutSwapTests {
    @Test("an open text edit is kept for its clip, and another clip opening drops it")
    func whenAClipOtherThanTheEditedOneOpens_thenTheDraftGoes() {
        let library = LibraryModel()
        let clip = UUID()
        library.open(clip)
        library.beginTextEdit(of: clip, text: "typed so far")
        library.textEdit?.draft += " and more"

        #expect(library.isEditingText(of: clip))
        #expect(library.textEdit?.draft == "typed so far and more")

        library.open(clip)
        #expect(library.isEditingText(of: clip), "opening the same clip again keeps the draft")

        library.open(UUID())
        #expect(library.textEdit == nil)
    }

    @Test("locking closes the editor and forgets the draft, which holds a clip's plaintext")
    func whenTheHistoryLocks_thenNoDraftStays() {
        let library = LibraryModel()
        let clip = UUID()
        library.open(clip)
        library.beginTextEdit(of: clip, text: "secret words")
        library.query = "words"

        library.closeEverything()

        #expect(library.textEdit == nil)
        #expect(library.openClipID == nil)
        #expect(library.query.isEmpty)
        #expect(library.scrollAnchor == nil)
    }

    @Test("the scope, the search and the first visible card are model state, not a layout's")
    func whenTheLayoutChanges_thenTheModelStillHoldsThem() {
        let library = LibraryModel()
        let anchor = CardIdentity(id: UUID(), content: "hash")
        library.scrollAnchor = anchor
        library.query = "basil"
        library.filter.scope = .pinned

        #expect(library.scrollAnchor == anchor)
        #expect(library.query == "basil")
        #expect(library.filter.scope == .pinned)
    }

    @Test("a regular width under 800 points starts with the sidebar hidden, a wider one shows it")
    func whenRegularAndNarrow_thenTheSidebarStartsHidden() {
        #expect(LibraryChrome.initialColumns(width: 507) == .detailOnly)
        #expect(LibraryChrome.initialColumns(width: 799) == .detailOnly)
        #expect(LibraryChrome.initialColumns(width: 800) == .all)
        #expect(LibraryChrome.initialColumns(width: 1180) == .all)
        #expect(LibraryChrome.showsChipRow(isRegular: true, columns: LibraryChrome.initialColumns(width: 600)))
    }
}
