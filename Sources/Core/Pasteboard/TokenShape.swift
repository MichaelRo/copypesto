// SPDX-License-Identifier: MIT
import Foundation

enum TokenShape {
    static func looksLikeIdentifier(_ token: String) -> Bool {
        if token.allSatisfy(\.isNumber) { return true }
        if isHexDigest(token) { return true }
        if UUID(uuidString: token) != nil { return true }
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
        let hasLowercaseWord = segments.contains { $0.count >= 2 && $0.allSatisfy(\.isLowercase) }
        let hasLongAllCaps = segments.contains { $0.count >= 6 && $0.allSatisfy(\.isUppercase) }
        if hasLowercaseWord, hasLongAllCaps { return false }

        let unreadable = segments.filter { !isReadableSegment($0) }
        if unreadable.isEmpty { return true }
        // At most one short lowercase/digit tag (like a host suffix); longer or split random chunks are keys.
        return segments.count >= 3
            && unreadable.count == 1
            && unreadable[0].count <= 5
            && unreadable[0].allSatisfy { $0.isLowercase || $0.isNumber }
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
        var vowelCount = 0
        for character in lower {
            if vowels.contains(character) {
                vowelCount += 1
                consonantRun = 0
            } else {
                consonantRun += 1
                longestRun = max(longestRun, consonantRun)
            }
        }
        if segment.count >= 10 {
            return vowelCount * 4 >= segment.count && longestRun <= 3
        }
        return vowelCount > 0 && longestRun <= 5
    }
}
