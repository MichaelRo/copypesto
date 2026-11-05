// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension CommandBarView {
    static let whenMoreID = "date-more"

    /// Today and Yesterday stay one click away; choosing the one in force again clears it.
    var dayEntries: [FilterEntry] {
        [(SearchDateFilter.today, "Today"), (.yesterday, "Yesterday")].map { filter, label in
            let isOn = appState.searchDateFilter == filter
            return FilterEntry(id: "date-\(filter.id)", label: label, isActive: isOn) {
                appState.searchDateFilter = isOn ? .all : filter
            }
        }
    }

    /// The rest of the ranges in one menu chip that names the range in force. Any other date is a sentence for Ask.
    var whenMoreEntry: FilterEntry {
        let current = appState.searchDateFilter
        let isInMenu = ![SearchDateFilter.all, .today, .yesterday].contains(current)
        return FilterEntry(
            id: Self.whenMoreID, label: isInMenu ? current.label() : "More", identifier: "More time ranges",
            spoken: isInMenu ? "When, \(current.label())" : "More time ranges",
            help: "Last 7 days, the last hours, or a day", isActive: isInMenu, menu: whenMenuItems
        ) {
            openRequests[Self.whenMoreID, default: 0] += 1
        }
    }

    private var whenMenuItems: [PopUpMenuItem] {
        let current = appState.searchDateFilter
        func choice(_ title: String, _ filter: SearchDateFilter) -> PopUpMenuItem {
            .choice(title, isOn: current == filter) { appState.searchDateFilter = filter }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days: [PopUpMenuItem] = (2...13).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return choice(
                day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                .custom(DateInterval(start: day, end: end))
            )
        }
        return [
            choice("Any Time", .all), choice("Last 7 Days", .week), choice("Last 30 Days", .month), .divider,
            choice("Last Hour", .last(3600)), choice("Last 3 Hours", .last(3 * 3600)),
            choice("Last 12 Hours", .last(12 * 3600)), .divider, .submenu("On a Day", days)
        ]
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
