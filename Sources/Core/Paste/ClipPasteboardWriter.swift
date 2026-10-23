// SPDX-License-Identifier: MIT
import AppKit

/// Fills a pasteboard with one clip: its files, or its stored flavour with the rich flavours and the plain string
/// beside it, or just its preview text for a clip that never had data. The caller opens the write, so the clip's
/// protection and the own-write gate are its business (`AppState.writeItem`).
public enum ClipPasteboardWriter {
    /// What the paste coordinator should type for a text clip.
    @MainActor
    public static func fill(
        _ pasteboard: NSPasteboard,
        with item: ClipboardItem,
        fileURLs: [URL],
        data: Data?,
        richPayload: RichTextPayload?
    )
    -> PasteCoordinator.PayloadKind {
        if !fileURLs.isEmpty {
            pasteboard.writeObjects(fileURLs as [NSURL])
            return .nonText
        }
        let isText = item.type == .text || item.type == .code
        if let blob = item.blob, let data {
            richPayload?.write(to: pasteboard)
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(blob.mimeType))
            let plainFlavour = PasteFlavors.plainText(forStoredType: blob.mimeType, data: data)
            if let plainFlavour { pasteboard.setString(plainFlavour, forType: .string) }
            guard isText else { return .nonText }
            let text = plainFlavour ?? String(data: data, encoding: .utf8) ?? item.displayPreviewText
            let hasRichFlavor = richPayload != nil
                || blob.mimeType == NSPasteboard.PasteboardType.rtf.rawValue
                || blob.mimeType == NSPasteboard.PasteboardType.rtfd.rawValue
                || blob.mimeType == NSPasteboard.PasteboardType.html.rawValue
            return hasRichFlavor ? .richText(text) : .text(text)
        }
        let fallback = item.displayPreviewText
        pasteboard.setString(fallback, forType: .string)
        return isText ? .text(fallback) : .nonText
    }
}
