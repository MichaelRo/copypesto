// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The clips the size preview in Pesto's settings shows: made up, so the page shows no one's own clips in a
/// screenshot, and there even before the history has any.
enum KeyboardPreviewSamples {
    static func entries(now: Date = .now) -> [QuickInsertEntry] {
        [
            entry(.pinned, .text, String(localized: "12 Basil Lane, Springfield"), minutes: 900, color: "#F5C400"),
            entry(.recent, .url, "https://copypesto.net/guide/keyboard", minutes: 2, color: "#1A8CFF"),
            entry(
                .snippets, .text, String(localized: "Thanks, see you at {{time}}"), minutes: 4000, snippet: true
            ),
            entry(.recent, .color, "#2E7D4F", minutes: 30),
            entry(
                .recent, .text, String(localized: "Pick up basil, pine nuts and parmesan on the way home"),
                minutes: 12, color: "#34C759"
            ),
            entry(.recent, .code, "let total = prices.reduce(0, +)", minutes: 60, color: "#147EFB"),
            entry(.recent, .text, String(localized: "Meeting moved to Thursday at 3"), minutes: 180),
            entry(.recent, .text, String(localized: "Order ships tomorrow by noon"), minutes: 240, color: "#FF9500")
        ].map { $0(now) }
    }

    private static func entry(
        _ section: QuickInsertEntry.Section, _ kind: ClipboardType, _ text: String, minutes: Double,
        color: String? = nil, snippet: Bool = false
    )
    -> (Date) -> QuickInsertEntry {
        { now in
            QuickInsertEntry(
                id: UUID(), section: section, kind: kind, title: text, text: text, expandsOnInsert: snippet,
                date: now.addingTimeInterval(-minutes * 60), sourceIsThisDevice: color == nil,
                sourceColorHex: color
            )
        }
    }
}
