# Changelog

All notable user-facing changes to Pesto are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

## [1.5.0] - 2026-11-08
### Added
- Settings, General: **Install updates automatically**, when Pesto last checked, and a **Check Now** button.
- When a check you start finds an update that installs by itself, a notice under the menu bar says it is ready; click it to restart now.
- While an update is waiting, the menu bar menu and General offer **Restart to Update** and **What's New**.

### Changed
- Pictures wider or taller than a card are shown whole over a blurred copy of themselves, not cropped. ([ADR 0041](decisions/0041-a-picture-fills-the-card-only-near-its-shape.md))

## [1.4.0] - 2026-11-07
### Changed
- The shelf is solid by default. The translucent Liquid Glass look, the earlier default, is an option in Settings, Appearance. ([ADR 0035](decisions/0035-shelf-surface-solid-or-glass.md))
- Short text clips and link hosts lead in prominent sizing; cards covered during screen sharing show clear kind and age badges.
- New backup passphrases need twelve characters and pass a strength check.

### Added
- Copy Recognized Text from any picture clip, in its card menu or hover card.
- Paste As and Copy As turn structured text into formatted JSON and Markdown.
- Paste import keeps Paste boards as collections and imports recent history up to capacity.

## [1.3.0] - 2026-11-05
### Changed
- Search filters: Today and Yesterday are chips; a More menu holds the last 7 and 30 days, the last hours and any recent day. Format and From list every language and app in your history. Ask understands exact dates.
- Typing on the shelf without ⌘F counts every key, including after a pause.
- The clip menu leads with Paste and Paste as Plain Text. The shelf opens on All again after 90 seconds closed.
- A clip in a collection shows when you first copied it, so a paste does not change it.
- Settings: General is grouped into Shelf, Copy and paste and Floating window.

## [1.2.0] - 2026-11-02
### Added
- Multi-device sync through encrypted folders (off by default). ([ADR 0018](decisions/0018-multi-device-sync.md))
- Dedicated importers for eleven clipboard managers, any CSV, JSON or text file, and Raycast snippets.
- Decode JWT from a card; lone emojis and symbols get glyph cards; `{{clipboard}}` and `{{uuid}}` snippet placeholders.

### Changed
- Settings → Data: backup is a switch, *Back up this Mac*, under a line that says your clips stay on this Mac and what the
  backup is doing. The fourth tile shows the time of the last backup, or *Needs you* when the last run could not save.
  *Restore from Backup…* counts what it would add before you confirm. ([ADR 0019](decisions/0019-backup-and-sync-group.md))

## [1.1.0] - 2026-10-28
### Added
- Smart Snippets: fill-ins that Pesto asks for when you paste, and suggestions for look-alike text you paste over several days.
- Shelf app chips show the app icon and open in place on hover.

## [1.0.1] - 2026-10-26
### Changed
- Signed with a Developer ID and notarized.
- Shelf suggestions above the clip grid; refined spacing during search.

## [1.0.0] - 2026-10-23

The first release. Nothing has shipped before, so this lists what Pesto does, not edits to earlier drafts. The early
commit history was condensed into a few commits before the repository went public; this file and `decisions/` record why.

This build is signed with a self-signed identity, not an Apple Developer ID, so macOS asks you to choose *Open Anyway*
once (`docs/guide/getting-started.md`). Check the download against the SHA-256 on the release page.

### Added
- Ask Pesto: a question typed into search is answered from your clips, on your Mac with Apple Intelligence where available, and by plain rules where not. Describe Image gives a picture a description (macOS 27 with Apple Intelligence).
- A GIF copied from Chrome, Arc or Edge plays on its card: Pesto fetches the GIF the browser pointed to when Link Previews are on.
- The disk image shows Pesto, a dotted arrow and Applications; opened from the image or Downloads, Pesto offers to move itself to Applications.
- Save Image to Downloads (⌘S on the focused picture, or the card's menu), Copy As on a colour (HEX, RGB, HSL, SwiftUI, NSColor), and a shelf position setting, Bottom or Top, chosen from two small pictures (Settings, Appearance).
- Paste One by One (⇧⌘P): select clips and press it, and each plain ⌘V in any app pastes the next one. Paste All (⌘P) joins the selected text clips and pastes them at once.
- Undo and redo (⌘Z, ⇧⌘Z) for deletes and changes to clips, collections and snippets, and for imports. A bar offers Undo after a delete. The last 20 actions are kept in memory, still encrypted, and forgotten when you lock, clear or quit.
- Export Collection… in a collection's right-click menu on the shelf, as well as in Settings.
- Import from Maccy, Alfred, CleanClip, PasteNow, CopyClip, PastePal, Pastebot, Clipy, Flycut and Unclutter, next to Paste and snippets files. Each reads a copy of the library, read-only.
- Snippets are edited in the list, with Insert chips and a live preview.
- A pasted secret leaves the clipboard after 30 seconds and stays off Universal Clipboard.
- Hide Clip Contents as a menu-bar item, a Shortcuts action and a Focus filter.
- Turn off any shortcut; three optional shortcuts for the floating window, pausing capture and hiding clip contents; a list of the shelf's keys. A combination macOS already uses is refused.
- A theme for dark mode, if you want one; Show Pesto in the menu bar can be turned off.
- Suggested snippets (starters, and text you paste often); *Import from another app* takes a Raycast snippets export as well as Paste.
- About Pesto is a window in the style of the website.
- Clipboard history shelf (⇧⌘V) with a horizontal row of cards.
- Encrypted backup to one file per Mac (passphrase or recovery key), and restore from any backup file.
- AES-256-GCM encryption at rest of clip content, previews, titles, notes, tags and search vectors.
- Masking of secrets (card numbers, API keys, tokens, password lines); the real text shows only through Show, after Touch ID or the account password.
- Perceptual-hash deduplication for picture clips (Hamming ≤ 5).
- Collections, including smart collections built from rules.
- Three-tier paste: Accessibility direct-write → keystroke synthesis → clipboard replace.
- Onboarding flow with Accessibility and Keychain permission steps.
- Retention policy (configurable; default 30 days).
- Quick-paste-last shortcut (⌥⌘V).
- Paste anywhere: a click on the shelf focuses a clip and a double click or Return pastes it; ⇧Return pastes plain text.
- Themes (Basil, Parmesan, Pine nut, Mortar), each with an app icon; a separate theme for dark mode if you want one.
- One *Ask for Touch ID again after* setting (1, 5, 15 or 60 minutes) for the history lock and every protected action.
- Settings search that takes you to the setting and highlights it; the encrypted backup carries your settings.
- Link previews and the cursor menu are off until you turn them on (Settings, Privacy and General).
- Copy Diagnostics in About: versions, your Mac model and which switches are on, with no clips, for a bug report.

### Known limits
- No sync between Macs and no iOS app: history stays on the Mac. One encrypted backup file per Mac can be restored on another.
- Builds are not signed with an Apple Developer ID yet, so macOS asks you to choose *Open Anyway* the first time.
- The ⌃⌥⌘V plain-text shortcut did not fire in one hand test and is under investigation.
- The cursor menu is for the mouse only: macOS gives a panel that never takes the keyboard no way to read arrow keys.
