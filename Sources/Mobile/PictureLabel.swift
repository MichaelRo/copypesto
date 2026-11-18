// SPDX-License-Identifier: MIT
import Foundation

/// What VoiceOver says for a picture in the detail: that it is a picture, its size, and the start of the text read in
/// it, if any.
enum PictureLabel {
    static let textLimit = 200

    static func make(width: Int?, height: Int?, recognizedText: String?) -> String {
        var parts = [String(localized: "Picture")]
        if let width, let height, width > 0, height > 0 {
            parts[0] = String(localized: "Picture, \(width) by \(height)")
        }
        let text = recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            let shown = text.count > textLimit ? String(text.prefix(textLimit)) + "\u{2026}" : text
            parts.append(String(localized: "Text in the picture: \(shown)"))
        }
        return parts.joined(separator: ". ")
    }
}
