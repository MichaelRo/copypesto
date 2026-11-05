// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension CommandBarView {
    static let whenEntryID = "date-when"

    private static let datePresets: [SearchDateFilter] = [.all, .today, .yesterday, .week, .month]

    /// The When chip: it names the range in force, a click opens the menu, and the keyboard steps through the presets.
    var whenEntry: FilterEntry {
        let current = appState.searchDateFilter
        return FilterEntry(
            id: Self.whenEntryID, label: current.label(), spoken: "When, \(current.label())",
            help: "Show only clips from a time range", isActive: current != .all
        ) {
            let presets = Self.datePresets
            let next = presets.firstIndex(of: appState.searchDateFilter).map { ($0 + 1) % presets.count } ?? 0
            appState.searchDateFilter = presets[next]
        }
    }

    /// Presets, the last hours and the last two weeks of days. Any other date is a sentence for Ask.
    @ViewBuilder
    var whenMenu: some View {
        let now = Date.now
        let calendar = Calendar.current
        ForEach(Self.datePresets, id: \.id) { filter in
            whenButton(filter.label(), filter: filter)
        }
        Divider()
        ForEach([1, 3, 12], id: \.self) { hours in
            let range = SearchDateFilter.custom(DateInterval(
                start: now.addingTimeInterval(-Double(hours) * 3600), end: now.addingTimeInterval(60)
            ))
            whenButton(hours == 1 ? "Last hour" : "Last \(hours) hours", filter: range)
        }
        Menu("On a Day") {
            ForEach(2...13, id: \.self) { back in
                if let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)),
                   let end = calendar.date(byAdding: .day, value: 1, to: day)
                {
                    whenButton(
                        day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                        filter: .custom(DateInterval(start: day, end: end))
                    )
                }
            }
        }
        Divider()
        Button("For other dates, ask: \u{201C}between Nov 1 and Nov 3\u{201D}") {}
            .disabled(true)
    }

    private func whenButton(_ title: String, filter: SearchDateFilter) -> some View {
        Button {
            appState.searchDateFilter = filter
        } label: {
            if isChosen(filter, titled: title) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func isChosen(_ filter: SearchDateFilter, titled title: String) -> Bool {
        guard case let .custom(candidate) = filter, case let .custom(current) = appState.searchDateFilter else {
            return appState.searchDateFilter == filter
        }
        let isWholeDay = Calendar.current.startOfDay(for: candidate.start) == candidate.start
        return isWholeDay ? current == candidate : appState.searchDateFilter.label() == title
    }

    /// The From chips: the three most copied apps, and any further one that is in use so it can be switched off.
    var sourceEntries: [FilterEntry] {
        let apps = suggestionsModel.suggestions.topApps
        let shown = apps.prefix(3) + apps.dropFirst(3).filter { appState.searchSourceFilter.contains($0.bundleID) }
        return shown.map { app in
            FilterEntry(
                id: "app-\(app.bundleID)", label: app.name,
                iconImage: SourceIconCache.shared.image(forBundleID: app.bundleID),
                isActive: appState.searchSourceFilter.contains(app.bundleID)
            ) {
                if appState.searchSourceFilter.contains(app.bundleID) {
                    appState.searchSourceFilter.remove(app.bundleID)
                } else {
                    appState.searchSourceFilter.insert(app.bundleID)
                }
            }
        }
    }

    /// Formats of text that the classifier tags (`@markdown`, `@json`): one chip each puts the tag in the search field.
    var formatEntries: [FilterEntry] {
        [("markdown", "Markdown", "text.alignleft"), ("json", "JSON", "curlybraces")].map { tag, label, icon in
            let isActive = selectedTag?.lowercased() == tag
            return FilterEntry(
                id: "format-\(tag)", label: label, icon: icon, help: "Show only clips written as \(label)",
                isActive: isActive
            ) {
                appState.searchText = isActive ? "" : "@\(tag)"
            }
        }
    }

    var sensitiveEntry: FilterEntry {
        FilterEntry(
            id: "sensitive", label: "Sensitive", icon: "eye.slash",
            help: "Show only sensitive clips: the ones Pesto hid as secrets and the ones marked sensitive",
            isActive: appState.searchSensitiveOnly
        ) {
            appState.searchSensitiveOnly.toggle()
        }
    }

    var remoteEntries: [FilterEntry] {
        guard keepsRemoteCopies || suggestionsModel.suggestions.hasRemoteClips || appState.searchRemoteOnly else {
            return []
        }
        return [FilterEntry(
            id: "remote", label: "Other Devices", icon: "iphone", help: "Show only clips copied on another device",
            isActive: appState.searchRemoteOnly
        ) {
            appState.searchRemoteOnly.toggle()
        }]
    }

    /// The NSFW reveal toggle: only shown while filtering is on.
    var hiddenEntries: [FilterEntry] {
        guard nsfwModeRaw == NSFWMode.hide.rawValue else { return [] }
        return [FilterEntry(
            id: "hidden", label: "Hidden", icon: "eye.slash", help: "Show sensitive clips in search results",
            isActive: appState.showHiddenNSFW
        ) {
            appState.showHiddenNSFW.toggle()
        }]
    }
}
