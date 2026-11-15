// SPDX-License-Identifier: MIT
import Foundation

/// Which clips a widget shows, chosen in its configuration (ADR 0052). A collection is not offered: the snapshot does
/// not carry collections, and a widget must not read more than the snapshot.
public enum WidgetClipSource: String, CaseIterable, Codable, Sendable {
    case recent
    case pinned
}
