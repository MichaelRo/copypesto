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
    /// What the person last typed into each fill-in of a snippet, sealed with the rest (ADR 0017).
    public var fieldMemory: [String: String]?
    /// The clip's `TextSignature`, for noticing clips that look alike (ADR 0017). Derived data, sealed with the rest.
    public var signature: [UInt32]?
    /// The days (counted from the reference date) on which the clip was pasted, the last thirty at most.
    public var pasteDays: [Int]?

    public init(
        customTitle: String? = nil, userNote: String? = nil, tags: [String] = [],
        customSymbolName: String? = nil, collectionOrder: Int? = nil, ogTitle: String? = nil,
        ogSiteName: String? = nil, linkPreviewFetched: Bool? = nil, fieldMemory: [String: String]? = nil,
        signature: [UInt32]? = nil,
        pasteDays: [Int]? = nil
    ) {
        self.customTitle = customTitle
        self.userNote = userNote
        self.tags = tags
        self.customSymbolName = customSymbolName
        self.collectionOrder = collectionOrder
        self.ogTitle = ogTitle
        self.ogSiteName = ogSiteName
        self.linkPreviewFetched = linkPreviewFetched
        self.fieldMemory = fieldMemory
        self.signature = signature
        self.pasteDays = pasteDays
    }

    public var isEmpty: Bool {
        customTitle == nil && userNote == nil && tags.isEmpty && customSymbolName == nil
            && collectionOrder == nil && ogTitle == nil && ogSiteName == nil && linkPreviewFetched != true
            && (fieldMemory ?? [:]).isEmpty && signature == nil && (pasteDays ?? []).isEmpty
    }

    public static let pasteDayWindow = 30

    public static func dayNumber(of date: Date, calendar: Calendar = .current) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate / 86_400)
    }

    public static func parseTags(_ raw: String) -> [String] {
        raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
