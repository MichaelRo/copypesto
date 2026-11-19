// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import UniformTypeIdentifiers

/// Reads what another app shared into one inbox item, within the extension's memory limit: a picture is read from its
/// file only when it is small enough to keep as it is, and otherwise scaled down from the file by ImageIO (a GIF too
/// large to keep whole is refused, not reduced to its first frame).
@MainActor
enum ShareReader {
    struct Unreadable: Error {}

    static func item(from providers: [NSItemProvider]) async throws -> InboxItem? {
        for provider in providers {
            let types = provider.registeredTypeIdentifiers
            guard let choice = SharedContentChoice.choose(typeIdentifiers: types) else { continue }
            if let item = try await item(choice, from: provider) { return item }
        }
        return nil
    }

    private static func item(_ choice: SharedContentChoice, from provider: NSItemProvider) async throws -> InboxItem? {
        switch choice {
        case let .picture(type):
            return try await picture(of: type, from: provider, keepsOriginal: true)
        case let .pictureToConvert(type):
            return try await picture(of: type, from: provider, keepsOriginal: false)
        case .link:
            return try await InboxItem.link(url(from: provider))
        case .text:
            let registered = provider.registeredTypeIdentifiers
            let utf8 = UTType.utf8PlainText.identifier
            let type = registered.contains(utf8)
                ? utf8 : registered.first { UTType($0)?.conforms(to: .plainText) == true } ?? utf8
            let raw = try await data(of: type, from: provider)
            guard raw.count <= InboxPolicy.maxTextBytes else { throw InboxError.tooLarge }
            let encoding: String.Encoding = type == UTType.utf16PlainText.identifier ? .utf16 : .utf8
            guard let text = String(data: raw, encoding: encoding) else { throw Unreadable() }
            return InboxItem.text(text)
        }
    }

    private static func picture(
        of type: String, from provider: NSItemProvider, keepsOriginal: Bool
    ) async throws
    -> InboxItem? {
        let payload: (Data, String) = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? Unreadable())
                    return
                }
                continuation.resume(with: Result { try readPicture(at: url, type: type, keepsOriginal: keepsOriginal) })
            }
        }
        let sourceURL = (payload.1 == UTType.gif.identifier || !LinkPreviewPolicy.isEnabled())
            ? nil
            : await animatedAddress(from: provider)
        return InboxItem(typeIdentifier: payload.1, payload: payload.0, createdAt: .now, sourceImageURL: sourceURL)
    }

    nonisolated static let maxHTMLBytes = 1_000_000

    nonisolated static func animatedAddress(inHTML data: Data?) -> URL? {
        guard let data, data.count <= maxHTMLBytes, let html = String(data: data, encoding: .utf8) else { return nil }
        return ImageSourceAddress.animatedPictureURL(inHTML: html)
    }

    private static func animatedAddress(from provider: NSItemProvider) async -> URL? {
        let html = UTType.html.identifier
        guard provider.hasItemConformingToTypeIdentifier(html) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: html) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
                guard size <= maxHTMLBytes, let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: animatedAddress(inHTML: data))
            }
        }
    }

    /// Runs inside the provider's callback, while the file it lent still exists.
    private nonisolated static func readPicture(
        at url: URL, type: String, keepsOriginal: Bool
    ) throws
    -> (Data, String) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        if keepsOriginal {
            switch InboxPolicy.handling(ofStoredPictureType: type, byteCount: size) {
            case .keep: return try (Data(contentsOf: url), type)
            case .refuse: throw InboxError.tooLarge
            case .scaleDown: break
            }
        }
        let png = ImageDownsampler.thumbnailPNG(contentsOf: url, maxPixel: InboxPolicy.maxConvertedPixel)
        guard let png else { throw Unreadable() }
        guard png.count <= InboxPolicy.maxPictureBytes else { throw InboxError.tooLarge }
        return (png, UTType.png.identifier)
    }

    /// Safari's `public.url` data is an archived URL, not its text, so the provider is asked for the object.
    private static func url(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, error in
                if let url = (object as? NSURL)?.absoluteURL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? Unreadable())
                }
            }
        }
    }

    private static func data(of typeIdentifier: String, from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? Unreadable())
                }
            }
        }
    }
}
