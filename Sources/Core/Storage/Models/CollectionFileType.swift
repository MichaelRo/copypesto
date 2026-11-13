// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// The `.pesto` file a collection is shared as (ADR 0045): one JSON file, declared in Info.plist as an exported type.
public enum CollectionFileType {
    public static let fileExtension = "pesto"
    public static let identifier = "\(AppIdentity.bundleID).collection"
    /// Files an import accepts: the new type and the plain `.json` that earlier versions wrote.
    public static let importableExtensions: Set<String> = [fileExtension, "json"]

    public static var utType: UTType {
        UTType(identifier) ?? UTType(exportedAs: identifier, conformingTo: .json)
    }

    public static var importableTypes: [UTType] {
        [utType, .json]
    }

    public enum OpenVerdict: Equatable, Sendable {
        case accept
        case notACollectionFile
        case tooLarge
    }

    /// Whether a file handed to the app (Finder, AirDrop, a double click) is worth showing the person. Decided from the
    /// name and the size alone; nothing is read.
    public static func openVerdict(for url: URL) -> OpenVerdict {
        guard url.isFileURL, importableExtensions.contains(url.pathExtension.lowercased()) else {
            return .notACollectionFile
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { return .notACollectionFile }
        let size = attributes?[.size] as? Int ?? 0
        return size > HistoryExporter.maxImportBytes ? .tooLarge : .accept
    }

    public struct Summary: Equatable, Sendable {
        public let name: String
        public let clipCount: Int
    }

    /// The collection's name and how many clips a file holds, for the question asked before an import. Throws for a
    /// file that is not a collection file or is from a newer version.
    public static func summary(of data: Data) throws -> Summary {
        guard data.count <= HistoryExporter.maxImportBytes else { throw HistoryExporter.ImportError.fileTooLarge }
        let outline = try JSONDecoder().decode(CollectionOutline.self, from: data)
        guard outline.version <= CollectionFilePolicy.currentVersion else {
            throw HistoryExporter.ImportError.unsupportedVersion
        }
        return Summary(name: outline.collection.name, clipCount: outline.items.count)
    }

    public static func summary(ofFile url: URL) throws -> Summary {
        try summary(of: HistoryExporter.boundedContents(of: url))
    }
}

private struct CollectionOutline: Decodable {
    struct Board: Decodable { let name: String }
    struct Entry: Decodable {}
    let version: Int
    let collection: Board
    let items: [Entry]
}
