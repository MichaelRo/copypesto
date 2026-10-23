// SPDX-License-Identifier: MIT
import Foundation

public enum AskDateRange: String, Sendable, Equatable {
    case all, today, yesterday, week, month
}

public struct AskPestoQuery: Sendable, Equatable {
    public var keywords: String
    public var types: [ClipboardType]
    public var range: AskDateRange

    public init(keywords: String, types: [ClipboardType], range: AskDateRange) {
        self.keywords = keywords
        self.types = types
        self.range = range
    }

    public var hasFilters: Bool {
        !types.isEmpty || range != .all
    }

    public var summary: String {
        var parts: [String] = []
        if !types.isEmpty { parts.append(types.map(Self.plural).joined(separator: ", ")) }
        switch range {
        case .all: break
        case .today: parts.append("today")
        case .yesterday: parts.append("yesterday")
        case .week: parts.append("past 7 days")
        case .month: parts.append("past 30 days")
        }
        if !keywords.isEmpty { parts.append("\u{201C}\(keywords)\u{201D}") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func plural(_ type: ClipboardType) -> String {
        switch type {
        case .text: "Text"
        case .url: "Links"
        case .image: "Images"
        case .file: "Files"
        case .color: "Colors"
        case .code: "Code"
        }
    }
}
