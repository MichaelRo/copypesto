// SPDX-License-Identifier: MIT
import PestoCore
import UIKit

/// Ask Pesto on iOS (ADR 0058): the sentence in the search field becomes words, kinds and a date range, as the Mac's
/// Ask button does it (ADR 0005). Apple's on-device model reads it when it can run; otherwise, or when it fails,
/// `RuleBasedQueryInterpreter` does, so the chip works with Apple Intelligence off.
extension MobileAppState {
    private struct NoModel: QueryInterpreting {
        func interpret(_: String) async throws -> AskPestoQuery {
            throw AppleIntelligenceClient.ClientError.unavailable
        }
    }

    func askInterpreter() -> FallbackQueryInterpreter {
        aiAvailability().isAvailable && OnDeviceQueryInterpreter.isAvailable
            ? FallbackQueryInterpreter(primary: OnDeviceQueryInterpreter())
            : FallbackQueryInterpreter(primary: NoModel())
    }

    func askPesto(_ sentence: String) async -> AskPestoQuery {
        let query = await askInterpreter().interpret(sentence)
        guard !Task.isCancelled, !isHistoryLockedNow() else { return query }
        UIAccessibility.post(notification: .announcement, argument: Self.askAnnouncement(for: query))
        return query
    }

    static func askAnnouncement(for query: AskPestoQuery) -> String {
        query.hasFilters || !query.keywords.isEmpty
            ? String(localized: "Filters applied: \(query.summary)")
            : String(localized: "No filters found in that. Showing everything.")
    }
}
