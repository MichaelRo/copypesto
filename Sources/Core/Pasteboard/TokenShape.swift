// SPDX-License-Identifier: MIT
import Foundation

enum TokenShape {
    static func looksLikeIdentifier(_ token: String) -> Bool {
        if token.allSatisfy(\.isNumber) { return true }
        if isHexDigest(token) { return true }
        let segments = token.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if segments.count >= 2 {
            return separatedLooksLikeIdentifier(segments)
        }
        return singleSegmentLooksLikeIdentifier(token)
    }

    private static func isHexDigest(_ token: String) -> Bool {
        (token.count == 40 || token.count == 64)
            && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func separatedLooksLikeIdentifier(_ segments: [String]) -> Bool {
        // Any long non-word, non-digit chunk (like acme-prod-api-<random> or sk_live_<random>) is a secret payload.
        guard segments.allSatisfy({ $0.count < 12 || $0.allSatisfy(\.isNumber) || isWord($0) }) else {
            return false
        }
        let readable = segments.count(where: isReadableSegment)
        let threshold = segments.count == 2 ? 1.0 : 0.6
        return Double(readable) / Double(segments.count) >= threshold
    }

    private static func singleSegmentLooksLikeIdentifier(_ token: String) -> Bool {
        let words = splitCamelCase(token).filter { !$0.allSatisfy(\.isNumber) }
        guard words.count >= 3 else { return false }
        let longWordCharacters = words.filter { $0.count >= 4 && isWord($0) }.reduce(0) { $0 + $1.count }
        return Double(longWordCharacters) / Double(token.count) >= 0.6
    }

    private static func splitCamelCase(_ token: String) -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in token.unicodeScalars {
            let character = Character(scalar)
            if character.isUppercase, !current.isEmpty, current.last?.isLowercase == true {
                words.append(current)
                current = String(character)
            } else if character.isNumber, !current.isEmpty, current.last?.isNumber == false {
                words.append(current)
                current = String(character)
            } else if !character.isNumber, !current.isEmpty, current.last?.isNumber == true {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static let vowels = Set("aeiouy")

    private static func isReadableSegment(_ segment: String) -> Bool {
        if segment.allSatisfy(\.isNumber) || isWord(segment) { return true }
        // Region/version/environment markers like "gov3", "ec2", "us1", "v12".
        guard let firstDigit = segment.firstIndex(where: \.isNumber) else { return false }
        let prefix = String(segment[..<firstDigit])
        let suffix = String(segment[firstDigit...])
        return !prefix.isEmpty && prefix.count <= 8 && suffix.count <= 3
            && prefix.allSatisfy(\.isLetter) && suffix.allSatisfy(\.isNumber)
            && isWord(prefix)
    }

    private static func isWord(_ segment: String) -> Bool {
        guard segment.allSatisfy(\.isLetter), segment.count <= 16 else { return false }
        let lower = segment.lowercased()
        let validCase = segment == lower || segment == segment.uppercased() || segment == lower.capitalized
        guard validCase else { return false }
        if segment.count <= 3 { return true }
        var consonantRun = 0
        var longestRun = 0
        for character in lower {
            consonantRun = vowels.contains(character) ? 0 : consonantRun + 1
            longestRun = max(longestRun, consonantRun)
        }
        return lower.contains(where: vowels.contains) && longestRun <= 5
    }
}
