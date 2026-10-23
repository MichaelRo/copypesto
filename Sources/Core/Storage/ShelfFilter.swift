// SPDX-License-Identifier: MIT
import Foundation

/// What the shelf shows, apart from the text a person typed: hidden sensitive clips, the app chips, the
/// selected collection and, while a search is active, the type, source, date, Sensitive and Other Devices chips. Search
/// by meaning
/// goes through the same filters, so it can never bring back what they removed.
public struct ShelfFilter {
    public var hidesSensitive: Bool
    public var appBundleIDs: Set<String> = []
    public var inCollection: ((ClipboardItem) -> Bool)?
    public var searchActive: Bool
    public var types: Set<String>
    public var sources: Set<String>
    public var date: SearchDateFilter
    public var sensitiveOnly: Bool
    public var remoteOnly = false
    public var now: Date = .now

    public init(
        hidesSensitive: Bool, appBundleIDs: Set<String> = [], inCollection: ((ClipboardItem) -> Bool)? = nil,
        searchActive: Bool, types: Set<String>, sources: Set<String>, date: SearchDateFilter, sensitiveOnly: Bool,
        remoteOnly: Bool = false, now: Date = .now
    ) {
        self.hidesSensitive = hidesSensitive
        self.appBundleIDs = appBundleIDs
        self.inCollection = inCollection
        self.searchActive = searchActive
        self.types = types
        self.sources = sources
        self.date = date
        self.sensitiveOnly = sensitiveOnly
        self.remoteOnly = remoteOnly
        self.now = now
    }

    /// The oldest timestamp the date chip lets through, or nil for all time.
    public var dateCutoff: Date? {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return switch date {
        case .all: nil
        case .today: startOfToday
        case .yesterday:
            Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)
                ?? startOfToday.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        }
    }

    /// An upper-bound timestamp (exclusive) when the date chip targets a completed day such as Yesterday.
    public var dateBefore: Date? {
        switch date {
        case .yesterday: Calendar.current.startOfDay(for: now)
        case .all, .today, .week, .month: nil
        }
    }

    /// Sensitive-clip hiding, the app-context filter and the collection.
    public func scope(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var result = items
        if hidesSensitive { result = result.filter { !$0.isNSFW } }
        if !appBundleIDs.isEmpty { result = result.filter { $0.sourceBundleID.map(appBundleIDs.contains) ?? false } }
        if let inCollection { result = result.filter(inCollection) }
        return result
    }

    /// The chips of the search bar; nothing while no search is active.
    public func searchBar(_ items: [ClipboardItem]) -> [ClipboardItem] {
        guard searchActive else { return items }
        var result = items
        if !types.isEmpty { result = result.filter { types.contains($0.typeRaw) } }
        if !sources.isEmpty {
            result = result.filter { $0.sourceBundleID.map(sources.contains) ?? false }
        }
        if let cutoff = dateCutoff { result = result.filter { $0.timestamp >= cutoff } }
        if let before = dateBefore { result = result.filter { $0.timestamp < before } }
        if sensitiveOnly { result = result.filter { $0.isNSFW || $0.sensitivityRaw != nil } }
        if remoteOnly { result = result.filter(\.isRemote) }
        return result
    }

    public func apply(to items: [ClipboardItem]) -> [ClipboardItem] {
        searchBar(scope(items))
    }

    /// Scope, then the typed text, then the chips; clips found by meaning follow, after the same filters.
    public func search(
        in items: [ClipboardItem],
        textMatches: ([ClipboardItem]) -> [ClipboardItem],
        supplement: [ClipboardItem]
    )
    -> [ClipboardItem] {
        var result = searchBar(textMatches(scope(items)))
        let present = Set(result.map(\.id))
        result += apply(to: supplement).filter { !present.contains($0.id) }
        return result
    }
}

/// The date range chosen in the filter bar.
public enum SearchDateFilter: String, Sendable {
    case all, today, yesterday, week, month
}
