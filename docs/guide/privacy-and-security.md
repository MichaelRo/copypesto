# Privacy and security

Pesto's history is sensitive by nature, so it is built to keep it on your Mac, encrypted, and out of sight of anything
that should not see it.

## What Pesto stores
Text, code, links, pictures, files and colors you copy, with the app they came from, the time, and any tags or notes
you add. Text found inside pictures (OCR) is stored so pictures are searchable.

## Where it stays
Your history lives in `~/Library/Application Support/net.copypesto.pesto/` on this Mac. **Pesto uploads nothing itself.** There is no
account, no analytics and no crash reporter. The only third-party code bundled is Sparkle, which installs updates; the
project's build files are checked by a test, and a pre-push hook and a CI check refuse an import of any of eleven well-known analytics SDKs.

The only network requests Pesto makes are:
- **Update checks** (the appcast at copypesto.net), which install only with your approval. When you accept an update, the disk image is downloaded from GitHub (github.com, the project’s release page).
- **Link previews**, when you look at a link card (title and picture of the page you copied). They are off until you turn them on in
  *Settings → Privacy*, because a preview asks the linked site, which sees a request from your Mac (and the page can name an icon and a picture, which are fetched too). Pesto does not fetch links that could carry a secret or trigger something (reset and verification links, links with a token, code or signature in them, signed download links, and links to shared documents such as Google Docs, Notion or Figma, where the address is the permission), addresses on your own Mac or network, or any link while the history is locked. A GIF download follows a redirect only to an address that passes the same checks. The system's preview loader follows redirects on its own, and Pesto cannot tell when a public name resolves to a private address.
- **The GIF behind a picture you copied from a browser**, under the same switch (off until you turn it on). A browser's Copy Image gives Pesto only the first frame and the picture's address, so Pesto asks that address for the GIF once, so that it can play on the shelf and paste as a GIF. The site sees one request for a picture it already sent your browser. With link previews off, the picture stays a still. While the history is locked it is not fetched at all, so a picture copied then stays a still.
- **Nothing for AI.** Summarize, Translate, Extract, Describe Image, picture screening and Ask Pesto run on your Mac
  with Apple Intelligence and send nothing anywhere.
- **Links you open**: Maps for an address, a carrier's tracking page, or a link inside a clip.
- **Automatic backup**, if you switch it on: an encrypted file written to iCloud Drive or a folder you choose (see
  below). If you choose iCloud Drive, macOS uploads that encrypted file to Apple; Pesto itself sends it nowhere.

## Undo
To let you undo a delete, Pesto keeps the last few deleted clips in memory, still encrypted, and never writes them to disk. Locking the history, *Clear History*, *Clear Everything* and quitting empty that list. Credentials, clips that expire on their own and clips over 4 MB are never kept for undo (a masked card or API key can be undone).

## What Accessibility is used for
Pesto asks for the Accessibility permission so that it can paste for you. It uses it in three ways:
- To press ⌘V in the app you were using, and to write the clip straight into the focused field where an app allows it.
  It checks that the app you meant is still in front before it presses anything.
- Two optional features watch keystrokes while they are on (and the small menu at the cursor, if you turn it on, watches for Escape while it is open): the append shortcut (a second ⌘C) and Paste One by One (each plain
  ⌘V pastes the next clip). Their monitors look at the key and its modifiers and ignore everything else; they do not
  record or store what you type, and they run only while the feature is on.
- Pesto never reads what is in a text field. It asks where the caret or selection is, not what the field holds.

Without the permission, Pesto still keeps your history, and pasting from the shelf copies the clip and tells you to
press ⌘V yourself.

## Encryption
The content of everything you copy, its preview, and the titles, notes and tags you add are encrypted with AES-256-GCM before it is written to disk. The
key is random, created on first launch and kept in your login Keychain for this Mac only; it is never sent anywhere.
A clip's fingerprint, used to spot duplicates, is a keyed hash under that key, so it reveals nothing about the content.

