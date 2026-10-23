// SPDX-License-Identifier: MIT
import Foundation

public protocol QueryInterpreting: Sendable {
    func interpret(_ question: String) async throws -> AskPestoQuery
}

public struct RuleBasedQueryInterpreter: Sendable {
    public init() {}

    private static let fillers: Set<String> = [
        "the", "a", "an", "my", "me", "i", "that", "this", "those", "these", "from", "of", "in", "on", "at", "to",
        "copied", "copy", "find", "show", "get", "search", "for", "about", "with", "and", "or", "was", "were", "had",
        "have", "just", "some", "any", "all", "recent", "recently", "ago", "last", "past", "earlier"
    ]

    private static let types: [String: ClipboardType] = [
        "text": .text, "texts": .text, "note": .text, "notes": .text, "plain": .text,
        "link": .url, "links": .url, "url": .url, "urls": .url, "website": .url, "websites": .url,
        "image": .image, "images": .image, "picture": .image, "pictures": .image, "screenshot": .image,
        "screenshots": .image, "photo": .image, "photos": .image,
        "code": .code, "snippet": .code, "snippets": .code,
        "file": .file, "files": .file, "document": .file, "documents": .file,
        "color": .color, "colors": .color, "colour": .color, "colours": .color
    ]

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "fourteen": 14, "thirty": 30,
        "couple": 2, "few": 3, "several": 5
    ]

    public func interpret(_ question: String) -> AskPestoQuery {
        let words = question.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var range = AskDateRange.all
        var types: [ClipboardType] = []
        var keywords: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let next = index + 1 < words.count
                ? words[index + 1].lowercased().trimmingCharacters(in: .punctuationCharacters) : ""
            index += 1
            if let (matchedRange, extraStep) = Self.matchDateRange(lower: lower, next: next) {
                range = widen(range, to: matchedRange)
                index += extraStep
            } else if let slashTypes = Self.parseSlashTypes(lower) {
                for type in slashTypes where !types.contains(type) {
                    types.append(type)
                }
            } else if let type = Self.types[lower] {
                if !types.contains(type) { types.append(type) }
            } else if !Self.fillers.contains(lower), !lower.isEmpty {
                keywords.append(word.trimmingCharacters(in: .punctuationCharacters))
            }
        }
        return AskPestoQuery(keywords: keywords.joined(separator: " "), types: types, range: range)
    }

    private static func matchDateRange(lower: String, next: String) -> (AskDateRange, Int)? {
        if lower == "today" || lower == "tonight" {
            return (.today, 0)
        }
        if lower == "this", ["morning", "afternoon", "evening"].contains(next) {
            return (.today, 1)
        }
        if lower == "yesterday" {
            return (.yesterday, 0)
        }
        if lower == "last", next == "night" {
            return (.yesterday, 1)
        }
        if ["this", "last", "past"].contains(lower), ["week", "weeks"].contains(next) {
            return (.week, 1)
        }
        if ["this", "last", "past"].contains(lower), ["month", "months"].contains(next) {
            return (.month, 1)
        }
        if let dayCount = parseDayCount(lower), ["day", "days"].contains(next) {
            let mapped: AskDateRange = dayCount == 1 ? .yesterday : (dayCount <= 7 ? .week : .month)
            return (mapped, 1)
        }
        return nil
    }

    private static func parseDayCount(_ token: String) -> Int? {
        if let n = Int(token), n > 0 { return n }
        return numberWords[token]
    }

    private static func parseSlashTypes(_ token: String) -> [ClipboardType]? {
        guard token.contains("/") else { return nil }
        let parts = token.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        var matched: [ClipboardType] = []
        for part in parts {
            guard let type = types[part] else { return nil }
            matched.append(type)
        }
        return matched
    }

    private func widen(_ current: AskDateRange, to new: AskDateRange) -> AskDateRange {
        let order: [AskDateRange] = [.all, .today, .yesterday, .week, .month]
        return (order.firstIndex(of: new) ?? 0) > (order.firstIndex(of: current) ?? 0) ? new : current
    }
}

public struct FallbackQueryInterpreter: Sendable {
    let primary: any QueryInterpreting
    let fallback: RuleBasedQueryInterpreter

    public init(primary: any QueryInterpreting, fallback: RuleBasedQueryInterpreter = RuleBasedQueryInterpreter()) {
        self.primary = primary
        self.fallback = fallback
    }

    public func interpret(_ question: String) async -> AskPestoQuery {
        let deterministic = fallback.interpret(question)
        guard var query = try? await primary.interpret(question) else { return deterministic }
        if deterministic.range != .all {
            query.range = deterministic.range
        }
        for type in deterministic.types where !query.types.contains(type) {
            query.types.append(type)
        }
        let cleaned = fallback.interpret(query.keywords).keywords
        query.keywords = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return query
    }
}
