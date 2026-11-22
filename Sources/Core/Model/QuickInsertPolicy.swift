// SPDX-License-Identifier: MIT
import Foundation

/// The bounds of the quick-insert set (ADR 0051): a short list an AutoFill extension opens and draws well inside its
/// memory limit, small enough that what sits in the app group stays small.
public enum QuickInsertPolicy {
    public static let maxPinned = 50
    public static let maxSnippets = 50
    public static let maxRecent = 60
    /// The collections the person may choose for the keyboard and AutoFill, and the clips each carries (ADR 0062).
    public static let maxCollections = 12
    public static let maxCollectionClips = 30
    public static let maxCollectionNameCharacters = 40
    /// A longer clip is not offered: inserting a whole document into a text field is not what this is for.
    public static let maxEntryBytes = 32 * 1024
    public static let maxTotalBytes = 256 * 1024
    public static let maxTitleCharacters = 120
    public static let maxSourceCharacters = 60
    public static let thumbnailMaxPixel = 240
    public static let maxThumbnailBytes = 24 * 1024
    /// How many clips of each kind are looked at to find the ones that may be offered.
    public static let scanLimit = 200
    /// Encoding escapes a control character as six bytes (`\u0000`), so even a set of nothing else fits.
    public static let maxFileBytes = 2 * 1024 * 1024
    /// How long the app waits after a change to the history before it writes the set again.
    public static let rewriteDelay: Duration = .seconds(1)
}