What is not encrypted, so you know: the names of the apps clips came from, when they were copied and how big they are (for a picture, its width and height in pixels); what kind each clip is (text, picture, link and so on), whether it is pinned, how often it was pasted and which collection it is in; which clips are secrets, their category and the masked preview the shelf shows (for a card its last four digits; for a key with a known prefix, such as `ghp_`, that prefix and how many characters it hides; for a JWT, a long random key or a password hash, how many characters it hides; other secrets show only dots or a label); its length in characters, the language of a code clip, its expiry and shortcut slot, and whether it is marked sensitive, flagged adult or came from another device (with the device's identifier and the number that orders it among that device's clips); the names, icons and rules of your collections; colors you copied; and a coarse fingerprint of each picture, used to spot near duplicates.
While the history lock is off, the preview of your latest clip that holds no secret is also kept in a small file only
your user account can read, so the `pesto` command and AppleScript can show it; turning the lock on removes it. Pesto
puts nothing into Spotlight: a version that offered it left an index, and the first launch of this one removes it.
The title of a page behind a link is encrypted along with your own titles, notes and tags, and so are the numeric
vectors used for search by meaning (they describe a clip's topic and can hint at its words).

Backups are encrypted the same way before they are saved anywhere: with a passphrase you choose, or with a random
recovery key alone (a backup is never left unencrypted, and there is no empty passphrase). If you switch on automatic
backup (off by default, per Mac), the file goes to iCloud Drive or a folder you picked, and whatever syncs that folder
sees only encrypted bytes. Pesto has no server of its own that receives it. The recovery key is kept in this Mac's
Keychain so it can be shown again, only after Touch ID or your password.

What that protects: someone who copies your database file or your disk. What it does not protect: someone who is
logged in to your unlocked Mac as you, because your Mac can decrypt the history for you. If you lose the Keychain item
(for example by erasing the Mac), the old history cannot be recovered. Pesto then offers to start with an empty history
rather than silently creating a new key.

## What is never captured
- Anything a password manager marks as concealed or transient (the standard clipboard markers).
- Copies made in apps on the exclusion list: 1Password, Bitwarden, Dashlane, LastPass, Keeper, KeePass-style apps,
  Apple Passwords and Keychain Access, among others. The built-in apps that are installed on this Mac are shown in *Settings → Privacy → App exclusions*, with a count of the rest;
  add your own apps there too, and remove them any time. The built-in list cannot be shortened, but you can allow one
  app for 15 minutes, an hour, four hours or until Pesto quits, as you choose (after Touch ID or your password, unless you confirmed it recently). What
  it marks as concealed meanwhile is kept hidden as a "Credential" and removed when the allowance ends (a day at the latest; pin a clip to keep it).
- A copy made in an excluded app is dropped even after you switch away from it, so a password copied and then
  pasted elsewhere does not slip in.

## Secrets
![A clip whose text is blurred because it is marked sensitive.](../images/sensitive-card.png)

Credit card numbers, API keys, tokens and similar are detected and **masked** on the cards. To read one, click the eye
on the card (or right-click it and choose *Show*): after Touch ID or your password (asked inside the shelf, and not again
for 1, 5, 15 or 60 minutes, as you choose in Settings → Privacy) the text shows until you choose *Hide*, close the shelf, lock the history or cover the clips. Pasting a
clip always pastes the real text.

## Locking your history
![The shelf blurred behind a "History locked" panel with an Unlock with Touch ID button.](../images/history-locked.png)

*Settings → Privacy → History lock* shows a lock screen over a blurred shelf with the Touch ID prompt inside it (or use
your password). The history locks a set time after you last unlocked it. While it is locked, the shelf, the `pesto://`
links, AppleScript, Shortcuts and the Control Center button cannot read or paste your clips; with the lock on,
turning it off, exporting and importing history ask for Touch ID or your password first. Pasting a clip that
contains a secret keeps it off Universal Clipboard and away from other clipboard managers that respect the mark, and removes it from the
clipboard after 30 seconds unless you copied something else by then. History can also be cleared
when you quit or when the screen locks (*Settings → Data*). Decrypted previews are removed from memory when the
history locks.

The lock stops someone at your unattended Mac. It does not stop another program running as you: those programs can read
your files. Pesto encrypts what it stores, but a process running as you on an unlocked Mac is not a threat model any
app can fully defend against.

## Screen sharing and sensitive content (the blur)
Hide during screen sharing is off until you turn it on (*Settings → Privacy*). With it on, clips are blurred while your screen is being shared or mirrored, or while a known sharing app is open. macOS gives apps no way to see that a share is under way, so Pesto watches for a mirrored display, for sharing or recording apps such as Zoom, Teams, FaceTime and OBS, and for the "sharing your screen" bar that Chrome, Firefox, Edge, Brave and Arc show while a page shares your screen or a window; a share of one tab, and shares from Safari, are not seen. For those, choose **Hide Clip Contents** in the menu bar before you share (and **Show Clip Contents** afterwards; a single covered clip also has its own **Show**, in the clip's menu or on the cover), or use the *Hide Clip Contents* action in Shortcuts, where it can have a keyboard shortcut, or as a Focus filter. Links to adult sites are detected on your Mac by their address, and by their page title when link previews are on. Pictures, and the pictures on linked pages, are screened by your Mac's on-device model when Apple Intelligence is on (macOS 27): its safety guardrails refusing a picture is the signal, so it is best-effort and can miss things. Nothing is stored or sent anywhere by this. Matches are blurred, hidden or shown as you choose (*Settings → Privacy*); right-click any clip and choose **Mark as Sensitive** to blur one yourself. Return and a double click paste a blurred clip without showing it; choose **Show** to look at it. After you reveal a blurred clip, the menu offers **Hide Again** or **Mark as Not Sensitive**.

## Exports
*Settings → Data → Import and export → Text history → Export…* writes a plain, **unencrypted** JSON file of your text, code, link and color clips: the first 500 characters of each, the app it came from, the time, and any title, note, tags and pin you added. Clips containing secrets are masked in it. Pictures and files are left out (a picture's text and a file's path would otherwise be in it), but keep the file as private as you would the text it holds.

## The Privacy pane
*Settings → Privacy* opens with what stays on this Mac, shows how many copies Pesto has refused (excluded apps, concealed sources and other devices; counts only, never what was copied) and lets you turn link previews off. **Clear Everything** is in *Settings → Data → Start over*: it removes every clip, pinned ones too, and your collections and snippets, after authenticating.

## Deleting
- *Clear History* (menu bar) removes the last 5 minutes, the last hour, today, or everything except pinned clips, after
  asking you to confirm.
- Deleting a clip removes its previews, its search entry and its file copies, not just the row.
- **What Clear Everything guarantees, and what it does not.** Deleting a row does not overwrite the part of the database
  file it sat in; the bytes stay there, and in the file's write-ahead log, until something else is written over them (we
  measured this on macOS 27: the encrypted text of deleted clips was still in the files after a clear). So after it has
  removed everything, Pesto replaces its encryption key with a new random one. What was encrypted under the old key can
  no longer be opened by anyone, including you. What it cannot reach is anything that was never encrypted: the names of
  the apps clips came from, their times, sizes and kinds, collection names, the masked previews of secrets and color
  values stay in those freed pages until they are reused. A backup file has its own key and is not touched (Clear
  Everything pauses or removes it as you chose). An old copy of your login Keychain in a Time Machine backup or an APFS
  snapshot still holds the old key. If the key cannot be replaced, the clips are still removed and the old key stays.
- Pesto never puts clips into Spotlight.

## Reporting a problem
Found a security or privacy problem? Please report it privately rather than in a public issue: email
security@copypesto.net, or see copypesto.net/security.
