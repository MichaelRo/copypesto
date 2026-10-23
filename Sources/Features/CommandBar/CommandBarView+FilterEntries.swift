// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension CommandBarView {
    var dateEntries: [FilterEntry] {
        [
            (AppState.SearchDateFilter.all, "Any time", "Any time"),
            (.today, "Today", "Today"),
            (.yesterday, "Yesterday", "Yesterday"),
            (.week, "7d", "Last 7 days"),
            (.month, "30d", "Last 30 days")
        ].map { filter, label, spoken in
            FilterEntry(
                id: "date-\(filter.rawValue)", label: label, spoken: spoken,
                isActive: appState.searchDateFilter == filter
            ) {
                appState.searchDateFilter = filter
            }
        }
    }

    var sourceEntries: [FilterEntry] {
        suggestionsModel.suggestions.topApps.map { app in
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
