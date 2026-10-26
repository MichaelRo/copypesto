// SPDX-License-Identifier: MIT
import Foundation

public enum ShelfSuggestionCopy {
    public static func shortcutOfferTitle(pasteCount: Int, keyString: String, isPinned: Bool) -> String {
        let timesText = pasteCount == 1 ? "1 time" : "\(pasteCount) times"
        if isPinned {
            return String(localized: "You have pasted this clip \(timesText). Paste it from any app with \(keyString)?")
        } else {
            return String(
                localized: "You have pasted this clip \(timesText). Pin it and paste it from any app with \(keyString)?"
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
        let weeksText = weeks == 1 ? "1 week" : "\(weeks) weeks"
        return String(
            localized: "You have not used \(keyString) in \(weeksText). Remove the shortcut? The clip stays pinned."
        )
    }

    public static func reminderTitle(shelfPastes: Int, keyString: String) -> String {
        let timesText = shelfPastes == 1 ? "1 time" : "\(shelfPastes) times"
        return String(
            localized: "You pasted this clip from the shelf \(timesText). \(keyString) pastes it from any app."
        )
    }

    public static func snippetTitle(pasteCount: Int) -> String {
        let timesText = pasteCount == 1 ? "1 time" : "\(pasteCount) times"
        return String(localized: "You have pasted this clip \(timesText). Make it a snippet?")
    }

    public static var offNoticeTitle: String {
        String(localized: "Suggestions are off. Turn them back on in Settings, under General.")
    }
}
