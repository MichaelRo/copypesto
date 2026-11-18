// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import UniformTypeIdentifiers

/// A clip's real content, opened from its sealed blob, in the form the clipboard, Share and a drag hand out.
enum ClipContent: Equatable {
    case text(String)
    case link(URL, text: String)
    case picture(Data, typeIdentifier: String)

    static func make(type: ClipboardType, payload: Data, mimeType: String?) -> ClipContent? {
        if type == .image {
            let identifier = mimeType.flatMap { UTType($0) }?.identifier ?? UTType.png.identifier
            return payload.isEmpty ? nil : .picture(payload, typeIdentifier: identifier)
        }
        guard let text = String(data: payload, encoding: .utf8), !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .url, let url = URL(string: trimmed), url.scheme != nil {
            return .link(url, text: text)
        }
        return .text(text)
    }

    @MainActor
    static func of(_ item: ClipboardItem) -> ClipContent? {
        guard let payload = item.blob?.decryptedData() else { return nil }
        return make(type: item.type, payload: payload, mimeType: item.mimeType)
    }

    /// The clip opened on a context of its own, off the main actor, so a large clip does not hold up the sheet.
    @concurrent
    static func load(itemID: UUID, container: ModelContainer) async -> ClipContent? {
        guard let item = clip(itemID, in: ModelContext(container)),
              let payload = item.blob?.decryptedData() else { return nil }
        return make(type: item.type, payload: payload, mimeType: item.mimeType)
    }

    /// The clip's decrypted bytes, for the text a shown secret reveals.
    @concurrent
    static func payload(itemID: UUID, container: ModelContainer) async -> Data? {
        clip(itemID, in: ModelContext(container))?.blob?.decryptedData()
    }

    private nonisolated static func clip(_ id: UUID, in context: ModelContext) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    var plainText: String? {
        switch self {
        case let .text(text), let .link(_, text): text
        case .picture: nil
        }
    }
}
