// SPDX-License-Identifier: MIT

/// What became of asking for a clip to be made a snippet in place (ADR 0075).
public enum SnippetConversion: Equatable, Sendable {
    case converted
    /// The text holds no `{{placeholder}}`, so it would be only a pinned clip.
    case needsPlaceholder
    /// A secret, a clip still being judged, or one that is not text.
    case notConvertible
    case missing
}
