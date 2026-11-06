// SPDX-License-Identifier: MIT
import Foundation

/// The JSON and Markdown entries of Paste As and Copy As (ADR 0033): which a clip qualifies for, and what they write.
/// The one place that decides, so a card's menu and the paste read the same rule.
///
/// A clip that is hidden, filtered, still being screened or too big is never read: the answer is "none" before any
/// decryption, so a secret is not transformed around its mask and a 5 MB clip costs a paste nothing. A clip whose
/// blob will not open is "none" too, never its preview (`AppState.writeItem` has the same rule). A transform that
/// cannot be made hides its entry; nothing is reported to the person. Main actor only: RTF is read with AppKit.
@MainActor
public enum StructuredPaste {
    /// The size of the clip's text, as stored with the clip: the same limit as Quick Look and the hover card.
    public static let maxClipBytes = DetailPopoverContent.maxReadableBytes
    /// The sealed formatted flavours (HTML, RTF and RTFD, as base64 in a JSON envelope) of one clip: past this the menu
    /// does not decrypt them.
    static let maxRichCiphertextBytes = 2_000_000

    public static func offered(for item: ClipboardItem) -> [TextTransform] {
        guard isEligible(item) else { return [] }
        var entries: [TextTransform] = []
        if let text = plainText(of: item), qualifiesForJSON(text) { entries.append(.json) }
        if markdown(for: item) != nil { entries.append(.markdown) }
        return entries
    }

    /// The text to write for `transform`, nil when the clip does not qualify any more or the transform is not one of
    /// these two.
    public static func result(of transform: TextTransform, for item: ClipboardItem) -> String? {
        guard isEligible(item) else { return nil }
        switch transform {
        case .json:
            return plainText(of: item).flatMap(jsonText(from:))
        case .markdown:
            return markdown(for: item)
        default:
            return nil
        }
    }

    private static func isEligible(_ item: ClipboardItem) -> Bool {
        (item.type == .text || item.type == .code)
            && item.sensitivityRaw == nil && !item.isNSFW && !item.analysisPending
            && item.byteSize <= maxClipBytes
    }

    private static func plainText(of item: ClipboardItem) -> String? {
        item.blob?.decryptedText()
    }

    /// Reads only the first rows of a table: enough to say it is one when the menu opens.
    private static func qualifiesForJSON(_ text: String) -> Bool {
        JSONDocument.formatted(text) != nil || CSVTable.parse(text, maxRows: 50) != nil
    }

    private static func jsonText(from text: String) -> String? {
        JSONDocument.formatted(text) ?? CSVTable.parse(text)?.jsonText()
    }

    private static func markdown(for item: ClipboardItem) -> String? {
        if let blob = item.blob, let sealed = blob.encryptedRichData, sealed.count <= maxRichCiphertextBytes,
           let payload = blob.decryptedRichPayload()
        {
            if let html = payload.html, let text = HTMLMarkdown.convert(html) { return text }
            if let rtfd = payload.rtfd, let text = RTFMarkdown.convert(rtfd, isRTFD: true) { return text }
            if let rtf = payload.rtf, let text = RTFMarkdown.convert(rtf) { return text }
            return nil
        }
        guard item.type == .code, item.detectedLanguage == "html", let text = plainText(of: item),
              text.utf8.count <= HTMLMarkdown.maxInputBytes else { return nil }
        return HTMLMarkdown.convert(Data(text.utf8))
    }
}
