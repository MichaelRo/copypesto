// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// The shelf used to filter clips one by one (`ShelfFilter` plus a text match); it now filters rows on the history
/// index. The old rule is kept here as the oracle, so the two cannot drift apart.
@MainActor
struct HistoryIndexParityTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let items: [ClipboardItem]
    private let collection = UUID()

    private struct Sample {
        let text: String
        let type: ClipboardType
        let source: String?
        let title: String?
        let tags: [String]
        let language: String?

        init(
            _ text: String,
            _ type: ClipboardType,
            _ source: String?,
            title: String? = nil,
            tags: [String] = [],
            language: String? = nil
        ) {
            self.text = text
            self.type = type
            self.source = source
            self.title = title
            self.tags = tags
            self.language = language
        }
    }

    private static let samples = [
        Sample("Café menu for Friday", .text, "com.apple.Notes", title: "Lunch"),
        Sample("let total = values.reduce(0, +)", .code, "com.apple.dt.Xcode", tags: ["swift"], language: "swift"),
        Sample("https://example.com/report", .url, "com.apple.Safari", title: "Quarterly Report", tags: ["work"]),
        Sample("#1E90FF", .color, "com.apple.ColorSyncUtility"),
        Sample("echo hello", .code, "com.apple.Terminal", tags: ["Python-notes"], language: "python"),
        Sample("invoice 2026-10", .text, "com.apple.mail", title: "Invoice", tags: ["finance", "work"]),
        Sample("Naïve résumé draft", .text, "com.apple.TextEdit"),
        Sample("hidden thing", .text, "com.apple.Safari"),
        Sample("remote note", .text, nil),
        Sample("another plain line", .text, "com.apple.Notes", title: "Notes to self", tags: ["inv"])
    ]

    init() throws {
        container = try ModelContainerSetup.makeInMemory().synced
        context = ModelContext(container)
        var built: [ClipboardItem] = []
        for (offset, sample) in Self.samples.enumerated() {
            let item = ClipboardItem(
                type: sample.type, sourceBundleID: sample.source, previewText: sample.text,
                contentHash: "h\(offset)", byteSize: 10, deviceID: "t", sequenceNumber: Int64(offset),
                collectionID: offset % 3 == 0 ? collection : nil
            )
            item.timestamp = Date(timeIntervalSinceNow: -Double(Self.samples.count - offset) * 86_400 * 4)
            item.detectedLanguage = sample.language
            item.isNSFW = offset == 7
            item.isRemote = offset == 8
            context.insert(item)
            if sample.title != nil || !sample.tags.isEmpty {
                item.updateMetadata {
                    $0.customTitle = sample.title
                    $0.tags = sample.tags
                }
            }
            built.append(item)
        }
        try context.save()
        items = built.sorted { $0.timestamp > $1.timestamp }
    }

    /// The text rule the shelf used before the index, line for line.
    private func legacyTextMatches(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        if query.hasPrefix("@") {
            let suffix = String(query.dropFirst()).lowercased()
            return items.filter { item in
                item.tags.contains { $0.lowercased().hasPrefix(suffix) } || item.detectedLanguage?
                    .lowercased() == suffix
            }
        }
        let foldedQuery = SearchMatching.fold(query)
        return items.filter { item in
            SearchMatching.matches(foldedText: item.searchableGridPreview, foldedQuery: foldedQuery)
                || (item.customTitle.map { SearchMatching.matches($0, query: query) } == true)
                || (item.userNote.map { SearchMatching.matches($0, query: query) } == true)
                || item.tags.contains { SearchMatching.matches($0, query: query) }
        }
    }

    @Test("the index filters exactly as the old shelf pipeline did, over every combination of scope, chips and text")
    func indexAgreesWithShelfFilter() {
        let index = HistoryIndex(items: items)
        let queries = ["", "cafe", "REPORT", "résumé", "naive", "@python", "@w", "@swift", "inv", "zzz", "e"]
        var checked = 0
        for query in queries {
            for hides in [false, true] {
                for searchActive in [false, true] {
                    for apps in [Set<String>(), ["com.apple.Notes", "com.apple.Safari"]] {
                        for inCollection in [false, true] {
                            for chip in 0..<6 {
                                var filter = ShelfFilter(
                                    hidesSensitive: hides, appBundleIDs: apps,
                                    inCollection: inCollection ? { [collection] in $0.collectionID == collection } :
                                        nil,
                                    searchActive: searchActive, types: [], sources: [], date: .all,
                                    sensitiveOnly: false, remoteOnly: false
                                )
                                switch chip {
                                case 1: filter.types = [ClipboardType.code.rawValue]
                                case 2: filter.sources = ["com.apple.Safari"]
                                case 3: filter.date = .week
                                case 4: filter.sensitiveOnly = true
                                case 5: filter.remoteOnly = true
                                default: break
                                }
                                let expected = filter.search(
                                    in: items, textMatches: { legacyTextMatches($0, query: query) }, supplement: []
                                ).map(\.id)
                                let actual = index.matching(
                                    HistoryCriteria(
                                        hidesSensitive: filter.hidesSensitive, appBundleIDs: filter.appBundleIDs,
                                        collectionID: inCollection ? collection : nil,
                                        searchActive: filter.searchActive,
                                        types: filter.types, sources: filter.sources, dateCutoff: filter.dateCutoff,
                                        dateBefore: filter.dateBefore,
                                        sensitiveOnly: filter.sensitiveOnly, remoteOnly: filter.remoteOnly, query: query
                                    )
                                )
                                #expect(
                                    actual == expected,
                                    "'\(query)' \(hides) \(searchActive) \(apps.count) \(inCollection) \(chip)"
                                )
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        #expect(checked == 11 * 2 * 2 * 2 * 2 * 6)
    }
}
