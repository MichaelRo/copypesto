// SPDX-License-Identifier: MIT
import Foundation

/// Turns clips that differ in a few words into one snippet with a fill-in where they differ (ADR 0017). It works on
/// text already in memory, keeps none of it, and proposes nothing it is not sure of: at most five fields and at least
/// half of the words shared.
public enum TemplateInferrer {
    public struct Proposal: Equatable, Sendable {
        public let template: String
        public let fields: [SnippetField]
    }

    static let maxFields = 5
    static let minimumSharedShare = 0.5

    public static func propose(from texts: [String]) -> Proposal? {
        guard texts.count >= 2 else { return nil }
        let base = tokens(of: texts[0])
        guard base.contains(where: \.isWord) else { return nil }
        var differs = [Bool](repeating: false, count: base.count)
        var samples = [[String]](repeating: [], count: base.count)
        for text in texts.dropFirst() {
            let other = tokens(of: text)
            let matched = alignment(base, other)
            for index in base.indices where base[index].isWord {
                if let partner = matched[index] {
                    if base[index].text != other[partner].text { differs[index] = true }
                } else {
                    differs[index] = true
                }
                samples[index].append(matched[index].map { other[$0].text } ?? "")
            }
        }
        return render(base, differs: differs, samples: samples)
    }

    /// The text with a literal ISO date read as `{{isodate}}`, or nil when it holds none.
    public static func replacingDates(in text: String) -> String? {
        let replaced = text.replacingOccurrences(
            of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: "{{isodate}}", options: .regularExpression
        )
        return replaced == text ? nil : replaced
    }

    private struct Token {
        let text: String
        let isWord: Bool
    }

    private static func tokens(of text: String) -> [Token] {
        var result: [Token] = []
        var current = ""
        var currentIsWord = false
        for character in text {
            let isWord = character.isLetter || character.isNumber
            if !current.isEmpty, isWord != currentIsWord {
                result.append(Token(text: current, isWord: currentIsWord))
                current = ""
            }
            current.append(character)
            currentIsWord = isWord
        }
        if !current.isEmpty { result.append(Token(text: current, isWord: currentIsWord)) }
        return result
    }

    /// For each base token, the index of the token in `other` it lines up with (longest common subsequence of words).
    private static func alignment(_ base: [Token], _ other: [Token]) -> [Int?] {
        let a = base.indices.filter { base[$0].isWord }
        let b = other.indices.filter { other[$0].isWord }
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = base[a[i]].text == other[b[j]].text
                    ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result = [Int?](repeating: nil, count: base.count)
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if base[a[i]].text == other[b[j]].text {
                result[a[i]] = b[j]
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        for index in a where result[index] == nil {
            result[index] = nil
        }
        return result
    }

    private static func render(_ base: [Token], differs: [Bool], samples: [[String]]) -> Proposal? {
        let words = base.indices.filter { base[$0].isWord }
        let changing = words.filter { differs[$0] }
        guard !changing.isEmpty, Double(words.count - changing.count) / Double(words.count) >= minimumSharedShare else {
            return nil
        }
        var template = ""
        var fields: [SnippetField] = []
        var counts: [String: Int] = [:]
        var index = 0
        while index < base.count {
            guard differs[index], base[index].isWord else {
                template += base[index].text
                index += 1
                continue
            }
            var run = [index]
            var next = index + 1
            while next + 1 < base.count, !base[next].isWord, base[next].text == " ", differs[next + 1],
                  base[next + 1].isWord
            {
                run.append(next + 1)
                next += 2
            }
            let values = run.flatMap { samples[$0] } + run.map { base[$0].text }
            var label = labelFor(values)
            counts[label, default: 0] += 1
            if counts[label] ?? 1 > 1 { label += " \(counts[label] ?? 2)" }
            let field = SnippetField(label: label, kind: .text(multiline: false), defaultValue: nil)
            fields.append(field)
            template += field.token
            index = (run.last ?? index) + 1
        }
        guard fields.count <= maxFields else { return nil }
        return Proposal(template: template, fields: fields)
    }

    private static func labelFor(_ values: [String]) -> String {
        let nonEmpty = values.filter { !$0.isEmpty }
        if !nonEmpty.isEmpty, nonEmpty.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return "Number" }
        if !nonEmpty.isEmpty,
           nonEmpty.allSatisfy({ $0.first?.isUppercase == true && $0.dropFirst().allSatisfy(\.isLetter) })
        {
            return "Name"
        }
        return "Field"
    }
}
