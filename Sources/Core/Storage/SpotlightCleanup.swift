// SPDX-License-Identifier: MIT
import CoreSpotlight
import Foundation

public protocol SpotlightIndexRemoving: Sendable {
    func removeDomains(_ domains: [String])
}

public struct SystemSpotlightIndex: SpotlightIndexRemoving {
    public init() {}

    public func removeDomains(_ domains: [String]) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domains) { _ in }
    }
}

/// Pesto no longer puts clips into Spotlight (ADR 0002): the index was the one place clip text was readable outside
/// the app, it reached only clips copied after it was switched on, and results showed the app's name, not the text. An
/// older version may have left an index behind, so the first launch removes it, and the switch it stored.
public enum SpotlightCleanup {
    public static let legacyEnabledKey = "spotlightIndexingEnabled"
    public static let legacyEnabledAtKey = "spotlightIndexingEnabledAt"
    public static let doneKey = Setting.spotlightIndexRemoved.name

    public static func removeIndexOnce(
        defaults: UserDefaults = AppDefaults.store, index: any SpotlightIndexRemoving = SystemSpotlightIndex()
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        index.removeDomains(["\(AppIdentity.bundleID).clips", AppIdentity.legacySpotlightDomain])
        defaults.removeObject(forKey: legacyEnabledKey)
        defaults.removeObject(forKey: legacyEnabledAtKey)
        defaults.set(true, forKey: doneKey)
    }
}
