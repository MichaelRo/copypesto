// SPDX-License-Identifier: MIT
import Foundation

public enum ShelfSuggestionCopy {
    public static func shortcutOfferTitle(pasteCount: Int, keyString: String, isPinned: Bool) -> String {
        if isPinned {
            String(localized: "You have pasted this clip \(pasteCount) times. Paste it from any app with \(keyString)?")
        } else {
            String(
                localized:
                "You have pasted this clip \(pasteCount) times. Pin it and paste it from any app with \(keyString)?"
            )
        }
    }

    public static func shortcutOfferButton(isPinned: Bool, keyString: String) -> String {
        if isPinned {
            String(localized: "Use \(keyString)")
        } else {
            String(localized: "Pin with \(keyString)")
        }
    }

    public static func dormantTitle(keyString: String, weeks: Int) -> String {
        String(
            localized: "You have not used \(keyString) in \(weeks) weeks. Remove the shortcut? The clip stays pinned."
        )
    }

    public static func reminderTitle(shelfPastes: Int, keyString: String) -> String {
        String(
            localized: "You pasted this clip from the shelf \(shelfPastes) times. \(keyString) pastes it from any app."
        )
    }

    public static func snippetTitle(pasteCount: Int) -> String {
        String(localized: "You have pasted this clip \(pasteCount) times. Make it a snippet?")
    }

    public static var offNoticeTitle: String {
        String(localized: "Suggestions are off. Turn them back on in Settings, under General.")
    }
}
