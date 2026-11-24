// SPDX-License-Identifier: MIT
import Foundation

public enum ClipText {
    /// The clip's whole text: its decrypted blob, or its preview when it has none (an old snippet).
    public static func full(of item: ClipboardItem) -> String {
        if let blob = item.blob, let text = blob.decryptedText() { return text }
        return item.displayPreviewText
    }
}

public enum ClipJoin {
    public struct Joined: Sendable, Equatable {
        public let text: String
        public let isProtected: Bool
        public let leftOut: Int

        public init(text: String, isProtected: Bool, leftOut: Int) {
            self.text = text
            self.isProtected = isProtected
            self.leftOut = leftOut
        }
    }

    /// Several clips joined by a blank line, protected (kept off Universal Clipboard) when any of them is a secret.
    /// Nil unless there are at least two. Paste All / Copy All uses this text; no clip is created. Stops at
    /// `maxBytes`: a clip that would pass it, and every one after it, is left out and counted without being read
    /// (the size is stored with the clip), so selecting many large clips does not decrypt them all on the main thread.
    public static func join(
        _ items: [ClipboardItem], maxBytes: Int = ClipSizePolicy.maxTextBytes
    )
    -> Joined? {
        guard items.count > 1 else { return nil }
        var kept: [ClipboardItem] = []
        var total = 0
        for item in items {
            let separator = kept.isEmpty ? 0 : 2
            if !kept.isEmpty, total + separator + item.byteSize > maxBytes { break }
            total += separator + item.byteSize
            kept.append(item)
        }
        return Joined(
            text: kept.map(ClipText.full(of:)).joined(separator: "\n\n"),
            isProtected: kept.contains { $0.sensitivityRaw != nil || $0.analysisPending },
            leftOut: items.count - kept.count
        )
    }
}
