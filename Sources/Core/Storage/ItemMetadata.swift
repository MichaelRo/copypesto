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
    /// When the clip was first copied, kept once a paste, a copy or a re-copy moves its `timestamp` to the front, so a
    /// collection can keep a clip where it was. Absent until the first of those.
    public var copiedAt: Date?
    /// How the clip was made on this iPhone or iPad (ADR 0049). Never synced or backed up.
    public var captureMethod: CaptureMethod?
    /// What rules a lookalike picture out without decoding it (ADR 0077). Derived from this device's decoder: never
    /// synced or backed up.
    public var pictureFingerprint: PictureFingerprint?
    /// Other devices' clip IDs folded into this clip during sync (exact-hash twins or perceptual lookalikes). Never
    /// synced or backed up; used so deleting this clip tombstones its folded peer IDs too.
    public var foldedSyncIDs: [UUID]?

    public init(
        customTitle: String? = nil, userNote: String? = nil, tags: [String] = [],
        customSymbolName: String? = nil, collectionOrder: Int? = nil, ogTitle: String? = nil,
        ogSiteName: String? = nil, linkPreviewFetched: Bool? = nil, fieldMemory: [String: String]? = nil,
        signature: [UInt32]? = nil,
        pasteDays: [Int]? = nil, copiedAt: Date? = nil, captureMethod: CaptureMethod? = nil,
        pictureFingerprint: PictureFingerprint? = nil, foldedSyncIDs: [UUID]? = nil
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
        self.copiedAt = copiedAt
        self.captureMethod = captureMethod
        self.pictureFingerprint = pictureFingerprint
        self.foldedSyncIDs = foldedSyncIDs
    }

    public var isEmpty: Bool {
        customTitle == nil && userNote == nil && tags.isEmpty && customSymbolName == nil
            && collectionOrder == nil && ogTitle == nil && ogSiteName == nil && linkPreviewFetched != true
            && (fieldMemory ?? [:]).isEmpty && signature == nil && (pasteDays ?? []).isEmpty
            && copiedAt == nil && captureMethod == nil && pictureFingerprint == nil
            && (foldedSyncIDs ?? []).isEmpty
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
