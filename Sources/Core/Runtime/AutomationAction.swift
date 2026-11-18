// SPDX-License-Identifier: MIT
public enum AutomationAction: Equatable, Sendable {
    case open, list, search, paste, pin, collection, clear, summary, clip

    /// `pesto://<host>`. `pinboard` is the deprecated name of `collection` (ADR 0007); `clip` is a widget's link to
    /// one clip (`WidgetLink`, ADR 0052 and 0059).
    public init?(host: String?) {
        switch host {
        case "open": self = .open
        case "list": self = .list
        case "search": self = .search
        case "paste": self = .paste
        case "pin": self = .pin
        case "collection", "pinboard": self = .collection
        case "clear": self = .clear
        case "summary": self = .summary
        case WidgetLink.host: self = .clip
        default: return nil
        }
    }
}
