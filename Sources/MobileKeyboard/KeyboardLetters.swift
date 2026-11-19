// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The search page's keys (ADR 0063): lowercase letters or numbers and punctuation. They type into Pesto's own search
/// field and nowhere else: the only thing this view holds is the model, whose search methods change only the query,
/// and neither knows the app's text field (`KeyboardSearchTests` scans both).
struct KeyboardLetters: View {
    enum Alphabet: CaseIterable, Equatable {
        case qwerty
        case azerty
        case qwertz
        case hebrew
        case arabic
        case cyrillic
        case greek

        var isRTL: Bool {
            self == .hebrew || self == .arabic
        }

        var badge: String {
            switch self {
            case .qwerty: "ABC"
            case .azerty: "AZE"
            case .qwertz: "QWE"
            case .hebrew: "אבג"
            case .arabic: "أبج"
            case .cyrillic: "АБВ"
            case .greek: "ΑΒΓ"
            }
        }

        var rows: [[String]] {
            switch self {
            case .qwerty:
                [
                    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                    ["z", "x", "c", "v", "b", "n", "m"]
                ]
            case .azerty:
                [
                    ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
                    ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
                    ["w", "x", "c", "v", "b", "n"]
                ]
            case .qwertz:
                [
                    ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p"],
                    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                    ["y", "x", "c", "v", "b", "n", "m"]
                ]
            case .hebrew:
                [
                    ["ק", "ר", "א", "ט", "ו", "ן", "ם", "פ"],
                    ["ש", "ד", "ג", "כ", "ע", "י", "ח", "ל", "ך", "ף"],
                    ["ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת", "ץ"]
                ]
            case .arabic:
                [
                    ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج", "د"],
                    ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"],
                    ["ذ", "ئ", "ء", "ؤ", "ر", "ى", "ة", "و", "ز", "ظ"]
                ]
            case .cyrillic:
                [
                    ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
                    ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
                    ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
                ]
            case .greek:
                [
                    ["ς", "ε", "ρ", "τ", "υ", "θ", "ι", "ο", "π"],
                    ["α", "σ", "δ", "φ", "γ", "η", "ξ", "κ", "λ"],
                    ["ζ", "χ", "ψ", "ω", "β", "ν", "μ"]
                ]
            }
        }
    }

    enum Layout: Equatable {
        case letters(Alphabet)
        case digits
    }

    let model: KeyboardModel
    let layout: Layout

    private var rows: [[String]] {
        switch layout {
        case let .letters(alphabet):
            alphabet.rows
        case .digits:
            KeyboardPad.rows
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button { model.typeInSearch(key) } label: {
                            Text(verbatim: key)
                                .font(.title3)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 40)
                        }
                        .buttonStyle(KeyboardKeyStyle())
                    }
                }
                .padding(.horizontal, row.count < 10 ? CGFloat(10 - row.count) * 12 : 0)
            }
        }
        // Keycap rows follow physical keyboard order even when the interface direction is RTL.
        .environment(\.layoutDirection, .leftToRight)
    }

    static func resolvedAlphabets(
        inputModeLanguages: [String] = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage),
        preferredLanguages: [String] = Locale.preferredLanguages
    )
    -> [Alphabet] {
        let fromModes = deduplicatedAlphabets(from: inputModeLanguages)
        if !fromModes.isEmpty { return fromModes }
        let fromLocales = deduplicatedAlphabets(from: preferredLanguages)
        return fromLocales.isEmpty ? [.qwerty] : fromLocales
    }

    static var isActiveLocaleRTL: Bool {
        if resolvedAlphabets().first?.isRTL == true { return true }
        guard let first = Locale.preferredLanguages.first else { return false }
        return Locale.Language(identifier: first).characterDirection == .rightToLeft
    }

    private static func deduplicatedAlphabets(from codes: [String]) -> [Alphabet] {
        var result: [Alphabet] = []
        for code in codes {
            guard let alphabet = alphabet(forLanguageCode: code), !result.contains(alphabet) else { continue }
            result.append(alphabet)
        }
        return result
    }

    static func alphabet(forLanguageCode code: String) -> Alphabet? {
        let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return nil }
        if ["emoji", "dictation", "intl"].contains(language) { return nil }

        switch language {
        case "he", "iw":
            return .hebrew
        case "ar":
            return .arabic
        case "ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "tg", "mn":
            return .cyrillic
        case "el":
            return .greek
        case "fr":
            return parts.contains("ca") ? .qwerty : .azerty
        case "de", "cs", "sk", "hu", "hr", "sl":
            return .qwertz
        default:
            return .qwerty
        }
    }
}
