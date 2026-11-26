// SPDX-License-Identifier: MIT
import Foundation

/// The bounds of the widget snapshot (ADR 0052): enough for the large family, small enough that what sits in the app
/// group stays small and the widget opens it well inside its memory limit.
public enum WidgetSnapshotPolicy {
    /// The large family shows six; two more cover a clip that leaves before the next write.
    public static let maxClips = 8
    public static let maxPinned = 6
    public static let maxPreviewCharacters = 200
    /// A text, code, link or color clip up to this size carries its whole text, so a tile can copy it in place; a
    /// longer one is copied by opening Pesto.
    public static let maxFullTextBytes = 4 * 1024
    public static let maxFullTextTotalBytes = 32 * 1024
    public static let maxLinkPartCharacters = 120
    public static let maxSourceCharacters = 60
    public static let thumbnailMaxPixel = 240
    public static let maxThumbnailBytes = 24 * 1024
    public static let maxThumbnailTotalBytes = 160 * 1024
    /// JSON escapes a control character as six bytes and base64 grows a thumbnail by a third: the fullest snapshot the
    /// bounds allow (`WidgetSnapshotSelectionTests`) still fits. With every collection full of clips no list shares it
    /// measured 1,099,583 bytes, over the 512 KB of ADR 0052; this bound leaves it a third to spare (ADR 0060).
    public static let maxFileBytes = 1536 * 1024
    /// How many of the newest clips, and of the newest pinned ones, are looked at to find the ones that may be shown.
    public static let scanLimit = 60
    /// The first collections in Pesto's order that a widget may be set to (ADR 0060); each carries at most `maxClips`.
    public static let maxCollections = 24
    public static let maxCollectionNameCharacters = 60
    public static let maxSymbolNameCharacters = 60
    /// How many of the newest clips a smart collection's rules are matched against.
    public static let smartScanLimit = 300
    /// How many of a plain collection's newest members (by last use) are put in its order, so a rewrite never opens
    /// the sealed metadata of a whole large collection: a clip placed by hand but older than these is not on the
    /// widget, while Pesto and its keyboard still show it (ADR 0060, lowered from 300 by ADR 0076).
    public static let collectionScanLimit = 60
    /// How long the app waits after a change to the history before it writes the snapshot again.
    public static let rewriteDelay: Duration = .seconds(1)
    /// How long a tile that copied in place says Copied.
    public static let copiedFeedback: TimeInterval = 2
}
