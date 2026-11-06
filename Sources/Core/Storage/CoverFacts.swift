// SPDX-License-Identifier: MIT
import Foundation

/// The only facts a covered card (screen share, Hide Clip Contents) draws or speaks: its ⌘ number, the kind of clip as
/// one plain word, and its age. Everything else identifies the content or where it came from (the app, the secret's
/// category, a length or size, a title, a file name, a link's domain, a color, a picture) and never gets here, because
/// the cover's view and its VoiceOver text are built from this value alone (ADR 0028, which keeps ADR 0003).
public struct CoverFacts: Equatable, Sendable {
    public let number: Int?
    public let kind: String
    public let age: String
    public let spokenAge: String

    public init(item: ClipboardItem, number: Int?, inCollection: Bool, now: Date = .now) {
        self.number = number
        // A sensitive clip reads as Text whatever it holds, so the kind never says "card" or "key" by elimination.
        kind = item.sensitivity == nil ? item.type.presentation.label : ClipboardType.text.presentation.label
        let interval = CardAge.interval(for: item, inCollection: inCollection, now: now)
        age = CardAge.text(interval: interval)
        spokenAge = CardAge.spoken(interval: interval)
    }

    public var numberLabel: String? {
        number.map { "⌘\($0)" }
    }

    public var spokenLabel: String {
        "\(kind.lowercased()), hidden"
    }

    /// A clip blurred by the content filter says why it is hidden; the words "sensitive content, hidden" are what the
    /// UI tests and automation find such a card by.
    public var contentFilteredSpokenLabel: String {
        "\(kind.lowercased()), sensitive content, hidden"
    }

    public var spokenValue: String {
        number.map { "command \($0), \(spokenAge)" } ?? spokenAge
    }

    public var everyString: [String] {
        [numberLabel, kind, age, spokenLabel, contentFilteredSpokenLabel, spokenValue].compactMap(\.self)
    }
}
