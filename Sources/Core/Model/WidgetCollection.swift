// SPDX-License-Identifier: MIT
import Foundation

/// A collection as the widget offers it in its settings (ADR 0060): what the picker lists and an empty widget draws,
/// never its rules or anything about its clips.
public struct WidgetCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let symbolName: String
    /// `#RRGGBB`, as the collection stores it.
    public let colorHex: String
    public let isSmart: Bool

    public init(id: UUID, name: String, symbolName: String, colorHex: String, isSmart: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.isSmart = isSmart
    }
}
