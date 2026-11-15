// SPDX-License-Identifier: MIT
import Foundation

/// The bounds of the widget snapshot (ADR 0052): enough for the large family, small enough that what sits in the app
/// group stays small and the widget opens it well inside its memory limit.
public enum WidgetSnapshotPolicy {
    /// The large family shows six; two more cover a clip that leaves before the next write.
    public static let maxClips = 8
    public static let maxPreviewCharacters = 200
    public static let maxLinkPartCharacters = 120
    public static let maxSourceCharacters = 60
    public static let thumbnailMaxPixel = 240
    public static let maxThumbnailBytes = 24 * 1024
    public static let maxThumbnailTotalBytes = 160 * 1024
    /// Thumbnails grow by a third as base64 in the JSON: 160 KB of them and eight clips of text stay under this.
    public static let maxFileBytes = 256 * 1024
    /// How many of the newest clips are looked at to find the ones that may be shown.
    public static let scanLimit = 60
    /// How long the app waits after a change to the history before it writes the snapshot again.
    public static let rewriteDelay: Duration = .seconds(1)
}
