// SPDX-License-Identifier: MIT
import Foundation

/// How the person handed a clip to Pesto on an iPhone or iPad. Kept only on the device that made the clip, in its
/// sealed metadata, and never in a sync record or a backup (ADR 0049); a Mac copy has none.
public enum CaptureMethod: String, Codable, Sendable, CaseIterable {
    case paste
    case note
    case share
    case drop
    case shortcut
}
