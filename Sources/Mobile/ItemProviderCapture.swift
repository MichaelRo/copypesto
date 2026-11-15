// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import UIKit
import UniformTypeIdentifiers

/// Reads what the Paste button or a drop delivered, choosing as the share extension does (`SharedContentChoice`).
@MainActor
enum ItemProviderCapture {
    typealias Choice = SharedContentChoice

    nonisolated static let acceptedTypes: [UTType] = [.image, .url, .plainText]

    nonisolated static func choose(typeIdentifiers: [String]) -> Choice? {
        SharedContentChoice.choose(typeIdentifiers: typeIdentifiers)
    }

    struct Unreadable: Error {}

    static func capture(from providers: [NSItemProvider]) async throws -> PasteboardCapture? {
        for provider in providers {
            guard let choice = choose(typeIdentifiers: provider.registeredTypeIdentifiers) else { continue }
            if let capture = try await capture(choice, from: provider) { return capture }
        }
        return nil
    }

    private static func capture(_ choice: Choice, from provider: NSItemProvider) async throws -> PasteboardCapture? {
        switch choice {
        case let .picture(type):
            return try await ClipCapture.picture(data(of: type, from: provider), typeIdentifier: type)
        case let .pictureToConvert(type):
            let raw = try await data(of: type, from: provider)
            guard let png = UIImage(data: raw)?.pngData() else { throw Unreadable() }
            return ClipCapture.picture(png, typeIdentifier: UTType.png.identifier)
        case .link:
            let raw = try await data(of: UTType.url.identifier, from: provider)
            guard let url = URL(dataRepresentation: raw, relativeTo: nil) else { throw Unreadable() }
            return ClipCapture.link(url)
        case .text:
            let registered = provider.registeredTypeIdentifiers
            let utf8 = UTType.utf8PlainText.identifier
            let type = registered.contains(utf8)
                ? utf8 : registered.first { UTType($0)?.conforms(to: .plainText) == true } ?? utf8
            let raw = try await data(of: type, from: provider)
            let encoding: String.Encoding = type == UTType.utf16PlainText.identifier ? .utf16 : .utf8
            guard let text = String(data: raw, encoding: encoding) else { throw Unreadable() }
            return ClipCapture.text(text)
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
