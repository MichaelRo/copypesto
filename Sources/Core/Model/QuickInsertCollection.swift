// SPDX-License-Identifier: MIT
import Foundation

/// A collection the person chose to carry in the quick-insert set (ADR 0062): its name and glyph for a chip, and its
/// clips in its own order as ids of the set's entries. Never its rules.
public struct QuickInsertCollection: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let symbolName: String
    public let color: String
    public let entryIDs: [UUID]

    public init(id: UUID, name: String, symbolName: String, color: String = "", entryIDs: [UUID]) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.color = color
        self.entryIDs = entryIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? ""
        entryIDs = try container.decode([UUID].self, forKey: .entryIDs)
    }
}
