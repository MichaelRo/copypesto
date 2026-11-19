// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// The search page's letters type into Pesto's own field and never into the app (ADR 0063).
@Suite("The keyboard's search page")
@MainActor
struct KeyboardSearchTests {
    @Test("typing, deleting and clearing change only the page's own query, which closing drops")
    func whenTyped_thenOnlyTheQueryChanges() {
        let model = KeyboardModel()
        model.typeInSearch("x")
        #expect(model.searchQuery == nil)
        model.openSearch()
        model.typeInSearch("b")
        model.typeInSearch("asil")
        #expect(model.searchQuery?.search == "basil")
        model.deleteInSearch()
        #expect(model.searchQuery?.text == "basi")
        model.clearSearch()
        #expect(model.searchQuery?.text.isEmpty == true)
        model.closeSearch()
        #expect(model.searchQuery == nil)
        #expect(!model.isSearching)
    }

    @Test("the letters and the model know nothing of the app's text field")
    func whenScanned_thenTheLettersCannotReachTheApp() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MobileKeyboard")
        for name in ["KeyboardLetters.swift", "KeyboardModel.swift"] {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for forbidden in ["textDocumentProxy", "KeyboardKeys", "insertText", "UIInputViewController"] {
                #expect(!text.contains(forbidden), "\(name) names \(forbidden)")
            }
        }
    }
}
