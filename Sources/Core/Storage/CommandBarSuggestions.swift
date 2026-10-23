// SPDX-License-Identifier: MIT
import Foundation

public struct SourceApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct CommandBarSuggestions: Sendable, Equatable {
    public let topTags: [String]
    public let topApps: [SourceApp]
    /// The apps copied from most over the last seven days, most copied first (the shelf's app chips).
    public let recentApps: [SourceApp]
    public let hasRemoteClips: Bool

    public static let empty = CommandBarSuggestions(topTags: [], topApps: [])

    public init(
        topTags: [String], topApps: [SourceApp], recentApps: [SourceApp] = [], hasRemoteClips: Bool = false
    ) {
        self.topTags = topTags
        self.topApps = topApps
        self.recentApps = recentApps
        self.hasRemoteClips = hasRemoteClips
    }
}

/// The app chips beside the collections: the app in front, then the few others copied from most lately. Pesto itself is
/// never one (its own windows are often in front while the shelf opens).
public enum AppChips {
    public static let recentLimit = 3
    public static let recentDays = 7

    public static func chips(
        frontmost: SourceApp?, recent: [SourceApp], ownBundleID: String?, recentLimit: Int = AppChips.recentLimit
    )
    -> [SourceApp] {
        let front = frontmost.flatMap { $0.bundleID == ownBundleID ? nil : $0 }
        let others = recent.filter { $0.bundleID != ownBundleID && $0.bundleID != front?.bundleID }
        // With no app in front (Pesto's own menu or Settings was), a fourth recent app stands in, so the row is never
        // short.
        return (front.map { [$0] } ?? []) + others.prefix(front == nil ? recentLimit + 1 : recentLimit)
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
    private var hasRemoteClips = false
    private let recentSince: Date?

    /// `recentSince` is the start of the window that makes an app "recent"; without it there are no recent apps.
    public init(recentSince: Date? = nil) {
        self.recentSince = recentSince
    }

    public mutating func add(
        tags: [String], bundleID: String?, appName: String?, isRemote: Bool = false, timestamp: Date? = nil
    ) {
        if isRemote { hasRemoteClips = true }
        for tag in tags {
            tagCounts[tag, default: 0] += 1
        }
        guard let bundleID else { return }
        appCounts[bundleID, default: 0] += 1
        if let recentSince, let timestamp, timestamp >= recentSince { recentAppCounts[bundleID, default: 0] += 1 }
        if appNames[bundleID] == nil, let appName { appNames[bundleID] = appName }
    }

    public func suggestions(tagLimit: Int, appLimit: Int, recentAppLimit: Int = 0) -> CommandBarSuggestions {
        CommandBarSuggestions(
            topTags: TopCounts.rank(tagCounts, limit: tagLimit),
            topApps: apps(from: appCounts, limit: appLimit),
            recentApps: apps(from: recentAppCounts, limit: recentAppLimit),
            hasRemoteClips: hasRemoteClips
        )
    }

    private func apps(from counts: [String: Int], limit: Int) -> [SourceApp] {
        TopCounts.rank(counts.filter { appNames[$0.key] != nil }, limit: limit)
            .compactMap { id in appNames[id].map { SourceApp(bundleID: id, name: $0) } }
    }
}
