// SPDX-License-Identifier: MIT
import Foundation

/// One letter layout for the keyboard's own search field (ADR 0066), as iOS draws it for that language: the rows, a
/// shift layer where the script has one, the long-press accents, and where Delete sits. The search page offers the
/// layouts of the person's own keyboards (`resolved`).
public struct SearchKeyboardLayout: Equatable, Identifiable, Sendable {
    public let id: String
    /// The language whose name the space bar shows and whose rules uppercase its letters.
    public let languageCode: String
    public let rows: [[String]]
    /// A fixed second layer (Thai, Hindi, Korean); nil where Shift means capitals or nothing.
    public let shiftedRows: [[String]]?
    public let isRTL: Bool
    public let isCased: Bool
    public let composesHangul: Bool
    /// The row whose trailing key is Delete: the third on most layouts, the first on Hebrew's.
    public let deleteRow: Int
    let variantTable: [String: [String]]

    init(
        id: String, languageCode: String, rows: [[String]], shiftedRows: [[String]]? = nil, isRTL: Bool = false,
        isCased: Bool = true, composesHangul: Bool = false, deleteRow: Int? = nil, variants: [String: [String]] = [:]
    ) {
        self.id = id
        self.languageCode = languageCode
        self.rows = rows
        self.shiftedRows = shiftedRows
        self.isRTL = isRTL
        self.isCased = isCased
        self.composesHangul = composesHangul
        self.deleteRow = deleteRow ?? rows.count - 1
        variantTable = variants
    }

    public var hasShift: Bool {
        isCased || shiftedRows != nil
    }

    public func label(for key: String, shifted: Bool) -> String {
        guard shifted else { return key }
        if let shiftedRows {
            for (rowIndex, row) in rows.enumerated() {
                if let column = row.firstIndex(of: key) { return shiftedRows[rowIndex][column] }
            }
            return key
        }
        return isCased ? key.uppercased(with: Locale(identifier: languageCode)) : key
    }

    public func variants(for key: String, shifted: Bool = false) -> [String] {
        let found = variantTable[key] ?? []
        guard shifted, isCased else { return found }
        let locale = Locale(identifier: languageCode)
        return found.map { $0.uppercased(with: locale) }
    }
}

public extension SearchKeyboardLayout {
    static func layout(forLanguageCode code: String) -> SearchKeyboardLayout? {
        let parts = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return nil }
        if ["emoji", "dictation", "intl"].contains(language) || needsInputMethod(languageCode: language) { return nil }
        let id = if language == "fr" {
            parts.contains("ca") ? "qwerty" : parts.contains("ch") ? "qwertz" : "azerty"
        } else {
            layoutIDByLanguage[language] ?? "qwerty"
        }
        return all.first { $0.id == id }
    }

    /// Languages whose iOS keyboard is not QWERTY; every other language with a letter grid uses QWERTY.
    private static let layoutIDByLanguage: [String: String] = {
        let groups: [String: [String]] = [
            "hebrew": ["he", "iw"], "arabic": ["ar"], "persian": ["fa"], "ukrainian": ["uk"], "greek": ["el"],
            "russian": ["ru", "be", "kk", "ky", "tg", "mn", "bg", "sr", "mk"], "korean": ["ko"], "thai": ["th"],
            "hindi": ["hi", "mr", "ne"], "turkish": ["tr"], "spanish": ["es", "ca", "gl", "eu"],
            "swedish": ["sv", "fi"], "danish": ["da"], "norwegian": ["nb", "nn", "no"], "german": ["de"],
            "qwertz": ["cs", "sk", "hu", "hr", "sl", "sq"]
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { id, codes in codes.map { ($0, id) } })
    }()

    /// A language typed through an input method (kana and kanji, pinyin and hanzi): a letter grid cannot type it, so
    /// the page says so rather than pretending.
    static func needsInputMethod(languageCode code: String) -> Bool {
        let language = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
        return ["ja", "zh", "yue"].contains(language.map(String.init) ?? "")
    }

    /// The person's keyboards first; their languages only when no keyboard has a layout here; QWERTY when nothing fits.
    static func resolved(
        inputModeLanguages: [String], preferredLanguages: [String]
    )
    -> [SearchKeyboardLayout] {
        func unique(_ codes: [String]) -> [SearchKeyboardLayout] {
            var result: [SearchKeyboardLayout] = []
            for code in codes {
                guard let layout = layout(forLanguageCode: code), !result.contains(layout) else { continue }
                result.append(layout)
            }
            return result
        }
        let fromModes = unique(inputModeLanguages)
        if !fromModes.isEmpty { return fromModes }
        let fromLanguages = unique(preferredLanguages)
        return fromLanguages.isEmpty ? [qwerty] : fromLanguages
    }

    static let all: [SearchKeyboardLayout] = [
        SearchKeyboardLayouts.qwerty, SearchKeyboardLayouts.spanish, SearchKeyboardLayouts.azerty,
        SearchKeyboardLayouts.german,
        SearchKeyboardLayouts.qwertz, SearchKeyboardLayouts.swedish, SearchKeyboardLayouts.danish,
        SearchKeyboardLayouts.norwegian, SearchKeyboardLayouts.turkish, SearchKeyboardLayouts.russian,
        SearchKeyboardLayouts.ukrainian, SearchKeyboardLayouts.greek, SearchKeyboardLayouts.hebrew,
        SearchKeyboardLayouts.arabic, SearchKeyboardLayouts.persian, SearchKeyboardLayouts.korean,
        SearchKeyboardLayouts.thai, SearchKeyboardLayouts.hindi
    ]

    static var qwerty: SearchKeyboardLayout {
        SearchKeyboardLayouts.qwerty
    }
}
