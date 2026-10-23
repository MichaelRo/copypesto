// SPDX-License-Identifier: MIT
import Foundation

/// Automatic transformations applied silently to every copied text item at ingest time.
/// Each rule is independently togglable via @AppStorage in Settings → Privacy.
public struct ClipboardRules: Sendable {
    public var stripTrackingParameters: Bool
    public var trimWhitespace: Bool
    public var normalizeLineEndings: Bool
    public var removeDuplicateSpaces: Bool

    public static func fromUserDefaults() -> ClipboardRules {
        from(AppDefaults.store)
    }

    static func from(_ d: UserDefaults) -> ClipboardRules {
        ClipboardRules(
            stripTrackingParameters: d.value(for: Setting.ruleStripTracking),
            trimWhitespace: d.value(for: Setting.ruleTrimWhitespace),
            normalizeLineEndings: d.value(for: Setting.ruleNormalizeLineEndings),
            removeDuplicateSpaces: d.value(for: Setting.ruleRemoveDuplicateSpaces)
        )
    }

    public init(
        stripTrackingParameters: Bool = true,
        trimWhitespace: Bool = false,
        normalizeLineEndings: Bool = true,
        removeDuplicateSpaces: Bool = false
    ) {
        self.stripTrackingParameters = stripTrackingParameters
        self.trimWhitespace = trimWhitespace
        self.normalizeLineEndings = normalizeLineEndings
        self.removeDuplicateSpaces = removeDuplicateSpaces
    }

    /// Apply all enabled rules to a text string. Returns the transformed string.
    public func apply(to text: String) -> String {
        var result = text

        if normalizeLineEndings {
            result = result.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }

        if stripTrackingParameters {
            result = TrackingParameters.removed(from: result)
        }

        if removeDuplicateSpaces {
            // Collapse runs of spaces/tabs (not newlines) to a single space.
            var prev: Character?
            result = result.filter { ch in
                let isSpace = ch == " " || ch == "\t"
                let drop = isSpace && prev == " "
                prev = isSpace ? " " : ch
                return !drop
            }
        }

        if trimWhitespace {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}
