// SPDX-License-Identifier: MIT
import Foundation

/// Copy Recognized Text on a picture (ADR 0034): how much of the text Pesto keeps, and which pictures offer it. The one
/// place that decides, before anything is decrypted, so a covered or hidden picture cannot be asked for its text.
public enum RecognizedText {
    /// A picture's text is kept up to this many bytes of UTF-8. A screenshot of a page is a few thousand.
    public static let maxBytes = 100_000

    /// The text as it is kept: cut on a character boundary at `maxBytes`.
    public static func capped(_ text: String) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: maxBytes)
        while end > text.startIndex, text[end...].utf8.first.map({ $0 & 0xC0 == 0x80 }) == true {
            end = text.utf8.index(before: end)
        }
        return String(text[..<end])
    }

    /// The card's preview holds the first `CardPreviewText.previewLength` characters. A text at least that long may
    /// have been cut, so it gets a file; a shorter one is its own preview.
    public static func needsFile(_ text: String) -> Bool {
        text.count >= CardPreviewText.previewLength
    }

    /// Whether the picture may hand out its text at all: no secret (even one that is shown), not filtered, not still
    /// being read.
    @MainActor
    static func isEligible(_ item: ClipboardItem) -> Bool {
        item.type == .image && item.sensitivityRaw == nil && !item.isNSFW && !item.analysisPending
    }

    /// Asked when the menu opens, never while a card draws. A file is one `fileExists`; an old picture without one is
    /// offered only when its preview is short enough to be the whole text.
    @MainActor
    public static func isOffered(for item: ClipboardItem, store: RecognizedTextStore = RecognizedTextStore()) -> Bool {
        guard isEligible(item) else { return false }
        return store.exists(for: item.id) || wholePreview(of: item) != nil
    }

    /// A necessary condition that costs nothing a card has not already paid (its preview is cached): the picture is
    /// eligible and read some text. VoiceOver lists the action on this; the action itself asks `isOffered`.
    @MainActor
    public static func hasText(_ item: ClipboardItem) -> Bool {
        isEligible(item) && !item.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The text to write, nil when the picture does not offer it or its file will not open. A file that will not open
    /// is not replaced by the preview.
    @MainActor
    public static func text(of item: ClipboardItem, store: RecognizedTextStore = RecognizedTextStore()) -> String? {
        guard isEligible(item) else { return nil }
        if store.exists(for: item.id) { return store.load(for: item.id) }
        return wholePreview(of: item)
    }

    @MainActor
    private static func wholePreview(of item: ClipboardItem) -> String? {
        let preview = item.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !preview.isEmpty && preview.count < CardPreviewText.previewLength ? preview : nil
    }
}
