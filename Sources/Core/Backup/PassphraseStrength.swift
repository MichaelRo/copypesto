// SPDX-License-Identifier: MIT
import Foundation

public enum PassphraseStrength: Equatable, Sendable {
    case tooShort
    case weak
    case fair
    case strong

    /// Only a strong passphrase is accepted: the wrapped key sits in a file in a folder anyone with access to the
    /// folder can copy, so a person who guesses passphrases offline is the attacker this is for. A recovery key is the
    /// alternative that needs no passphrase at all.
    public var isAcceptable: Bool {
        self == .strong
    }

    public static let minimumLength = 12
    static let longestRun = 4

    private static let common: [String] = [
        "password", "passw0rd", "letmein", "qwerty", "iloveyou", "welcome", "admin", "123456", "backup", "pesto",
        "dragon", "monkey", "sunshine", "football", "baseball", "master", "shadow", "trustno1", "abc123", "login",
        "princess", "starwars", "whatever", "changeme", "secret", "computer", "michael", "jennifer", "superman"
    ]

    /// Deliberately simple, with no list of every breached password: it turns away a common word anywhere in the
    /// passphrase, a run such as `abcde` or `12345`, and too few different characters. The key behind the passphrase
    /// is slow to guess (600,000 rounds), but that slows a guess down, it does not make a guessable passphrase safe.
    public static func evaluate(_ passphrase: String) -> PassphraseStrength {
        let trimmed = passphrase.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= minimumLength else { return .tooShort }
        let lowered = trimmed.lowercased()
        let squeezed = lowered.filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        if common.contains(where: { squeezed.contains($0) }) || Set(lowered).count <= 5 || hasRun(squeezed) {
            return .weak
        }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "-" }).count
        let classes = [
            trimmed.contains { $0.isLowercase }, trimmed.contains { $0.isUppercase },
            trimmed.contains { $0.isNumber }, trimmed.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        ].count(where: { $0 })
        if words >= 4 || trimmed.count >= 20 || (trimmed.count >= 14 && classes >= 3) { return .strong }
        return .fair
    }

    /// More than `longestRun` characters in a row that each follow the last by one (abcde, 54321).
    private static func hasRun(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars.map(\.value))
        var up = 1, down = 1
        for index in scalars.indices.dropFirst() {
            up = scalars[index] == scalars[index - 1] + 1 ? up + 1 : 1
            down = scalars[index] + 1 == scalars[index - 1] ? down + 1 : 1
            if max(up, down) > longestRun { return true }
        }
        return false
    }
}
