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
    /// bounds allow (`WidgetSnapshotSelectionTests`) still fits.
    public static let maxFileBytes = 512 * 1024
    /// How many of the newest clips, and of the newest pinned ones, are looked at to find the ones that may be shown.
    public static let scanLimit = 60
    /// How long the app waits after a change to the history before it writes the snapshot again.
    public static let rewriteDelay: Duration = .seconds(1)
    /// How long a tile that copied in place says Copied.
    public static let copiedFeedback: TimeInterval = 2
}
