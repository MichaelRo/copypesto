// SPDX-License-Identifier: MIT
import AppKit

/// The plain text of a copied RTF, RTFD or HTML document. AppKit's rich-text import is not thread-safe (it aborted a
/// test process off the main thread), so it runs on the main actor, never inside the watcher's actor. HTML does not go
/// through AppKit at all: its importer is WebKit-based and can request the images and styles the markup names, and
/// the markup is whatever any local program put on the board. RTF and RTFD import loads nothing from the network.
@MainActor
enum RichTextFlattener {
    static func plainText(from data: Data, type: NSPasteboard.PasteboardType) -> String? {
        if type == .html { return HTMLText.plainText(from: data) }
        let documentType: NSAttributedString.DocumentType = type == .rtfd ? .rtfd : .rtf
        return try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ).string
    }
}
