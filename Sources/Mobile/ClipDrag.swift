// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// The id rides along visible to Pesto alone (`.ownProcess`), so a drop on a sidebar collection files the clip and a
/// drop back on the grid is not taken for a new copy.
@MainActor
enum ClipDrag {
    static let clipIDType = UTType(exportedAs: "net.copypesto.pesto.clip-id")

    static func provider(for content: ClipContent, clipID: UUID) -> NSItemProvider {
        let provider: NSItemProvider
        switch content {
        case let .text(text):
            provider = NSItemProvider(object: text as NSString)
        case let .link(url, _):
            provider = NSItemProvider(object: url as NSURL)
        case let .picture(data, typeIdentifier):
            provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        let idData = Data(clipID.uuidString.utf8)
        let identifier = clipIDType.identifier
        provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
            completion(idData, nil)
            return nil
        }
        return provider
    }

    static func isOwnDrag(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(clipIDType.identifier) }
    }

    static func clipID(in providers: [NSItemProvider]) async -> UUID? {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(clipIDType.identifier)
        }) else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: clipIDType.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        return data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:))
    }
}
