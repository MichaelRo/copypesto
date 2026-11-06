// SPDX-License-Identifier: MIT
public struct NoResultsAdvice: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case clearFilters
        case clearSearch
    }

    public let sentence: String
    public let action: Action

    public var buttonTitle: String {
        switch action {
        case .clearFilters: "Clear Filters"
        case .clearSearch: "Clear Search"
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
        if sensitiveOnly { names.append("Sensitive") }
        if remoteOnly { names.append("Other Devices") }
        if showsHidden { names.append("Hidden") }

        guard !names.isEmpty else {
            return NoResultsAdvice(
                sentence: "Nothing matches “\(query)”. Search reads the first 500 characters of each clip.",
                action: .clearSearch
            )
        }
        let subject = query.isEmpty ? "Nothing matches" : "Nothing matches “\(query)”"
        return NoResultsAdvice(sentence: "\(subject) with \(list(names)) on.", action: .clearFilters)
    }

    private static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
