// SPDX-License-Identifier: MIT
import Foundation

public enum PassphraseStrength: Equatable, Sendable {
    case tooShort
    case weak
    case fair
    case strong

    public var isAcceptable: Bool {
        self == .fair || self == .strong
    }

    private static let common: Set<String> = [
        "password", "passw0rd", "letmein", "qwerty", "iloveyou", "welcome", "admin", "123456", "backup", "pesto"
    ]

    /// Deliberately simple: the key behind the passphrase is slow to guess (600,000 rounds) and a recovery key is
    /// offered, so this only turns away the obvious.
    public static func evaluate(_ passphrase: String) -> PassphraseStrength {
        let trimmed = passphrase.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 10 else { return .tooShort }
        let lowered = trimmed.lowercased()
        if common.contains(where: { lowered.hasPrefix($0) }) || Set(lowered).count <= 4 { return .weak }
        let words = trimmed.split(separator: " ").count
        let classes = [
            trimmed.contains { $0.isLowercase }, trimmed.contains { $0.isUppercase },
            trimmed.contains { $0.isNumber }, trimmed.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        ].count(where: { $0 })
        if words >= 4 || trimmed.count >= 20 || (trimmed.count >= 14 && classes >= 3) { return .strong }
        return .fair
    }
}
