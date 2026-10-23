// SPDX-License-Identifier: MIT
import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

public struct OnDeviceQueryInterpreter: QueryInterpreting {
    public init() {}

    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
            AIAvailability.current.isAvailable
        #else
            return false
        #endif
    }

    public func interpret(_ question: String) async throws -> AskPestoQuery {
        #if canImport(FoundationModels)
            guard #available(macOS 26, *) else { throw AppleIntelligenceClient.ClientError.unavailable }
            let session = LanguageModelSession(
                model: .default,
                instructions: """
                You turn a question about someone's clipboard history into search filters. Put only the words that \
                should appear in the clip into keywords, and leave out filler and any type or date words.
                """
            )
            let response = try await session.respond(to: question, generating: ParsedQuestion.self)
            return response.content.query
        #else
            throw AppleIntelligenceClient.ClientError.unavailable
        #endif
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    private struct ParsedQuestion {
        @Guide(description: "Words the clip itself should contain. Empty if the question names none.")
        var keywords: String
        @Guide(
            description: "Kinds of clip asked for: any of text, url, image, file, color, code. Empty if unspecified."
        ) var kinds: [String]
        @Guide(
            description: "How far back to look: all, today, yesterday, week (last 7 days) or month (last 30 days)."
        ) var range: String

        var query: AskPestoQuery {
            let lower = range.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedRange: AskDateRange = if let direct = AskDateRange(rawValue: lower) {
                direct
            } else if lower.contains("yesterday") {
                .yesterday
            } else if lower.contains("today") {
                .today
            } else if lower.contains("week") || lower.contains("7") {
                .week
            } else if lower.contains("month") || lower.contains("30") {
                .month
            } else {
                .all
            }
            return AskPestoQuery(
                keywords: keywords,
                types: kinds.compactMap { ClipboardType(rawValue: $0.lowercased()) },
                range: resolvedRange
            )
        }
    }
#endif
