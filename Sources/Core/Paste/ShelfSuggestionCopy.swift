// SPDX-License-Identifier: MIT
import Foundation

public enum ShelfSuggestionCopy {
    public static func shortcutOfferTitle(
        pasteCount: Int,
        keyString: String,
        isPinned: Bool,
        clipTitle: String? = nil
    )
    -> String {
        let subject = quotedSubject(clipTitle)
        if let subject {
            if isPinned {
                return String(
                    localized:
                    "You have pasted \(subject) \(pasteCount) times. Paste it from any app with \(keyString)?"
                )
            }
            return String(
                localized:
                "You have pasted \(subject) \(pasteCount) times. Pin it and paste it from any app with \(keyString)?"
            )
        }
        if isPinned {
            return String(
                localized: "You have pasted this clip \(pasteCount) times. Paste it from any app with \(keyString)?"
            )
        }
        return String(
            localized:
            "You have pasted this clip \(pasteCount) times. Pin it and paste it from any app with \(keyString)?"
        )
    }

    public static func dormantTitle(keyString: String, weeks: Int) -> String {
        String(
            localized: "You have not used \(keyString) in \(weeks) weeks. Remove the shortcut? The clip stays pinned."
        )
    }

    public static func reminderTitle(shelfPastes: Int, keyString: String, clipTitle: String? = nil) -> String {
        if let subject = quotedSubject(clipTitle) {
            return String(
                localized:
                "You pasted \(subject) from the shelf \(shelfPastes) times. \(keyString) pastes it from any app."
            )
        }
        return String(
            localized: "You pasted this clip from the shelf \(shelfPastes) times. \(keyString) pastes it from any app."
        )
    }

    private static func quotedSubject(_ clipTitle: String?) -> String? {
        guard let trimmed = clipTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return "\u{201C}\(trimmed)\u{201D}"
    }

    public static func snippetTitle() -> String {
        String(localized: "These clips look alike. Make one snippet with a fill-in for what changes?")
    }

    public static var offNoticeTitle: String {
        String(localized: "Suggestions are off. Turn them back on in Settings, under General.")
    }
}
