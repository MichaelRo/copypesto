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
            id: Self.whenMoreID, label: isInMenu ? current.label() : String(localized: "Date"),
            identifier: "More time ranges",
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
            choice("Last 12 Hours", .last(12 * 3600)), .divider, .submenu("On a Day", days),
            .divider, .action("Custom Date Range\u{2026}") { openCustomDateRangePicker() }
        ]
    }

    private func openCustomDateRangePicker() {
        if let interval = appState.searchDateFilter.interval(now: .now) {
            let lastDay = max(interval.start, min(Date.now, interval.end.addingTimeInterval(-1)))
            customStartDate = interval.start
            customEndDate = lastDay
            customRangeSingleDay = Calendar.current.isDate(interval.start, inSameDayAs: lastDay)
        } else {
            customStartDate = .now
            customEndDate = .now
            customRangeSingleDay = false
        }
        appState.showsCustomDateRange = true
    }

    var customDateRangePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Single day", isOn: $customRangeSingleDay)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)

            HStack(spacing: 8) {
                DatePicker(
                    customRangeSingleDay ? "Date" : "From",
                    selection: $customStartDate,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(customRangeSingleDay ? "Date" : "Start date")
                .onChange(of: customStartDate) { _, start in
                    if customEndDate < start {
                        customEndDate = start
                    }
                }

                if !customRangeSingleDay {
                    Text("to")
                        .font(.caption)
                        .pestoQuiet()
                    DatePicker(
                        "To",
                        selection: $customEndDate,
                        in: customStartDate...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("End date")
                }
            }

            HStack {
                Button("Clear") {
                    appState.searchDateFilter = .all
                    appState.showsCustomDateRange = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .pestoQuiet()
                .accessibilityIdentifier(AccessibilityID.customDateClearButton)

                Spacer(minLength: 12)

                Button("Apply") {
                    let end = customRangeSingleDay ? customStartDate : customEndDate
                    appState.searchDateFilter = SearchDateFilter.customRange(from: customStartDate, to: end)
                    appState.showsCustomDateRange = false
                }
                .buttonStyle(.pestoProminent)
                .controlSize(.small)
                .tint(accent)
                .accessibilityIdentifier(AccessibilityID.customDateApplyButton)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.customDateRangeRow)
    }

    func duplicatePinboard(_ source: Pinboard) {
        let next = (pinboards.map(\.sortOrder).max() ?? -1) + 1
        let copy = Pinboard(
            name: CollectionNaming.copyName(of: source.name, existing: pinboards.map(\.name)),
            symbolName: source.symbolName,
            colorHex: source.colorHex,
            sortOrder: next,
            isSmart: source.isSmart,
            smartPredicateData: source.smartPredicateData,
            triggerBundleID: nil
        )
        appState.attempt("Couldn\u{2019}t duplicate the collection") {
            try appState.collectionStore(context: modelContext).insert(.duplicate, [copy])
        }
    }

    func deletePinboard(_ pinboard: Pinboard) {
        let id = pinboard.id
        Task {
            guard await appState.confirmsLockedCollectionAction(
                id, reason: String(localized: "delete a locked collection")
            ) else { return }
            appState.deleteCollection(id: id, fromShelf: true)
        }
    }

    func persistPinboardOrder(_ order: [UUID], moved id: UUID? = nil) {
        let ids = pinboards.map(\.id)
        guard order != ids else { return }
        let reordered = order.compactMap { id in pinboards.first { $0.id == id } }
        appState.attempt("Couldn\u{2019}t save the collection order") {
            try appState.collectionStore(context: modelContext).edit(.reorder, reordered) {
                for (i, p) in reordered.enumerated() {
                    p.sortOrder = i
                }
            }
        }
        if let id,
           let position = order.firstIndex(of: id),
           let name = pinboards.first(where: { $0.id == id })?.name
        {
            Announcer.announce("\(name), position \(position + 1) of \(order.count)")
        } else {
            Announcer.announce("Moved")
        }
    }

    func movePinboard(_ id: UUID, by offset: Int) {
        let ids = pinboards.map(\.id)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + offset) else { return }
        var order = ids
        order.swapAt(from, from + offset)
        withAnimation(Motion.animation(.pestoMove)) { persistPinboardOrder(order, moved: id) }
    }

    static let fromID = "from"
    static let formatID = "format"

    /// From: one menu chip with every app and its clip count. It reads "Any app" until an app is chosen, then the app's
    /// name (or the first one and how many more).
    var fromEntry: FilterEntry? {
        let apps = suggestionsModel.suggestions.allApps
        guard !apps.isEmpty else { return nil }
        let chosen = apps.filter { appState.searchSourceFilter.contains($0.bundleID) }
        let label = FilterMenuLabel.from(chosen: chosen.map(\.name))
        var items: [PopUpMenuItem] = []
        if !chosen.isEmpty {
            items += [.action("Any App") { appState.searchSourceFilter = [] }, .divider]
        }
        items += apps.map { app in
            .choice("\(app.name) \u{00B7} \(app.count)", isOn: appState.searchSourceFilter.contains(app.bundleID)) {
                if appState.searchSourceFilter.contains(app.bundleID) {
                    appState.searchSourceFilter.remove(app.bundleID)
                } else {
                    appState.searchSourceFilter.insert(app.bundleID)
                }
            }
        }
        return FilterEntry(
            id: Self.fromID, label: label, identifier: "Filter by app",
            spoken: chosen.isEmpty ? "From, any app" : "From, \(chosen.map(\.name).joined(separator: ", "))",
            help: "Show only clips copied from an app", isActive: !chosen.isEmpty, menu: items
        ) {
            openRequests[Self.fromID, default: 0] += 1
        }
    }

    /// Format: one menu chip with Markdown, JSON and the languages in the history, each putting `@name` in the search
    /// field (a language matches by its first letters, and exactly when it is a whole name).
    var formatEntry: FilterEntry {
        let languages = suggestionsModel.suggestions.languages
        let tag = selectedTag?.lowercased()
        let named: [(tag: String, title: String)] =
            [("markdown", "Markdown"), ("json", "JSON")] + languages.map { ($0.name, $0.displayName) }
        let current = named.first { $0.tag == tag }
        var items: [PopUpMenuItem] = []
        if current != nil {
            items.append(.action("Any Format") {
                appState.cancelAsk()
                appState.searchText = ""
            })
            items.append(.divider)
        }
        for (name, title) in [("markdown", "Markdown"), ("json", "JSON")] {
            items.append(.choice(title, isOn: tag == name) {
                appState.cancelAsk()
                appState.searchText = tag == name ? "" : "@\(name)"
            })
        }
        if !languages.isEmpty {
            items.append(.divider)
            items += languages.map { language in
                .choice(
                    "\(language.displayName) \u{00B7} \(language.count)", isOn: tag == language.name
                ) {
                    appState.cancelAsk()
                    appState.searchText = tag == language.name ? "" : "@\(language.name)"
                }
            }
        }
        return FilterEntry(
            id: Self.formatID, label: FilterMenuLabel.format(chosen: current?.title), identifier: "Filter by format",
            spoken: current.map { "Format, \($0.title)" } ?? "Format, any",
            help: "Show only clips written as Markdown, JSON or a language", isActive: current != nil, menu: items
        ) {
            openRequests[Self.formatID, default: 0] += 1
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
