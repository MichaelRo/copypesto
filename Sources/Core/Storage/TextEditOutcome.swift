// SPDX-License-Identifier: MIT
import Foundation

/// What `StorageService.updateText(id:text:)` did with a new text for a clip.
public enum TextEditOutcome: Equatable, Sendable {
    case saved
    case unchanged
    case empty
    case missing
    /// A picture, a file, or a clip still being judged: its content is not text that can be edited.
    case notText

    /// Whether a clip of this kind holds text a person can edit: text, code, a link or a color, once it is judged.
    public static func isEditable(type: ClipboardType, analysisPending: Bool) -> Bool {
        !analysisPending && [.text, .code, .url, .color].contains(type)
    }
}
