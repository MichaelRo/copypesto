// SPDX-License-Identifier: MIT
import Foundation

/// The one place that decides whether a preview may be stored unencrypted. A colour's preview is the only one kept in
/// the clear (ADR 0002), so what counts as a colour is judged again at the point of storing: whatever filed a clip
/// under `.color` (an import, an old classifier), the text must still be a colour and nothing else.
public enum ColorPreviewPolicy {
    public static let maximumLength = 64

    public static func mayStoreInTheClear(_ preview: String) -> Bool {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength, !trimmed.contains(where: \.isNewline) else {
            return false
        }
        return ContentClassifier.classify(text: trimmed).type == .color
    }

    /// Whether a preview is stored as ciphertext. Every type is sealed except a real colour; a masked (sensitive)
    /// preview is plain by construction and the caller checks that itself.
    public static func sealsPreview(of type: ClipboardType, preview: String) -> Bool {
        guard !preview.isEmpty else { return false }
        return type != .color || !mayStoreInTheClear(preview)
    }
}
