// SPDX-License-Identifier: MIT
import Foundation

public struct SourceApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    /// How many clips came from it; 0 where the list is not a count (the shelf's app chips).
    public let count: Int

    public init(bundleID: String, name: String, count: Int = 0) {
        self.bundleID = bundleID
        self.name = name
        self.count = count
    }
}

/// A language the history holds, with how many clips carry it (the Format menu).
public struct LanguageCount: Sendable, Equatable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    public var displayName: String {
        Self.names[name] ?? name.prefix(1).uppercased() + name.dropFirst()
    }

    private static let names: [String: String] = [
        "javascript": "JavaScript", "typescript": "TypeScript", "html": "HTML", "css": "CSS", "sql": "SQL",
        "svg": "SVG", "xml": "XML", "yaml": "YAML", "php": "PHP", "csharp": "C#", "cpp": "C++", "go": "Go"
    ]
}

public struct CommandBarSuggestions: Sendable, Equatable {
    public let topTags: [String]
    public let topApps: [SourceApp]
    /// The apps copied from most over the last seven days, most copied first (the shelf's app chips).
    public let recentApps: [SourceApp]
    public let hasRemoteClips: Bool
    /// Every app a clip came from, most copied first (the From menu); `topApps` is its first few.
    public let allApps: [SourceApp]
    /// The languages in the history other than Markdown and JSON, which have chips of their own.
    public let languages: [LanguageCount]

    public static let empty = CommandBarSuggestions(topTags: [], topApps: [])

    public init(
        topTags: [String], topApps: [SourceApp], recentApps: [SourceApp] = [], hasRemoteClips: Bool = false,
        allApps: [SourceApp] = [], languages: [LanguageCount] = []
    ) {
        self.topTags = topTags
        self.topApps = topApps
        self.recentApps = recentApps
        self.hasRemoteClips = hasRemoteClips
        self.allApps = allApps
        self.languages = languages
    }
}

/// The app chips beside the collections: pinned apps first, then the app in front, then the few others copied from
/// most lately. Pesto itself is never one (its own windows are often in front while the shelf opens).
public enum AppChips {
    public static let recentLimit = 3
    public static let recentDays = 7

    public static func pinnedIDs(from stored: String) -> [String] {
        var seen: Set<String> = []
        return stored
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func encodePinnedIDs(_ ids: [String]) -> String {
        var seen: Set<String> = []
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ",")
    }

    public static func togglePinned(_ bundleID: String, in stored: String) -> String {
        var current = pinnedIDs(from: stored)
        if let index = current.firstIndex(of: bundleID) {
            current.remove(at: index)
        } else {
            current.append(bundleID)
        }
        return encodePinnedIDs(current)
    }

    public static func removePinned(_ bundleID: String, in stored: String) -> String {
        encodePinnedIDs(pinnedIDs(from: stored).filter { $0 != bundleID })
    }

    public static func chips(
        frontmost: SourceApp?, recent: [SourceApp], ownBundleID: String?, recentLimit: Int = AppChips.recentLimit,
        pinnedBundleIDs: [String] = [], knownApps: [SourceApp] = [], resolveAppName: (String) -> String? = { _ in nil }
    )
        -> [SourceApp]
    {
        var namesByID: [String: String] = [:]
        for app in knownApps + recent + (frontmost.map { [$0] } ?? []) where namesByID[app.bundleID] == nil {
            namesByID[app.bundleID] = app.name
        }
        let pinned: [SourceApp] = pinnedBundleIDs.compactMap { id in
            guard id != ownBundleID else { return nil }
            let name = namesByID[id] ?? resolveAppName(id) ?? id
            return SourceApp(bundleID: id, name: name)
        }
        let pinnedSet = Set(pinned.map(\.bundleID))
        let front = frontmost.flatMap {
            $0.bundleID == ownBundleID || pinnedSet.contains($0.bundleID) ? nil : $0
        }
        let others = recent.filter {
            $0.bundleID != ownBundleID && !pinnedSet.contains($0.bundleID) && $0.bundleID != front?.bundleID
        }
        // With no unpinned app in front (Pesto's own menu or Settings was, or the frontmost app is pinned), a fourth
        // recent app stands in, so the row is never short.
        return pinned + (front.map { [$0] } ?? []) + others.prefix(front == nil ? recentLimit + 1 : recentLimit)
    }
}

public enum TopCounts {
    /// Most used first; equal counts fall back to the key, so a refresh never reorders chips that did not change.
    public static func rank<Key: Hashable & Comparable>(_ counts: [Key: Int], limit: Int) -> [Key] {
        guard limit > 0 else { return [] }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}

/// Accumulates clips one at a time, so the history never has to be in memory at once. Add the newest clips first: an
/// app is named as the first clip seen names it.
public struct SuggestionTally: Sendable {
    private var tagCounts: [String: Int] = [:]
    private var appCounts: [String: Int] = [:]
    private var recentAppCounts: [String: Int] = [:]
    private var appNames: [String: String] = [:]
    private var languageCounts: [String: Int] = [:]
    private var hasRemoteClips = false
    private let recentSince: Date?
    private static let languagesWithTheirOwnChip: Set<String> = ["markdown", "json", "text"]

    /// `recentSince` is the start of the window that makes an app "recent"; without it there are no recent apps.
    public init(recentSince: Date? = nil) {
        self.recentSince = recentSince
    }

    public mutating func add(
        tags: [String], bundleID: String?, appName: String?, isRemote: Bool = false, timestamp: Date? = nil,
        language: String? = nil
    ) {
        if isRemote { hasRemoteClips = true }
        if let language, !Self.languagesWithTheirOwnChip.contains(language.lowercased()) {
            languageCounts[language.lowercased(), default: 0] += 1
        }
        for tag in tags {
            tagCounts[tag, default: 0] += 1
        }
        guard let bundleID, appName != SourceAppRecord.unknownDisplayName else { return }
        appCounts[bundleID, default: 0] += 1
        if let recentSince, let timestamp, timestamp >= recentSince { recentAppCounts[bundleID, default: 0] += 1 }
        if appNames[bundleID] == nil, let appName { appNames[bundleID] = appName }
    }

    public func suggestions(tagLimit: Int, appLimit: Int, recentAppLimit: Int = 0) -> CommandBarSuggestions {
        CommandBarSuggestions(
            topTags: TopCounts.rank(tagCounts, limit: tagLimit),
            topApps: apps(from: appCounts, limit: appLimit),
            recentApps: apps(from: recentAppCounts, limit: recentAppLimit),
            hasRemoteClips: hasRemoteClips,
            allApps: apps(from: appCounts, limit: appCounts.count, withCounts: true),
            languages: TopCounts.rank(languageCounts, limit: languageCounts.count)
                .map { LanguageCount(name: $0, count: languageCounts[$0] ?? 0) }
        )
    }

    private func apps(from counts: [String: Int], limit: Int, withCounts: Bool = false) -> [SourceApp] {
        TopCounts.rank(counts.filter { appNames[$0.key] != nil }, limit: limit)
            .compactMap { id in appNames[id].map { SourceApp(
                bundleID: id,
                name: $0,
                count: withCounts ? counts[id] ?? 0 : 0
            ) } }
    }
}
