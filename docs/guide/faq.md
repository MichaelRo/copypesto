# FAQ

## Is Pesto free?

Yes. There are no paid tiers and every feature is available to everyone.

## Does it sync between my Macs?

No. Your history stays on the Mac it was copied on. You can back it up to one
encrypted file and restore that file on another Mac (*Settings → Data → Backup*).

## Can I hide Pesto's icon from the menu bar?

Yes: *Settings → General → Show Pesto in the menu bar*. Then ⌘⇧V (or the
shortcut you chose) opens the shelf, and opening Pesto again from Applications shows Settings, so you can bring the icon
back.

## Can I turn a shortcut off?

Yes. Every shortcut in *Settings → Shortcuts* has a menu at the end of its row with *Turn Off*, and *Reset to Default*
brings the default back. Pesto refuses a combination macOS already uses, and says on the row when another app holds one.

## Is it on the Mac App Store?

No. Pesto is not on the Mac App Store.

Mac App Store apps run in a sandbox that prohibits monitoring the clipboard in the background while other applications are active. Pasting clips directly into the frontmost app also requires Accessibility access, which App Store apps cannot use for keystroke synthesis.

Pesto is distributed directly and notarized by Apple so macOS Gatekeeper accepts it without sandbox limitations.

## Does Pesto send my clipboard anywhere?

Pesto does not upload your history. The few requests it makes are listed in
[Privacy and security](privacy-and-security.md): update checks (and the download, from GitHub, when you accept one),
link previews, which ask the linked site for its title and picture, and the same for the GIF behind a picture copied from a browser (both are off until you turn them on in *Settings → Privacy*),
links you open, such as Maps or a carrier's tracking page, and the optional backup file. If you pick iCloud Drive for
the backup, macOS uploads that encrypted file for you.

## Will it capture my passwords?

Not from password managers: concealed copies are dropped and the common managers are
excluded. Anything else that looks like a card number, key or token is masked on screen. A password copied on its own,
with no label, can look like ordinary text and may not be masked, so copy passwords from a password manager.

## How much space does it use?

By default Pesto keeps one month of clips, up to 5,000 of them. Change this in
*Settings → Data* (*Keep clips for* and *Keep at most*). Pinned clips are kept.

## What happens to a very large copy?

Pesto keeps text up to 10 MB and pictures up to 100 MB. A file copied in Finder is kept as its location, whatever its size. A bigger copy is
not saved, and the shelf says so (the message stays for two minutes, or until you dismiss it). A copy near the limit takes a moment to process. Masking of secrets
looks at the whole copy.

## Can I move over from another clipboard manager?

Yes. After setup, Pesto offers once to bring over the history of a clipboard manager it finds on your Mac. There are
importers for Paste, Maccy, Alfred, CleanClip, PasteNow, CopyClip, PastePal, Pastebot, Clipy, Flycut and Unclutter, and
*Other File…* reads a CSV, JSON or text file from almost any other manager. See
[Moving from Paste](moving-from.md#moving-from-paste),
[Moving from Maccy or Alfred](moving-from.md#moving-from-maccy-or-alfred),
[Moving from other clipboard apps](moving-from.md#moving-from-other-clipboard-apps) and
[Moving from an app that is not listed](moving-from.md#moving-from-an-app-that-is-not-listed).

## Which macOS versions?

macOS 15 and later. On-device AI needs Apple Intelligence on macOS 26 or later; Describe Image
and picture screening need macOS 27.

## How do I uninstall it?

Quit Pesto, drag it to the Trash, and optionally delete
`~/Library/Application Support/net.copypesto.pesto/` and `~/Library/Preferences/net.copypesto.pesto.plist`. If you installed with Homebrew, `brew uninstall --cask pesto` keeps your settings and history; `brew uninstall --cask --zap pesto` deletes them too (the Keychain key stays behind). To remove
the keys, search Keychain Access for `net.copypesto.pesto` and delete what it finds: the encryption key
(`net.copypesto.pesto.blobKey`), the device ID (`net.copypesto.pesto.deviceID`) and, if you set up backup, the backup key (`net.copypesto.pesto.backupKey`). Backup
files you saved stay where you put them until you delete them.
