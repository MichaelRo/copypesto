// SPDX-License-Identifier: MIT
import Foundation

public typealias AskDateRange = SearchDateFilter

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
        case .today: parts.append(String(localized: "today"))
        case .yesterday: parts.append(String(localized: "yesterday"))
        case .week: parts.append(String(localized: "past 7 days"))
        case .month: parts.append(String(localized: "past 30 days"))
        case .custom, .last: parts.append(range.label())
        }
        if !keywords.isEmpty { parts.append("\u{201C}\(keywords)\u{201D}") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func plural(_ type: ClipboardType) -> String {
        switch type {
        case .text: String(localized: "Text")
        case .url: String(localized: "Links")
        case .image: String(localized: "Images")
        case .file: String(localized: "Files")
        case .color: String(localized: "Colors")
        case .code: String(localized: "Code")
        }
    }
}
