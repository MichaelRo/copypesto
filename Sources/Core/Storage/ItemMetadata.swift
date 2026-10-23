// SPDX-License-Identifier: MIT
import Foundation

/// What a person typed about a clip, and what a link's page called itself. Sealed into one ciphertext per clip
/// (`ClipboardItem.metadataCiphertext`) so a store file shows none of it.
public struct ItemMetadata: Codable, Equatable, Sendable {
    public var customTitle: String?
    public var userNote: String?
    public var tags: [String] = []
    public var customSymbolName: String?
    public var collectionOrder: Int?
    public var ogTitle: String?
    public var ogSiteName: String?
    public var linkPreviewFetched: Bool?

    public init(
        customTitle: String? = nil, userNote: String? = nil, tags: [String] = [],
        customSymbolName: String? = nil, collectionOrder: Int? = nil, ogTitle: String? = nil,
        ogSiteName: String? = nil, linkPreviewFetched: Bool? = nil
    ) {
        self.customTitle = customTitle
        self.userNote = userNote
        self.tags = tags
        self.customSymbolName = customSymbolName
        self.collectionOrder = collectionOrder
        self.ogTitle = ogTitle
        self.ogSiteName = ogSiteName
        self.linkPreviewFetched = linkPreviewFetched
    }

    public var isEmpty: Bool {
        customTitle == nil && userNote == nil && tags.isEmpty && customSymbolName == nil
            && collectionOrder == nil && ogTitle == nil && ogSiteName == nil && linkPreviewFetched != true
    }

    public static func parseTags(_ raw: String) -> [String] {
        raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
