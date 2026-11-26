// SPDX-License-Identifier: MIT
import Foundation

/// One clip in the quick-insert set (ADR 0051): its text exactly as it inserts, a line to show for it and the section
/// it is listed under. A snippet keeps its placeholders, which are filled at the moment it is inserted. A clip carried
/// only for a chosen collection is in `collection` (ADR 0062).
public struct QuickInsertEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Section: String, Codable, CaseIterable, Sendable {
        case pinned
        case snippets
        case recent
        case collection
    }

    public let id: UUID
    public let section: Section
    public let kind: ClipboardType
    public let title: String
    public let customTitle: String?
    public let ogTitle: String?
    public let text: String
    public let expandsOnInsert: Bool
    /// Copied on another device (a Mac, by sync or Universal Clipboard), so the keyboard can say so.
    public let fromAnotherDevice: Bool
    public let date: Date
    public let source: String?
    public let sourceIsThisDevice: Bool
    public let thumbnail: Data?
    public let recognizedText: String?
    public let isAnimated: Bool
    public let fieldMemory: [String: String]?
    /// The app it came from, a key of `QuickInsertSet.appIcons` (ADR 0074).
    public let sourceBundleID: String?
    /// The app's color as `#RRGGBB`, for the card's foot glow (ADR 0068).
    public let sourceColorHex: String?

    public var hasRecognizedText: Bool {
        recognizedText?.isEmpty == false
    }

    public init(
        id: UUID, section: Section, kind: ClipboardType, title: String, text: String, expandsOnInsert: Bool,
        fromAnotherDevice: Bool = false, customTitle: String? = nil, ogTitle: String? = nil,
        date: Date = Date(timeIntervalSince1970: 0), source: String? = nil, sourceIsThisDevice: Bool = false,
        thumbnail: Data? = nil, recognizedText: String? = nil, isAnimated: Bool = false,
        fieldMemory: [String: String]? = nil, sourceBundleID: String? = nil, sourceColorHex: String? = nil
    ) {
        self.id = id
        self.section = section
        self.kind = kind
        self.title = title
        self.customTitle = customTitle
        self.ogTitle = ogTitle
        self.text = text
        self.expandsOnInsert = expandsOnInsert
        self.fromAnotherDevice = fromAnotherDevice
        self.date = date
        self.source = source
        self.sourceIsThisDevice = sourceIsThisDevice
        self.thumbnail = thumbnail
        self.recognizedText = recognizedText
        self.isAnimated = isAnimated
        self.fieldMemory = fieldMemory
        self.sourceBundleID = sourceBundleID
        self.sourceColorHex = sourceColorHex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        section = try container.decode(Section.self, forKey: .section)
        kind = try container.decode(ClipboardType.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        ogTitle = try container.decodeIfPresent(String.self, forKey: .ogTitle)
        text = try container.decode(String.self, forKey: .text)
        expandsOnInsert = try container.decode(Bool.self, forKey: .expandsOnInsert)
        fromAnotherDevice = try container.decodeIfPresent(Bool.self, forKey: .fromAnotherDevice) ?? false
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date(timeIntervalSince1970: 0)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceIsThisDevice = try container.decodeIfPresent(Bool.self, forKey: .sourceIsThisDevice) ?? false
        thumbnail = try container.decodeIfPresent(Data.self, forKey: .thumbnail)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        isAnimated = try container.decodeIfPresent(Bool.self, forKey: .isAnimated) ?? false
        fieldMemory = try container.decodeIfPresent([String: String].self, forKey: .fieldMemory)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceColorHex = try container.decodeIfPresent(String.self, forKey: .sourceColorHex)
    }
}
