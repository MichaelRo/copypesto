// SPDX-License-Identifier: MIT
import Foundation

/// What the Settings search field looks through. `anchor` is text that appears in the pane's own source, so a test can
/// tell when a setting is renamed or removed and the index has fallen behind.
public struct SettingsIndexEntry: Sendable, Equatable {
    public let title: String
    public let pane: String
    public let keywords: [String]
    public let anchor: String
}

public enum SettingsIndex {
    /// The card of installed clipboard managers in Settings, Data; the shelf banner's Choose… scrolls to it.
    public static let foundOnThisMacTitle = "Found on this Mac"

    public static func search(_ query: String) -> [SettingsIndexEntry] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let ranked: [(hits: Int, offset: Int)] = entries.indices.compactMap { offset in
            let entry = entries[offset]
            let title = fold(entry.title)
            let haystack = ([title, fold(entry.pane)] + entry.keywords.map(fold)).joined(separator: " ")
            guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
            return (words.count(where: { title.contains($0) }), offset)
        }
        return ranked.sorted { ($0.hits, -$0.offset) > ($1.hits, -$1.offset) }.map { entries[$0.offset] }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func entry(
        _ title: String,
        _ pane: String,
        _ anchor: String,
        _ keywords: String...
    )
    -> SettingsIndexEntry {
        SettingsIndexEntry(
            title: title,
            pane: pane,
            keywords: keywords,
            anchor: anchor
        )
    }

