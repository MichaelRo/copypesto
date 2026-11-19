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
    public let text: String
    public let expandsOnInsert: Bool
    /// Copied on another device (a Mac, by sync or Universal Clipboard), so the keyboard can say so.
    public let fromAnotherDevice: Bool

    public init(
        id: UUID, section: Section, kind: ClipboardType, title: String, text: String, expandsOnInsert: Bool,
        fromAnotherDevice: Bool = false
    ) {
        self.id = id
        self.section = section
        self.kind = kind
        self.title = title
        self.text = text
        self.expandsOnInsert = expandsOnInsert
        self.fromAnotherDevice = fromAnotherDevice
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        section = try container.decode(Section.self, forKey: .section)
        kind = try container.decode(ClipboardType.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        expandsOnInsert = try container.decode(Bool.self, forKey: .expandsOnInsert)
        fromAnotherDevice = try container.decodeIfPresent(Bool.self, forKey: .fromAnotherDevice) ?? false
    }
}
