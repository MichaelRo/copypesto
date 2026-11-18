// SPDX-License-Identifier: MIT
import Foundation

/// What a tap on a widget tile does (ADR 0052), chosen in the widget's configuration as "When a clip is tapped".
public enum WidgetTapAction: String, CaseIterable, Codable, Sendable {
    case copy
    case openInPesto
    case openClip
}

/// The tile's tap: copy in place, from the snapshot's whole text, without opening Pesto; or a widget link the app acts
/// on. Long press is not offered: iOS keeps it for the widget's own menu.
public enum WidgetTap: Equatable, Sendable {
    case copyInPlace(UUID)
    case link(URL)

    public static func decide(for clip: WidgetClip, action: WidgetTapAction, copiesInPlace: Bool) -> WidgetTap {
        switch action {
        case .copy where copiesInPlace && clip.fullText != nil:
            .copyInPlace(clip.id)
        case .copy:
            .link(WidgetLink.url(for: clip.id))
        case .openInPesto:
            .link(WidgetLink.url(for: clip.id, action: .show))
        case .openClip:
            .link(WidgetLink.url(for: clip.id, action: clip.kind == .url ? .open : .show))
        }
    }

    /// The web address a link clip opens: its whole text read as one `http` or `https` URL with a host, and nothing
    /// else (no `javascript:`, `file:`, another app's scheme or text around it).
    public static func webURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty, components.user == nil,
              components.password == nil else { return nil }
        return components.url
    }
}
