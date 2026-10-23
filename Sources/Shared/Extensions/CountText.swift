// SPDX-License-Identifier: MIT
import Foundation

/// Counts as words ("1 clip", "2 clips"), with the plural forms in the String Catalog, so no sentence says "1 clips"
/// and
/// a translation can pick its own forms.
enum CountText {
    static func clips(_ count: Int) -> String {
        String(localized: "\(count) clips")
    }

    static func collections(_ count: Int) -> String {
        String(localized: "\(count) collections")
    }

    static func deletions(_ count: Int) -> String {
        String(localized: "\(count) deletions")
    }

    static func alreadyHere(_ count: Int) -> String {
        String(localized: "\(count) were already here.")
    }

    /// "5 clips, 2 collections and 1 deletion", joined the way the language does it.
    static func list(_ parts: [String]) -> String {
        ListFormatter.localizedString(byJoining: parts)
    }
}
