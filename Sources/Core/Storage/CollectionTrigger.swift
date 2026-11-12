// SPDX-License-Identifier: MIT
import Foundation

/// Which collection the shelf opens on for the app in front: the one whose trigger names that app, else none (All).
public enum CollectionTrigger {
    /// An app with no bundle identifier, or none in front, matches nothing. Matching `nil` against a collection's own
    /// `nil` trigger picked the first collection that had none (nearly every one), so the shelf opened on a random
    /// collection and a clip copied since was not on it.
    public static func collectionID(for bundleID: String?, in pinboards: [Pinboard]) -> UUID? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return pinboards.first { $0.triggerBundleID == bundleID }?.id
    }
}
