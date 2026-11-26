// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The keyboard's search layouts follow the person's own keyboards")
struct SearchKeyboardLayoutTests {
    @Test("every layout has letter rows, no key twice and a badge")
    func whenAnyLayout_thenItIsWellFormed() {
        for layout in SearchKeyboardLayout.all {
            #expect(layout.rows.count >= 3, "\(layout.id)")
            #expect(layout.rows.allSatisfy { !$0.isEmpty }, "\(layout.id)")
            let keys = layout.rows.flatMap(\.self)
            #expect(Set(keys).count == keys.count, "\(layout.id) repeats a key")
            #expect(!layout.languageCode.isEmpty)
            if let shifted = layout.shiftedRows {
                #expect(shifted.map(\.count) == layout.rows.map(\.count), "\(layout.id) shift layer shape")
            }
        }
        #expect(Set(SearchKeyboardLayout.all.map(\.id)).count == SearchKeyboardLayout.all.count)
    }

    @Test("a language picks the layout iOS gives it")
    func whenLanguageCode_thenItsLayout() {
        let cases: [(String, String)] = [
            ("en-US", "qwerty"), ("it", "qwerty"), ("pt-BR", "qwerty"), ("nl", "qwerty"), ("pl", "qwerty"),
            ("es-ES", "spanish"), ("ca", "spanish"),
            ("fr-FR", "azerty"), ("fr-CA", "qwerty"), ("de-DE", "german"), ("de-CH", "german"),
            ("cs", "qwertz"), ("hu", "qwertz"), ("sv-SE", "swedish"), ("fi", "swedish"),
            ("da", "danish"), ("nb-NO", "norwegian"), ("no", "norwegian"), ("tr", "turkish"),
            ("ru", "russian"), ("be", "russian"), ("uk-UA", "ukrainian"), ("el", "greek"),
            ("he-IL", "hebrew"), ("iw", "hebrew"), ("ar-SA", "arabic"), ("fa-IR", "persian"),
            ("ko-KR", "korean"), ("th", "thai"), ("hi-IN", "hindi")
        ]
        for (code, id) in cases {
            #expect(SearchKeyboardLayout.layout(forLanguageCode: code)?.id == id, "\(code)")
        }
        #expect(SearchKeyboardLayout.layout(forLanguageCode: "emoji") == nil)
        #expect(SearchKeyboardLayout.layout(forLanguageCode: "dictation") == nil)
        #expect(SearchKeyboardLayout.layout(forLanguageCode: "") == nil)
    }

    @Test("a language with no letter grid of its own is reported, not silently swapped")
    func whenInputMethodLanguage_thenItIsUnsupported() {
        for code in ["ja-JP", "zh-Hans", "zh-Hant", "yue"] {
            #expect(SearchKeyboardLayout.layout(forLanguageCode: code) == nil, "\(code)")
            #expect(SearchKeyboardLayout.needsInputMethod(languageCode: code), "\(code)")
        }
        #expect(!SearchKeyboardLayout.needsInputMethod(languageCode: "en"))
    }

    @Test("the person's keyboards lead, then their languages, without repeats, and QWERTY when nothing fits")
    func whenResolving_thenInputModesLeadAndRepeatsDrop() {
        let ids = { (modes: [String], langs: [String]) in
            SearchKeyboardLayout.resolved(inputModeLanguages: modes, preferredLanguages: langs).map(\.id)
        }
        #expect(ids(["he-IL", "en-US", "en-GB", "emoji"], ["fr"]) == ["hebrew", "qwerty"])
        #expect(ids([], ["de-DE", "ko"]) == ["german", "korean"])
        #expect(ids(["ja-JP"], []) == ["qwerty"])
        #expect(ids([], []) == ["qwerty"])
    }

    @Test("the search page's language key names the layout in two capitals, as iOS writes it on its space bar")
    func whenShortNamed_thenTwoCapitals() throws {
        #expect(try #require(SearchKeyboardLayout.layout(forLanguageCode: "en")).shortName == "EN")
        #expect(try #require(SearchKeyboardLayout.layout(forLanguageCode: "he")).shortName == "HE")
        #expect(try #require(SearchKeyboardLayout.layout(forLanguageCode: "ru")).shortName == "RU")
    }

