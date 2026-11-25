// SPDX-License-Identifier: MIT
import Foundation

/// Joins Korean jamo typed one at a time into syllables, as the two-set (Dubeolsik) keyboard does, for the keyboard's
/// own search field (ADR 0066). Anything that is not a compatibility jamo is appended as it is.
public enum HangulComposer {
    private static let syllableBase: UInt32 = 0xAC00
    private static let syllableLast: UInt32 = 0xD7A3
    private static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final".
    private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map(Optional.some)

    private static let compoundVowels: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"
    ]
    private static let compoundFinals: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ",
        "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"
    ]

    private struct Syllable {
        var initial: Int
        var vowel: Int
        var final: Int

        var character: Character {
            let value = HangulComposer.syllableBase + UInt32((initial * 21 + vowel) * 28 + final)
            return Character(UnicodeScalar(value) ?? "?")
        }
    }

    public static func appending(_ typed: String, to text: String) -> String {
        guard typed.count == 1, let jamo = typed.first, isJamo(jamo) else { return text + typed }
        guard let last = text.last else { return typed }
        let head = String(text.dropLast())

        if var syllable = syllable(of: last) {
            if let vowelIndex = vowels.firstIndex(of: jamo) {
                if syllable.final == 0 {
                    guard let joined = compoundVowels[String([vowels[syllable.vowel], jamo])],
                          let index = vowels.firstIndex(of: joined) else { return text + typed }
                    syllable.vowel = index
                    return head + String(syllable.character)
                }
                return head + movingFinal(of: syllable, before: vowelIndex)
            }
            if syllable.final == 0 {
                guard let index = finals.firstIndex(of: jamo) else { return text + typed }
                syllable.final = index
                return head + String(syllable.character)
            }
            guard let current = finals[syllable.final],
                  let joined = compoundFinals[String([current, jamo])],
                  let index = finals.firstIndex(of: joined) else { return text + typed }
            syllable.final = index
            return head + String(syllable.character)
        }

        if let initial = initials.firstIndex(of: last), let vowel = vowels.firstIndex(of: jamo) {
            return head + String(Syllable(initial: initial, vowel: vowel, final: 0).character)
        }
        if vowels.contains(last), let joined = compoundVowels[String([last, jamo])] {
            return head + String(joined)
        }
        return text + typed
    }

    /// Takes back the last jamo of the last syllable (a final, then half of a compound vowel, then the vowel), or the
    /// last character of anything else.
    public static func deletingLast(from text: String) -> String {
        guard let last = text.last else { return text }
        let head = String(text.dropLast())
        guard var syllable = syllable(of: last) else {
            if let split = splitCompoundVowel(last) { return head + String(split.first) }
            return head
        }
        if syllable.final != 0 {
            if let current = finals[syllable.final], let pair = compoundFinals.first(where: { $0.value == current }),
               let first = pair.key.first, let index = finals.firstIndex(of: first)
            {
                syllable.final = index
            } else {
                syllable.final = 0
            }
            return head + String(syllable.character)
        }
        if let split = splitCompoundVowel(vowels[syllable.vowel]), let index = vowels.firstIndex(of: split.first) {
            syllable.vowel = index
            return head + String(syllable.character)
        }
        return head + String(initials[syllable.initial])
    }

    private static func movingFinal(of syllable: Syllable, before vowel: Int) -> String {
        guard let final = finals[syllable.final] else { return String(syllable.character) }
        var kept = syllable
        let moving: Character
        if let pair = compoundFinals.first(where: { $0.value == final }), let first = pair.key.first,
           let second = pair.key.last, let index = finals.firstIndex(of: first)
        {
            kept.final = index
            moving = second
        } else {
            kept.final = 0
            moving = final
        }
        guard let initial = initials.firstIndex(of: moving) else {
            return String(syllable.character) + String(vowels[vowel])
        }
        return String(kept.character) + String(Syllable(initial: initial, vowel: vowel, final: 0).character)
    }

    private static func syllable(of character: Character) -> Syllable? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
              (syllableBase...syllableLast).contains(scalar.value) else { return nil }
        let offset = Int(scalar.value - syllableBase)
        return Syllable(initial: offset / (21 * 28), vowel: (offset % (21 * 28)) / 28, final: offset % 28)
    }

    private static func splitCompoundVowel(_ vowel: Character) -> (first: Character, second: Character)? {
        guard let pair = compoundVowels.first(where: { $0.value == vowel }), let first = pair.key.first,
              let second = pair.key.last else { return nil }
        return (first, second)
    }

    private static func isJamo(_ character: Character) -> Bool {
        initials.contains(character) || vowels.contains(character) || finals.contains(character)
    }
}
