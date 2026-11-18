// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import UniformTypeIdentifiers

/// What the person handed Pesto (the Paste button, a new note, a drop), as the capture `StorageService.ingest` takes.
/// A link is stored as its text, so the classifier files it as a link the way a copied address is on a Mac.
enum ClipCapture {
    static let textType = UTType.utf8PlainText.identifier

    /// Picture formats ingest stores as they are; anything else is converted to PNG first.
    static let storedPictureTypes = InboxPolicy.storedPictureTypes

    static func text(_ text: String, at date: Date = .now) -> PasteboardCapture? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let payload = Data(text.utf8)
        return PasteboardCapture(
            typeIdentifier: textType, payload: payload, payloadString: text, timestamp: date,
            contentHash: hash(of: payload)
        )
    }

    static func link(_ url: URL, at date: Date = .now) -> PasteboardCapture? {
        guard url.scheme != nil, !url.isFileURL else { return nil }
        return text(url.absoluteString, at: date)
    }

    static func picture(_ data: Data, typeIdentifier: String, at date: Date = .now) -> PasteboardCapture? {
        guard !data.isEmpty, storedPictureTypes.contains(typeIdentifier) else { return nil }
        return PasteboardCapture(
            typeIdentifier: typeIdentifier, payload: data, timestamp: date, contentHash: hash(of: data)
        )
    }

    /// The plain SHA-256 the watcher hands over; ingest keys it before it is stored (`ContentHash`).
    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
