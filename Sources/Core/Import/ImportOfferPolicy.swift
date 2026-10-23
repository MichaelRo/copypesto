// SPDX-License-Identifier: MIT
import Foundation

/// Which installed apps to offer to import from: once, after setup, and never again after the person has answered. They
/// come in the order of the import list, which puts Paste first (it has pinboards to bring), then Maccy (pins), then
/// Alfred (history only).
public enum ImportOfferPolicy {
    /// The most apps the banner names in full; with more it names the first two and counts the rest, so it stays a
    /// line.
    public static let namedInFull = 3

    public static func sources(installed: [ImportSource], alreadyOffered: Bool, hasOnboarded: Bool) -> [ImportSource] {
        guard hasOnboarded, !alreadyOffered else { return [] }
        return ImportSource.allCases.filter { installed.contains($0) }
    }

    public struct BannerNames: Equatable, Sendable {
        public let shown: [String]
        public let more: Int
    }

    public static func bannerNames(for sources: [ImportSource]) -> BannerNames {
        guard sources.count > namedInFull else { return BannerNames(shown: sources.map(\.name), more: 0) }
        let shown = sources.prefix(2).map(\.name)
        return BannerNames(shown: shown, more: sources.count - shown.count)
    }
}
