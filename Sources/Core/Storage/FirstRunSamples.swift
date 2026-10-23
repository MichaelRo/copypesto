// SPDX-License-Identifier: MIT
import Foundation

/// The two clips a new install starts with: a welcome note that says how the shelf works, and a pinned snippet that
/// shows `{{date}}` being filled in. They go through the same import path as any other clip, so they are encrypted,
/// classified and deleted like the rest, and are never added again once deleted.
public enum FirstRunSamples {
    public static let collectionName = "Snippets"
    public static let welcomeTitle = "Welcome to Pesto"
    public static let snippetTitle = "Sample snippet"

    public static func records(shortcut: String, now: Date = .now) -> [PasteImportRecord] {
        [
            record(text: welcomeText(shortcut: shortcut), title: welcomeTitle, pinboard: nil, at: now),
            record(text: snippetText, title: snippetTitle, pinboard: nil, at: now.addingTimeInterval(-60))
        ]
    }

    static func welcomeText(shortcut: String) -> String {
        """
        Welcome to Pesto.

        Everything you copy lands here and stays on this Mac. \(shortcut) opens this shelf from any app: use the \
        arrow keys, press Return to paste, or ⌘1 to ⌘9 to paste one of the first nine clips. Start typing to search.

        Pesto removes old clips after the time you set in Settings. To keep one, right-click it and choose Pin.

        The clip next to this one is a snippet: {{date}} turns into today's date when you paste it.

        Delete this clip when you are done: select it and press ⌫.
        """
    }

    static let snippetText = """
    Hi {{cursor}},

    Thanks for your message on {{date}}. I will get back to you soon.

    Best,
    """

    private static func record(text: String, title: String, pinboard: String?, at date: Date) -> PasteImportRecord {
        PasteImportRecord(
            pinboard: pinboard,
            title: title,
            timestamp: date,
            sourceBundleID: AppIdentity.bundleID,
            representations: [.init(uti: "public.utf8-plain-text", dataBase64: Data(text.utf8).base64EncodedString())]
        )
    }
}
