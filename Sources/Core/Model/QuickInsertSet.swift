// SPDX-License-Identifier: MIT
import Foundation

/// What the app keeps ready for AutoFill's text insertion and the keyboard (ADRs 0051, 0061, 0062), sealed in the app
/// group. A set written before collections opens with none and the keyboard returning after an insert.
public struct QuickInsertSet: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let entries: [QuickInsertEntry]
    public let collections: [QuickInsertCollection]
    /// The person's choice for the keyboard: after a tap inserts a clip, move to their own keyboard (a long press does
    /// the other).
    public let returnsAfterInsert: Bool
    public let accent: WidgetSnapshot.Theme
    public let keyboardSize: KeyboardSize
    public let keyboardEnabled: Bool
    public let autoFillEnabled: Bool

    public init(
        createdAt: Date, entries: [QuickInsertEntry], collections: [QuickInsertCollection] = [],
        returnsAfterInsert: Bool = true, accent: WidgetSnapshot.Theme = .brand,
        keyboardSize: KeyboardSize = .medium,
        keyboardEnabled: Bool = true, autoFillEnabled: Bool = true
    ) {
        self.createdAt = createdAt
        self.entries = entries
        self.collections = collections
        self.returnsAfterInsert = returnsAfterInsert
        self.accent = accent
        self.keyboardSize = keyboardSize
        self.keyboardEnabled = keyboardEnabled
        self.autoFillEnabled = autoFillEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        entries = try container.decode([QuickInsertEntry].self, forKey: .entries)
        collections = try container.decodeIfPresent([QuickInsertCollection].self, forKey: .collections) ?? []
        returnsAfterInsert = try container.decodeIfPresent(Bool.self, forKey: .returnsAfterInsert) ?? true
        accent = try container.decodeIfPresent(WidgetSnapshot.Theme.self, forKey: .accent) ?? .brand
        keyboardSize = try container.decodeIfPresent(KeyboardSize.self, forKey: .keyboardSize) ?? .medium
        keyboardEnabled = try container.decodeIfPresent(Bool.self, forKey: .keyboardEnabled) ?? true
        autoFillEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFillEnabled) ?? true
    }

    public static let empty = QuickInsertSet(createdAt: Date(timeIntervalSince1970: 0), entries: [])
}