    @Test("the rows match iOS's own Hebrew, Turkish, German and Russian keyboards")
    func whenSpecificLayouts_thenRowsMatchTheSystem() throws {
        let hebrew = try #require(SearchKeyboardLayout.layout(forLanguageCode: "he"))
        #expect(hebrew.rows[0] == ["ק", "ר", "א", "ט", "ו", "ן", "ם", "פ"])
        #expect(hebrew.isRTL && !hebrew.isCased)
        let turkish = try #require(SearchKeyboardLayout.layout(forLanguageCode: "tr"))
        #expect(turkish.rows[0].suffix(3) == ["p", "ğ", "ü"])
        #expect(turkish.rows[1].suffix(2) == ["ş", "i"])
        let german = try #require(SearchKeyboardLayout.layout(forLanguageCode: "de"))
        #expect(german.rows[0].last == "ü" && german.rows[1].suffix(2) == ["ö", "ä"])
        let russian = try #require(SearchKeyboardLayout.layout(forLanguageCode: "ru"))
        #expect(russian.rows.map(\.count) == [11, 11, 9])
        #expect(russian.variants(for: "е") == ["ё"])
        #expect(russian.variants(for: "ь") == ["ъ"])
    }

    @Test("shift gives capitals in the layout's language, a fixed layer where one exists, nothing in a caseless script")
    func whenShifted_thenTheRightCharacters() throws {
        let qwerty = try #require(SearchKeyboardLayout.layout(forLanguageCode: "en"))
        #expect(qwerty.label(for: "a", shifted: true) == "A")
        let turkish = try #require(SearchKeyboardLayout.layout(forLanguageCode: "tr"))
        #expect(turkish.label(for: "i", shifted: true) == "İ")
        #expect(turkish.label(for: "ı", shifted: true) == "I")
        let thai = try #require(SearchKeyboardLayout.layout(forLanguageCode: "th"))
        #expect(thai.label(for: thai.rows[1][0], shifted: true) == thai.shiftedRows?[1][0])
        #expect(thai.hasShift)
        let hebrew = try #require(SearchKeyboardLayout.layout(forLanguageCode: "he"))
        #expect(!hebrew.hasShift)
        #expect(hebrew.label(for: "ש", shifted: true) == "ש")
    }

    @Test("Latin letters offer their accents on a long press, as iOS does")
    func whenLongPress_thenAccents() throws {
        let qwerty = try #require(SearchKeyboardLayout.layout(forLanguageCode: "en"))
        #expect(qwerty.variants(for: "e").contains("é"))
        #expect(qwerty.variants(for: "n").contains("ñ"))
        #expect(qwerty.variants(for: "s").contains("ß"))
        #expect(qwerty.variants(for: "q").isEmpty)
        let arabic = try #require(SearchKeyboardLayout.layout(forLanguageCode: "ar"))
        #expect(arabic.variants(for: "ا").contains("أ"))
        #expect(qwerty.variants(for: "e", shifted: true).contains("É"))
    }

    @Test("the Cyrillic grid types each neighbour language's own letters, and Serbian in Latin gets a Latin grid")
    func whenCyrillicNeighbour_thenItsLettersAreOnALongPress() throws {
        let serbian = try #require(SearchKeyboardLayout.layout(forLanguageCode: "sr"))
        let letters = Set(serbian.rows.joined()).union(serbian.rows.joined().flatMap { serbian.variants(for: $0) })
        for letter in ["љ", "њ", "ђ", "ћ", "џ", "ј", "ѓ", "ќ", "ѕ", "і", "ў", "ә", "ң", "қ", "ө", "ұ", "ү", "һ"] {
            #expect(letters.contains(letter), "\(letter) cannot be typed")
        }
        #expect(SearchKeyboardLayout.layout(forLanguageCode: "sr-Latn")?.id == "qwertz")
    }

    @Test("a shifted variant that has no one-letter capital stays one letter (ß, not SS)")
    func whenShiftedVariantHasNoCapital_thenItStaysOneLetter() throws {
        let german = try #require(SearchKeyboardLayout.layout(forLanguageCode: "de"))
        let shifted = german.variants(for: "s", shifted: true)
        #expect(shifted.allSatisfy { $0.count == 1 }, "\(shifted)")
    }
}
