# Fix Pesto problems

## Paste does nothing, or only copies
Pesto needs the **Accessibility** permission to paste into other apps. In Pesto's own Settings, choose *General* and use
*Open Accessibility Settings…*, make sure Pesto is on, then quit and reopen Pesto. Without it Pesto puts the clip on the
clipboard and shows "Press ⌘V to paste". If you opened Pesto from the disk image or the Downloads folder, move it to
Applications first: the permission and updates need that one installed copy.

## Pesto is switched on in Accessibility, but paste stopped working after an update
macOS can keep the old entry for a copy of Pesto it no longer recognizes, so the switch looks on but does nothing. Open
*System Settings → Privacy & Security → Accessibility*, select Pesto, and remove it with the **−** button. Then quit
Pesto, open it again from Applications, and turn it on when it asks (or use *General → Open Accessibility Settings…*).

## macOS asks for Keychain access after an update
When updating from version 1.0.0 to 1.0.1 or later, macOS asks to confirm access to Pesto's encryption key in your login Keychain. Choose **Always Allow**. The first release was signed with a self-signed identity; releases from 1.0.1 onward are signed with an Apple Developer ID, and macOS preserves access across subsequent updates.

## Nothing new is captured
- macOS may be blocking clipboard reads: *System Settings → Privacy & Security → Paste from Other Apps → Pesto → Allow*.
  The menu bar shows "Clipboard Access Limited — Open Settings…" when this is the case.
- The app you copied from may be on the exclusion list (password managers are). Check *Settings → Privacy → App exclusions*.
- Concealed copies (a password manager's "copy password") are dropped on purpose.

## The shelf shows a blurred history
The history lock is on. Authenticate with Touch ID or your password. Change it in *Settings → Privacy → History lock*.

## "Can't unlock your clipboard history"
Pesto could not find its encryption key in your Keychain (for example after a Keychain reset), or the key it found does
not open your history. Your old history cannot be read without the key. The alert offers three choices:
- *Quit*, if you want to look for the key first (a Keychain or Time Machine backup). Nothing is changed.
- *Start With Empty History*, to continue with a new key and an empty shelf.
- *Restore from Backup…*, to choose a Pesto backup file, enter its passphrase or recovery key and see what it holds. Only
  when you press *Restore* does Pesto replace the history it can no longer read with the backup, in one step. A wrong
  passphrase or *Cancel* changes nothing and brings the alert back.

Starting empty and restoring both delete the history Pesto can no longer read; nothing is deleted before then. Pesto will
not create a new key behind your back.

## Two Pesto icons in the menu bar
Two copies are running (for example one from a download and one from a development build). Quit both from the Terminal
with `pkill -x Pesto`, then open the one you want.

## A shortcut doesn't work
Another app may already use it. *Settings → Shortcuts* shows a conflict warning. Record a
different shortcut. The plain-text shortcut (⌃⌥⌘V) did nothing in one hand test that could not be repeated from the
code; it also needs plain text on the clipboard, and it beeps when there is none. If you can, run
`log stream --predicate 'subsystem == "net.copypesto.pesto" AND category == "hotkey"'` in Terminal, press it, and
include what it prints: "Registered Paste as plain text: status -9878" means another app owns it, and no "Pressed" line
means it never fired.

## Sensitive pictures are not blurred
Picture screening uses your Mac's on-device model, so it works only on a Mac with Apple Intelligence turned on (macOS 27), and it is best-effort: it can miss things. Right-click a clip and choose **Mark as Sensitive** to blur one yourself. Links to adult sites are detected automatically by their address and page title.

## Describe Image isn't offered
It appears only on a Mac with Apple Intelligence turned on, running macOS 27 or later.

## If Pesto quits unexpectedly
Pesto writes the reason to `~/Library/Application Support/net.copypesto.pesto/last-exception.txt` the next time it crashes.
Please include that file and the output of *About → Copy Diagnostics* when you report the problem. For a crash, the
newest Pesto entry under *Console → Crash Reports* helps too. Both are public if you post them in an issue, so read them first.

## Starting over
*Clear History* in the menu bar removes your history (pinned clips are kept; *Settings → Data → Start over → Clear Everything…*
removes them too, and your collections and snippets). To reset every setting, quit Pesto and remove
`~/Library/Preferences/net.copypesto.pesto.plist`.
