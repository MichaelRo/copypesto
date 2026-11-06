// SPDX-License-Identifier: MIT
import Foundation

/// The text on the search bar's two menu chips. Each sits under a caption of the same word, so at rest it says what
/// the filter is set to, the way a Mac pop-up does (ADR 0025).
public enum FilterMenuLabel {
    public static func format(chosen title: String?) -> String {
        title ?? String(localized: "Any")
    }

    public static func from(chosen names: [String]) -> String {
        switch names.count {
        case 0: String(localized: "Any app")
        case 1: names[0]
        default: "\(names[0]) +\(names.count - 1)"
        }
    }
}
