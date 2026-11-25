// SPDX-License-Identifier: MIT
import Foundation

public struct NoResultsAdvice: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case clearFilters
        case clearSearch
    }

    public let sentence: String
    public let action: Action

    public var buttonTitle: String {
        switch action {
        case .clearFilters: String(localized: "Clear Filters")
        case .clearSearch: String(localized: "Clear Search")
        }
    }

    public static func make(
        query: String,
        kinds: Set<ClipboardType> = [],
        date: SearchDateFilter = .all,
        appNames: [String] = [],
        sensitiveOnly: Bool = false,
        remoteOnly: Bool = false,
        showsHidden: Bool = false
    )
    -> NoResultsAdvice {
        var names = ClipboardType.allCases.filter(kinds.contains).map(\.presentation.label)
        if date != .all { names.append(date.label()) }
        names += appNames
        if sensitiveOnly { names.append(String(localized: "Sensitive")) }
        if remoteOnly { names.append(String(localized: "Other Devices")) }
        if showsHidden { names.append(String(localized: "Hidden")) }

        guard !names.isEmpty else {
            let lead = String(localized: "Nothing matches \u{201C}\(query)\u{201D}.")
            let hint = String(localized: "Search reads the first 500 characters of each clip.")
            return NoResultsAdvice(sentence: "\(lead) \(hint)", action: .clearSearch)
        }
        let nameList = list(names)
        let sentence = query.isEmpty
            ? String(localized: "Nothing matches with \(nameList) on.")
            : String(localized: "Nothing matches \u{201C}\(query)\u{201D} with \(nameList) on.")
        return NoResultsAdvice(sentence: sentence, action: .clearFilters)
    }

    private static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        let head = names.dropLast().joined(separator: String(localized: ", "))
        return String(localized: "\(head) and \(last)")
    }
}
