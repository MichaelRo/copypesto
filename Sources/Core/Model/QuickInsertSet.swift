// SPDX-License-Identifier: MIT
import Foundation

/// What the app keeps ready for AutoFill's text insertion (ADR 0051), sealed in the app group.
public struct QuickInsertSet: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let entries: [QuickInsertEntry]

    public init(createdAt: Date, entries: [QuickInsertEntry]) {
        self.createdAt = createdAt
        self.entries = entries
    }

    public static let empty = QuickInsertSet(createdAt: Date(timeIntervalSince1970: 0), entries: [])
}
