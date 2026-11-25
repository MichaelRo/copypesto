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
        // SourceTree lives in the regression target; this one reads the four files by name and throws if one moves.
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MobileKeyboard")
        for name in [
            "KeyboardLetters.swift",
            "KeyboardLetterKey.swift",
            "KeyboardModel.swift",
            "KeyboardSearchPage.swift"
        ] {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for forbidden in ["textDocumentProxy", "KeyboardKeys", "insertText", "UIInputViewController"] {
                #expect(!text.contains(forbidden), "\(name) names \(forbidden)")
            }
        }
    }

    @Test("the page offers the layouts of the person's own keyboards, in order, and names those it cannot type")
    func whenResolvingLayouts_thenInputModesLeadAndInputMethodsAreNamed() {
        #expect(
            KeyboardLetters.resolvedLayouts(
                inputModeLanguages: ["emoji", "fr-FR", "he-IL", "dictation", "es-ES"],
                preferredLanguages: ["en-US"]
            ).map(\.id) == ["azerty", "hebrew", "spanish"]
        )
        #expect(
            KeyboardLetters.resolvedLayouts(inputModeLanguages: ["emoji"], preferredLanguages: ["he-IL", "en-US"])
                .map(\.id) == ["hebrew", "qwerty"]
        )
        #expect(KeyboardLetters.inputMethodLanguages(inputModeLanguages: ["en-US", "ja-JP", "zh-Hans"]) == [
            "ja-JP",
            "zh-Hans"
        ])
    }

    @Test("Korean typed on the page joins into syllables, and Delete takes back one jamo")
    func whenKorean_thenTheQueryComposes() {
        let model = KeyboardModel()
        model.openSearch()
        for jamo in ["ㅎ", "ㅏ", "ㄴ"] {
            model.typeInSearch(jamo, composingHangul: true)
        }
        #expect(model.searchQuery?.text == "한")
        model.deleteInSearch(decomposingHangul: true)
        #expect(model.searchQuery?.text == "하")
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

    @Test("keyboard interface direction follows preferred UI language, not active RTL input mode")
    func whenPreferredLanguageIsEnglish_thenInterfaceRemainsLTR() {
        #expect(!KeyboardLetters.isInterfaceRTL(preferredLocalizations: ["en"], preferredLanguages: ["en-US"]))
        #expect(KeyboardLetters.isInterfaceRTL(preferredLocalizations: ["he"], preferredLanguages: ["he-IL"]))
        #expect(!KeyboardLetters.isInterfaceRTL(preferredLocalizations: [], preferredLanguages: ["en-US"]))
    }
}
