// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public enum InsightsDateRange: String, CaseIterable, Sendable {
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"

    public var days: Int {
        self == .sevenDays ? 7 : 30
    }

    public var label: String {
        switch self {
        case .sevenDays: String(localized: "7 Days")
        case .thirtyDays: String(localized: "30 Days")
        }
    }
}

/// Pre-aggregated activity snapshot — retains lightweight values rather than live `ClipboardItem` model objects.
public struct InsightsSummary: Equatable, Sendable {
    public struct DailyCount: Equatable, Identifiable, Sendable {
        public let date: Date
        public let count: Int
        public var id: Date {
            date
        }

        public init(date: Date, count: Int) {
            self.date = date
            self.count = count
        }
    }

    public struct TypeCount: Equatable, Identifiable, Sendable {
        public let kind: ClipboardType
        public let count: Int
        public var id: ClipboardType {
            kind
        }

        public var label: String {
            kind.presentation.label
        }

        public init(kind: ClipboardType, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public struct Source: Equatable, Identifiable, Sendable {
        public let id: String
        public var bundleID: String? {
            id == "unknown" ? nil : id
        }

        public let name: String
        public let count: Int

        public init(id: String, name: String, count: Int) {
            self.id = id
            self.name = name
            self.count = count
        }
    }

    public struct PastedClip: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let preview: String
        public let count: Int

        public init(id: UUID, preview: String, count: Int) {
            self.id = id
            self.preview = preview
            self.count = count
        }
    }

    public var totalClips: Int
    public var dailyCounts: [DailyCount]
    public var typeCounts: [TypeCount]
    public var topSources: [Source]
    public var topPasted: [PastedClip]

    public var hasItems: Bool {
        totalClips > 0
    }

    public init(
        totalClips: Int = 0,
        dailyCounts: [DailyCount] = [],
        typeCounts: [TypeCount] = [],
        topSources: [Source] = [],
        topPasted: [PastedClip] = []
    ) {
        self.totalClips = totalClips
        self.dailyCounts = dailyCounts
        self.typeCounts = typeCounts
        self.topSources = topSources
        self.topPasted = topPasted
    }
}

public enum InsightsBuilder {
    /// Start of the first calendar day in `range` ending on `now`'s day (inclusive of today).
    public static func startDate(
        for range: InsightsDateRange,
        now: Date = .now,
        calendar: Calendar = .current
    )
    -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
    }

    /// Fetches on a background `ModelContext` sorted newest first so large histories retain today's activity without
    /// decrypting previews on the main actor.
    @concurrent
    public static func build(
        in container: ModelContainer,
        range: InsightsDateRange,
        now: Date = .now,
        calendar: Calendar = .current,
        unknownSourceLabel: String = String(localized: "Unknown"),
        concealedIDs: Set<UUID> = []
    ) async
    -> InsightsSummary {
        let cutoff = startDate(for: range, now: now, calendar: calendar)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5000
        let context = ModelContext(container)
        guard let items = try? context.fetch(descriptor) else { return InsightsSummary() }
        return build(
            from: items,
            range: range,
            now: now,
            calendar: calendar,
            unknownSourceLabel: unknownSourceLabel,
            isConcealed: { concealedIDs.contains($0.id) }
        )
    }

    /// Aggregates clipboard activity without keeping model instances or reading plaintext of sensitive, NSFW,
    /// analysis-pending, or concealed clips.
    public static func build(
        from items: [ClipboardItem],
        range: InsightsDateRange,
        now: Date = .now,
        calendar: Calendar = .current,
        unknownSourceLabel: String = "unknown",
        isConcealed: (ClipboardItem) -> Bool = { _ in false }
    )
        -> InsightsSummary
    {
        let start = startDate(for: range, now: now, calendar: calendar)
        let filtered = items.filter { $0.timestamp >= start && $0.timestamp <= now }
        guard !filtered.isEmpty else { return InsightsSummary() }

        let groupedByDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.timestamp) }
        let dailyCounts: [InsightsSummary.DailyCount] = (0..<range.days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return InsightsSummary.DailyCount(date: day, count: groupedByDay[day]?.count ?? 0)
        }

        var typeBuckets: [ClipboardType: Int] = [:]
        var sourceCounts: [String: Int] = [:]
        var sourceNames: [String: String] = [:]
        for item in filtered {
            typeBuckets[item.type, default: 0] += 1
            let key = item.sourceBundleID ?? "unknown"
            sourceCounts[key, default: 0] += 1
            if sourceNames[key] == nil {
                sourceNames[key] = item.sourceAppName ?? (key == "unknown" ? unknownSourceLabel : key)
            }
        }

        let typeCounts = typeBuckets
            .map { InsightsSummary.TypeCount(kind: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.kind.rawValue < $1.kind.rawValue
            }

        let topSources = sourceCounts
            .map { key, count in
                InsightsSummary.Source(id: key, name: sourceNames[key] ?? key, count: count)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name < $1.name
            }
            .prefix(5)
            .map(\.self)

        let topPasted = filtered
            .filter { item in
                item.pasteCount > 0
                    && item.sensitivityRaw == nil
                    && !item.isNSFW
                    && !item.analysisPending
                    && !isConcealed(item)
            }
            .sorted {
                if $0.pasteCount != $1.pasteCount { return $0.pasteCount > $1.pasteCount }
                return $0.timestamp > $1.timestamp
            }
            .prefix(10)
            .map { item in
                let raw = String(item.displayPreviewText.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
                let label = raw.isEmpty ? item.type.presentation.label : raw
                return InsightsSummary.PastedClip(id: item.id, preview: label, count: item.pasteCount)
            }

        return InsightsSummary(
            totalClips: filtered.count,
            dailyCounts: dailyCounts,
            typeCounts: typeCounts,
            topSources: topSources,
            topPasted: topPasted
        )
    }
}
