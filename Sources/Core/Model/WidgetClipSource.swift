// SPDX-License-Identifier: MIT
import Foundation

/// Which clips a widget shows, chosen in its configuration: the newest, the pinned ones (ADR 0052), or one collection
/// the snapshot carries (ADR 0060). A collection with no id is one the person has not chosen yet.
public enum WidgetClipSource: Hashable, Codable, Sendable {
    case recent
    case pinned
    case collection(UUID?)
}
