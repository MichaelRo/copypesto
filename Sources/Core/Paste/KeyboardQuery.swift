// SPDX-License-Identifier: MIT
import Foundation

/// The text in the keyboard's own search field (ADR 0063). Its letter keys type here and nowhere else: never into the
/// app the person is writing in. It lives only while the search page is open.
public struct KeyboardQuery: Equatable, Sendable {
    public static let maxLength = 64

    public private(set) var text = ""

    public init(starting word: String? = nil) {
        text = String((word ?? "").prefix(Self.maxLength))
    }

    /// What to search for: the text without spaces at its ends, once it holds a letter or digit.
    public var search: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.contains { $0.isLetter || $0.isNumber } ? trimmed : nil
    }

    public mutating func type(_ characters: String) {
        text = String((text + characters).prefix(Self.maxLength))
    }

    /// Korean jamo join the syllable before them (`HangulComposer`); anything else is typed as it is.
    public mutating func type(_ characters: String, composingHangul: Bool) {
        guard composingHangul else { return type(characters) }
        text = String(HangulComposer.appending(characters, to: text).prefix(Self.maxLength))
    }

    public mutating func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    /// On a Korean layout Delete takes back one jamo, as iOS's Korean keyboard does.
    public mutating func deleteBackward(decomposingHangul: Bool) {
        guard decomposingHangul else { return deleteBackward() }
        text = HangulComposer.deletingLast(from: text)
    }

    public mutating func clear() {
        text = ""
    }

    /// Strips Hebrew niqqud (`\u{0591}`–`\u{05C7}`) and folds Hebrew final letters (`ךםןףץ` → `כמנפצ`) for matching.
    public static func normalizedForSearch(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            if (0x0591...0x05C7).contains(scalar.value) { continue }
            switch scalar.value {
            case 0x05DA: scalars.append("כ") // ך → כ
            case 0x05DD: scalars.append("מ") // ם → מ
            case 0x05DF: scalars.append("נ") // ן → נ
            case 0x05E3: scalars.append("פ") // ף → פ
            case 0x05E5: scalars.append("צ") // ץ → צ
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
