// SPDX-License-Identifier: MIT
import Foundation

/// One clip in the quick-insert set (ADR 0051): its text exactly as it inserts, a line to show for it and the section
/// it is listed under. A snippet keeps its placeholders, which are filled at the moment it is inserted.
public struct QuickInsertEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Section: String, Codable, CaseIterable, Sendable {
        case pinned
        case snippets
        case recent
    }

    public let id: UUID
    public let section: Section
    public let kind: ClipboardType
    public let title: String
    public let text: String
    public let expandsOnInsert: Bool

    public init(
        id: UUID, section: Section, kind: ClipboardType, title: String, text: String, expandsOnInsert: Bool
    ) {
        self.id = id
        self.section = section
        self.kind = kind
        self.title = title
        self.text = text
        self.expandsOnInsert = expandsOnInsert
    }
}
