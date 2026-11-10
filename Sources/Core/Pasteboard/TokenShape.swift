// SPDX-License-Identifier: MIT
import Foundation

/// Tells a name or an id from a secret. Entropy alone cannot: a 36-character kebab-case name has more of it than
/// many real keys, so an unprefixed token is only a key when it is also not shaped like something a person reads.
enum TokenShape {
    static func looksLikeIdentifier(_ token: String) -> Bool {
        guard token.contains(where: \.isNumber), token.contains(where: \.isLetter) else { return true }
        let segments = token.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard segments.count >= 3 else { return false }
        let readable = segments.count(where: { isWord($0) || $0.allSatisfy(\.isNumber) })
        return Double(readable) / Double(segments.count) >= 0.6
    }

    private static let vowels = Set("aeiouy")

    private static func isWord(_ segment: String) -> Bool {
        guard segment.allSatisfy(\.isLetter), segment.count <= 12 else { return false }
        if segment.count <= 3 { return true }
        let lower = segment.lowercased()
        guard segment == lower || segment == lower.capitalized else { return false }
        var consonantRun = 0
        var longestRun = 0
        for character in lower {
            consonantRun = vowels.contains(character) ? 0 : consonantRun + 1
            longestRun = max(longestRun, consonantRun)
        }
        return lower.contains(where: vowels.contains) && longestRun <= 5
    }
}
