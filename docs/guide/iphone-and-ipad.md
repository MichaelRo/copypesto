# Pesto on iPhone and iPad

Pesto for iPhone and iPad (iOS 26 or iPadOS 26 and later) keeps an encrypted clipboard history on your device and optionally syncs with your Macs through a folder you choose. Every feature is free, with no account and no subscription.

Because iOS does not let an app watch the clipboard in the background, you add clips deliberately—through Paste, the Share sheet or Shortcuts—and insert them in other apps with AutoFill, the optional Pesto keyboard or widgets.

## Your library
All clips appear as cards in one scrollable grid on iPhone (up to two columns in portrait or three in landscape, narrowing at larger text sizes) and iPad (with a sidebar on wider windows, keyboard shortcuts, drag and drop and multitasking).

- **Search and Ask Pesto.** Search matches the first 500 characters of each clip, titles, notes, tags, link titles and text inside pictures, plus meaning in English for longer queries. Filter by kind, time (*Today*, *Yesterday*, *Last 7 Days*, custom dates), source app, *Sensitive* or *Other Devices*. Tap **Ask** (or press **⌘Return** on iPad) to turn a plain sentence into filters using on-device Apple Intelligence or built-in rules (Describe Image and automatic picture screening require iOS 27 or iPadOS 27 or later).
- **Details, editing and snippets.** Press and hold a clip (or open **Edit Details**) to rename it, add notes or tags, file it into a collection, copy with **Copy As** transforms, convert text into a snippet (**Make Snippet…**) or edit its text (**Edit Text**). Snippets with fill-in questions prompt you right before copying.
- **Pinning and collections.** Pin clips or file them into a collection to keep them past retention limits and **Clear History**, or build rule-based smart collections. On iPhone, touch and hold a collection chip to **Hide Collection** from the chip bar and quick-insert picker on that device (bring it back anytime under *Hidden Collections* in Settings).
- **Tapping a card** copies the clip to your clipboard and shows a confirmation ring (secrets copy marked local-only and expire from the clipboard after two minutes).

## Adding clips
- **Paste button and New Clip.** Tap the **Paste** button in the top bar to capture what is currently on your clipboard, or **+** to write a new note.
- **Add copies when Pesto opens.** Turn this on under *History & Capture* in Settings so Pesto captures what you copied whenever you open it. To skip the iOS paste prompt each time, tap *Allow Paste Without Asking…* and set *Paste from Other Apps* to *Allow* in iOS Settings.
- **Share sheet.** Share text, links or pictures from Safari, Photos or any other app directly to Pesto.
- **Shortcuts, Action Button and Control Center.** Use **Add Clipboard to Pesto** from Shortcuts, the iPhone Action Button, Back Tap or Control Center (see [Automation](automation.md#shortcuts-apples-app)).
- **Drag and drop.** Drag text, links or pictures straight onto the grid from another app, or drag a card out of Pesto.

## Inserting clips in other apps

### AutoFill (text insertion)
AutoFill lets you insert saved text clips, links, colors, snippets and collections into any text field without leaving the app you are in. Pesto AutoFill handles text insertion only and never stores or fills passwords, passkeys or one-time codes.

1. In Pesto, open Settings and choose *Keyboard & AutoFill*.
2. Tap *Set Up Keyboard & AutoFill…*, then *Turn On AutoFill…* (or turn on Pesto under *AutoFill & Passwords* in iOS Settings).
3. Long-press any text field, choose **AutoFill → Pesto**, and pick a clip.

Snippets that fill themselves in (dates, times or UUIDs) expand as you insert them, and snippets that ask for input prompt you right inside AutoFill. Snippets that read the live clipboard run inside the Pesto app.

### The optional Pesto keyboard
Pesto also offers an optional keyboard (`Pesto Keyboard`) so your clips are one tap of the Globe key away in any text field. It is off until you add it in iOS Settings.

- **Numbers and punctuation without Full Access.** Without Full Access, the keyboard provides a numbers-and-punctuation pad and points you to *Settings → General → Keyboard → Keyboards → Pesto* in iOS Settings.
- **Clips with Full Access.** iOS opens the shared encrypted quick-insert file only when **Allow Full Access** is on (under *General → Keyboard → Keyboards → Pesto* in iOS Settings). With Full Access, the keyboard shows **All** (your recent clips, pinned clips, non-prompting snippets and eligible pictures from them), **Pinned**, **Snippets** and your chosen collections.
- **Search.** While using the keyboard, Pesto looks at only the last word before the cursor (in memory, never stored) to surface matching clips. Tap the magnifying-glass key to open Pesto's own search page; its letter keys type only into Pesto's search field and never into the app behind it.
- **Size and behavior.** Under *Keyboard & AutoFill* in Pesto Settings, choose Small, Medium or Large cards, pick which collections appear and choose whether tapping a clip returns to your previous keyboard or stays in Pesto (holding a clip does the opposite). The keyboard's gear button lets you change the card size or jump straight to Pesto Settings.
- **Privacy.** Pesto Keyboard never reads your system clipboard and makes no network requests.

## Home Screen and Lock Screen widgets
Add Pesto's **Recent Clips** widget to your Home Screen (small, medium or large) or Lock Screen.

- Edit a Home Screen widget to choose **Recent**, **Pinned** or a specific **Collection**, and set **When a Clip Is Chosen** to **Copy** (copies short text clips in place without opening Pesto), **Open in Pesto** or **Open the Clip**.
- Lock Screen accessory widgets show a hidden placeholder until you edit that widget and turn on **Show Clips on Lock Screen**; choosing a clip there opens Pesto after unlocking.
- Secrets, clips still being checked, explicit clips and expiring clips never appear in widgets.

## Sync and encrypted backup
- **Folder sync.** Turn on *Sync* under *Extensions & Sync* in Settings and pick a shared folder (such as a folder in iCloud Drive). Pesto syncs through encrypted per-device logs with no server and no account. Because deleting a clip removes it on every synced device, sync is not a backup.
- **Encrypted backups by hand.** Open *Backup* under *Data* in Settings to run *Back Up Now…* or *Restore from Backup…* via Files. Each `.pestobackup` file is encrypted with a strong passphrase or your recovery key, and works across iPhone, iPad and Mac (settings stay on each device).

## Locking and privacy
- **Face ID History Lock.** Turn on *Lock History with Face ID* (or passcode) under *Privacy* in Settings. Widgets, AutoFill and Pesto Keyboard keep showing your quick-insert clips while the history is locked unless you turn off *Allow in Widgets and Keyboard while locked*.
- **Clear History.** Under *Data* in Settings, **Clear History** deletes unpinned clips that are not filed in a collection, after confirmation.
- **Screen capture.** Turn on *Hide clips while the screen is recorded or shared* under *Privacy* in Settings to blur your clips automatically during screen recording or sharing.

## What iPhone and iPad do without
Because iOS and iPadOS sandboxing works differently from macOS, the iPhone and iPad app does not include:
- background clipboard watching or global hotkeys;
- automatic pasting directly into another app (use AutoFill, Pesto Keyboard or copy-and-paste instead);
- importers for other Mac clipboard managers (import on your Mac, then sync or restore a backup);
- rich-text (RTF) snippet expansion or SVG rasterization.
