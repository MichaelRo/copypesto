// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
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

    @Test("the search page, its keys and the model know nothing of the app's text field")
    func whenScanned_thenTheLettersCannotReachTheApp() throws {
        // SourceTree lives in the regression target; this one reads the three files by name and throws if one moves.
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MobileKeyboard")
        for name in ["KeyboardLetters.swift", "KeyboardModel.swift", "KeyboardSearchPage.swift"] {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for forbidden in ["textDocumentProxy", "KeyboardKeys", "insertText", "UIInputViewController"] {
                #expect(!text.contains(forbidden), "\(name) names \(forbidden)")
            }
        }
    }

    @Test("all seven search alphabets provide three rows and report RTL accurately")
    func whenAlphabetSelected_thenRowsAndDirectionMatch() {
        for alphabet in KeyboardLetters.Alphabet.allCases {
            #expect(alphabet.rows.count == 3)
            #expect(alphabet.rows.allSatisfy { !$0.isEmpty })
        }
        #expect(KeyboardLetters.Alphabet.azerty.rows[0].prefix(3) == ["a", "z", "e"])
        #expect(KeyboardLetters.Alphabet.qwertz.rows[0].contains("z"))
        #expect(KeyboardLetters.Alphabet.qwertz.rows[2].contains("y"))
        #expect(KeyboardLetters.Alphabet.hebrew.rows[1].contains("ש"))
        #expect(KeyboardLetters.Alphabet.arabic.rows[0].contains("ض"))
        #expect(KeyboardLetters.Alphabet.cyrillic.rows[0].contains("й"))
        #expect(KeyboardLetters.Alphabet.greek.rows[1].contains("α"))

        #expect(KeyboardLetters.Alphabet.hebrew.isRTL)
        #expect(KeyboardLetters.Alphabet.arabic.isRTL)
        #expect(!KeyboardLetters.Alphabet.qwerty.isRTL)
        #expect(!KeyboardLetters.Alphabet.azerty.isRTL)
        #expect(!KeyboardLetters.Alphabet.qwertz.isRTL)
        #expect(!KeyboardLetters.Alphabet.cyrillic.isRTL)
        #expect(!KeyboardLetters.Alphabet.greek.isRTL)
    }

    @Test("active input modes resolve layouts in order and fall back to preferred languages")
    func whenResolvingAlphabets_thenInputModesLeadAndPreferredLanguagesFallback() {
        #expect(
            KeyboardLetters.resolvedAlphabets(
                inputModeLanguages: ["emoji", "fr-FR", "he-IL", "dictation", "es-ES"],
                preferredLanguages: ["en-US"]
            ) == [.azerty, .hebrew, .qwerty]
        )
        #expect(
            KeyboardLetters.resolvedAlphabets(
                inputModeLanguages: ["de-DE", "ar-SA", "ru-RU", "el-GR"],
                preferredLanguages: []
            ) == [.qwertz, .arabic, .cyrillic, .greek]
        )
        #expect(
            KeyboardLetters.resolvedAlphabets(
                inputModeLanguages: ["emoji"],
                preferredLanguages: ["he-IL", "en-US"]
            ) == [.hebrew, .qwerty]
        )
        #expect(
            KeyboardLetters.resolvedAlphabets(inputModeLanguages: [], preferredLanguages: []) == [.qwerty]
        )
    }

    @Test("clip card layout direction follows the clip's own script")
    func whenClipHasText_thenCardDirectionMatchesScript() {
        #expect(KeyboardClipKey.layoutDirection(for: "שלום עולם") == .rightToLeft)
        #expect(KeyboardClipKey.layoutDirection(for: "مرحبا بالعالم") == .rightToLeft)
        #expect(KeyboardClipKey.layoutDirection(for: "Basil pesto") == .leftToRight)
        #expect(KeyboardClipKey.layoutDirection(for: "Привет мир") == .leftToRight)
        #expect(KeyboardClipKey.layoutDirection(for: "Γεια σου") == .leftToRight)
        #expect(KeyboardClipKey.layoutDirection(for: "12345") == nil)
    }
}