    public static let entries: [SettingsIndexEntry] = [
        entry(
            "Launch Pesto at login",
            "General",
            "Launch Pesto at login",
            "startup",
            "boot",
            "open when i sign in",
            "menu bar"
        ),
        entry(
            "Menu bar icon",
            "General",
            "Show Pesto in the menu bar",
            "hide icon",
            "status item",
            "menu bar",
            "hidden"
        ),
        entry(
            "Paste from the floating window",
            "General",
            "Paste from the floating window",
            "auto-paste",
            "floating window",
            "tap",
            "click"
        ),
        entry(
            "Save pictures to",
            "General",
            "Save pictures to",
            "save image",
            "downloads",
            "folder",
            "picture"
        ),
        entry(
            "Keep clips for a number of days",
            "Data",
            "Keep clips for",
            "retention",
            "history length",
            "delete old",
            "days"
        ),
        entry("Keep up to a number of clips", "Data", "Keep at most", "retention", "maximum", "limit", "storage"),
        entry("Clear history on quit", "Data", "Clear history on quit", "privacy", "delete on exit"),
        entry(
            "Clear history when the screen locks",
            "Data",
            "Clear history when the screen locks",
            "privacy",
            "lock"
        ),
        entry("Play sounds on copy and paste", "General", "Play sounds on copy and paste", "audio", "feedback", "tink"),
        entry(
            "Open a small menu at the cursor",
            "General",
            "Open a small menu at the cursor",
            "quick menu",
            "caret",
            "text field",
            "full shelf"
        ),
        entry(
            "Check for updates automatically",
            "General",
            "Check for updates automatically",
            "updates",
            "sparkle",
            "version"
        ),
        entry("Version and build", "General", "AppVersion", "about", "version", "build"),
        entry(
            "Appearance: light, dark or system",
            "Appearance",
            "Appearance",
            "theme",
            "dark mode",
            "light mode",
            "dark"
        ),
        entry(
            "Theme",
            "Appearance",
            "Theme",
            "basil",
            "parmesan",
            "pine nut",
            "mortar",
            "marble",
            "colors",
            "shelf tint"
        ),
        entry("Accent color", "Appearance", "Accent color", "colour", "tint", "highlight"),
        entry(
            "Theme in dark mode", "Appearance", "Use another theme in dark mode",
            "dark theme", "night", "light and dark", "per mode"
        ),
        entry(
            "App icon",
            "Appearance",
            "App icon",
            "dock",
            "basil",
            "parmesan",
            "pine nut",
            "mortar",
            "garlic",
            "gold",
            "logo"
        ),
        entry(
            "Shelf position", "Appearance", "Shelf position",
            "bottom", "top", "notch", "under the notch", "menu bar", "where the shelf opens"
        ),
        entry("Card size", "Appearance", "Card size", "compact", "large", "standard", "bigger", "smaller"),
        entry("Open the shelf shortcut", "Shortcuts", "Open the shelf", "hotkey", "keyboard", "command shift v"),
        entry("Paste as plain text shortcut", "Shortcuts", "Paste as plain text", "hotkey", "formatting", "plain text"),
        entry("Quick paste shortcut", "Shortcuts", "Paste the previous clip", "hotkey", "previous"),
        entry(
            "Floating window shortcut", "Shortcuts", "Show or hide the floating window",
            "hotkey", "keyboard", "floating window"
        ),
        entry("Pause capturing shortcut", "Shortcuts", "Pause or resume capturing", "hotkey", "keyboard", "stop"),
        entry(
            "Hide clip contents shortcut", "Shortcuts", "Hide or show clip contents",
            "hotkey", "keyboard", "screen share", "blur"
        ),
        entry("Pinned clip shortcuts", "Shortcuts", "Pinned clip shortcuts", "control 1", "slots", "hotkey"),
        entry(
            "Shelf keys",
            "Shortcuts",
            "Shelf keys",
            "keyboard",
            "arrows",
            "return",
            "escape",
            "command k",
            "navigate"
        ),
        entry(
            "Accessibility access",
            "General",
            "Accessibility",
            "permission",
            "paste into other apps",
            "direct paste"
        ),
        entry(
            "Paste access (clipboard permission)",
            "General",
            "Open Pasteboard Settings",
            "pasteboard",
            "privacy",
            "allow"
        ),
        entry(
            "App exclusions",
            "Privacy",
            "App exclusions",
            "password manager",
            "1password",
            "never capture",
            "ignore apps"
        ),
        entry(
            "History lock (Touch ID)",
            "Privacy",
            "History lock",
            "touch id",
            "biometric",
            "password",
            "lock",
            "privacy"
        ),
        entry(
            "Hide contents during screen sharing",
            "Privacy",
            "Hide contents during screen sharing",
            "zoom",
            "presenting",
            "mirror"
        ),
        entry(
            "Ask for Touch ID again after",
            "Privacy",
            "Ask for Touch ID again after",
            "touch id",
            "password",
            "reveal",
            "show hidden",
            "remember",
            "how often",
            "lock after",
            "lock timeout",
            "idle"
        ),
        entry(
            "Keep copies from other devices",
            "Privacy",
            "Keep copies from other devices",
            "universal clipboard",
            "iphone",
            "ipad",
            "handoff",
            "another mac",
            "icloud"
        ),
        entry(
            "Sensitive content filter",
            "Privacy",
            "Sensitive content",
            "blur",
            "hide",
            "show",
            "nsfw",
            "adult",
            "explicit",
            "content filter",
            "filter"
        ),
        entry(
            "Strip URL tracking parameters",
            "Data",
            "Strip URL tracking parameters",
            "utm",
            "sanitize",
            "sanitise",
            "links"
        ),
        entry(
            "Trim whitespace",
            "Data",
            "Trim spaces at the start and end",
            "sanitize",
            "sanitise",
            "spaces",
            "leading"
        ),
        entry(
            "Normalize line endings",
            "Data",
            "Use one kind of line break",
            "sanitize",
            "sanitise",
            "crlf",
            "windows"
        ),
        entry("Collapse duplicate spaces", "Data", "Collapse duplicate spaces", "sanitize", "sanitise", "spaces"),
        entry("Double-press ⌘C to append", "Shortcuts", "Double-press ⌘C", "merge", "join", "copy twice"),
        entry("Encryption", "Privacy", "Encryption", "key", "keychain", "secure"),
        entry(
            "What stays on this Mac",
            "Privacy",
            "Your clips stay on this Mac",
            "privacy dashboard",
            "what pesto stores",
            "encryption key",
            "secrets masked",
            "blocked"
        ),
        entry("Load link previews", "Privacy", "Load link previews", "network", "internet", "privacy", "fetch"),
        entry("Clear Everything", "Data", "Clear Everything", "panic", "wipe", "delete all", "start over", "pinned"),
        entry(
            "Collections",
            "Collections",
            "Collections",
            "smart collection",
            "group",
            "folders",
            "suggest"
        ),
        entry(
            "Snippets", "Snippets", "Add Snippet",
            "template", "placeholder", "date", "time", "text expander", "boilerplate", "canned"
        ),
        entry(
            "Apple Intelligence", "General", "Apple Intelligence",
            "on-device", "model", "summarize", "translate", "extract", "describe image", "ask pesto", "ai", "turn off"
        ),
        entry("Export clips", "Data", "Export", "backup", "save", "json", "history"),
        entry(
            foundOnThisMacTitle, "Data", "Found on this Mac",
            "installed", "detected", "maccy", "paste app", "alfred", "switch", "migrate", "bring my history"
        ),
        entry(
            "Import from another app", "Data", "Another app",
            "paste app", "raycast", "textexpander", "alfred", "snippets file", "switch", "migrate", "pinboards",
            "other file",
            "csv", "json", "text file", "unknown app", "generic"
        ),
        entry(
            "Backup", "Data", "Set Up Backup",
            "encrypted", "restore", "recovery key", "passphrase", "icloud", "icloud drive", "automatic", "keep updated",
            "work mac", "turn off", "folder", "move to another mac", "back up now"
        ),
        entry("Rebuild search index", "Data", "Rebuild search index", "semantic", "search", "embeddings"),
        entry("Activity insights", "Data", "Insights", "statistics", "charts", "most pasted", "sources")
    ]
}
