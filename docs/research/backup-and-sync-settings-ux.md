# Keep backup and sync separate, but name them apart

> Outcome: [ADR 0019](../../decisions/0019-backup-and-sync-group.md) takes the report's rules (different verbs, a "this is not" sentence each, secrets out by default, no Macs list) but joins the two switches in one group with one shared "where" row, because two sections would repeat the folder and the secrets choice.

**Recommendation: keep one Settings → Data page with two clearly different sections, Backup and Sync, and remove the "Keep it up to date automatically" toggle from Backup.** The research found no industry convergence on a combined or split layout. It did find a consistent rule: vendors define the two ideas separately and state the delete consequence in the same sentence. Dropbox says a backup is an extra copy, while with sync "when a file is deleted from one location, it is deleted from all devices that are linked to it" ([Dropbox](https://www.dropbox.com/resources/difference-between-backup-and-sync)). The owner's worry holds up: an auto-updating toggle under Backup is what makes a backup read as sync. The fix is wording and structure, not merging the cards. Each section gets a distinct verb, its own one-line "this is not" sentence, and a status line. Both start Off on every Mac, and secrets stay out of sync unless the user opts in. Evidence quality is uneven. Many sources below are help pages read through search summaries, and several expected primary sources (NN/g, most of the HIG, Time Machine status strings) were never obtained. Those are flagged as gaps. Marked "Inference" means my own synthesis.

## What the evidence supports

**Separate concepts are the verified norm; one layout is not.** None of the surveyed apps has a combined "Backup and Sync" control. Day One, Bear, Things and Obsidian treat sync as an account or toggle and backup as snapshots, export or trash, while their docs repeatedly say sync is not a backup ([Day One](https://dayoneapp.com/guides/day-one-ios/backup-and-sync-options-on-ios-and-macos/), [Bear](https://blog.bear.app/2018/11/how-to-back-up-your-bear-notes/), [Obsidian](https://obsidian.md/help/sync/settings)). Apple's Photos page ends with "keep backup copies of your library" because deletes propagate ([Apple Support](https://support.apple.com/en-ae/HT204264)). Google merged two clients into Drive for desktop, but that is packaging; the notes say nothing about how its settings label the two ([Google Workspace Updates](https://workspaceupdates.googleblog.com/2021/02/google-drive-for-desktop-sync-solutions-update.html)). Even Dropbox's "Backup" is, per a community reply, an automation that moves folders into the synced folder, which shows how muddy the two get ([Dropbox Community](https://www.dropboxforum.com/discussions/101001014/sync-vs-backup/512060)). Evidence for a combined page is thin: Apple's HIG wants sync to be invisible ("assume they're always accessing the latest version"), and Apple still needed Recently Deleted and a note that photos are not in the backup ([HIG](https://developer.apple.com/design/human-interface-guidelines/icloud.md)). Inference: a transparent combined toggle produces exactly the misunderstanding the owner fears. No study measures how many users confuse the two; the claim rests on vendor docs, forum threads (for example [Obsidian forum](https://forum.obsidian.md/t/how-obsidian-nearly-lost-all-my-files-and-scared-the-crap-out-of-me/81104)) and vendor blogs with a commercial interest.

**Clipboard peers default private and treat history as sensitive.** Paste syncs Clipboard History and Pinboards behind one per-device iCloud toggle, off by default, with no documented categories or status UI ([Paste](https://pasteapp.io/help/where-paste-stores-your-data), [Paste troubleshooting](https://pasteapp.io/help/icloud-sync-doesn-t-work)). Raycast offers per-category toggles and states "Clipboard History stays on your device" ([Raycast](https://manual.raycast.com/cloud-sync.md)); Alfred leaves Clipboard History per Mac ([Alfred](https://alfredapp.com/help/advanced/sync)). Maccy has no sync ([issue](https://www.goodfirstissue.org/p0deje/Maccy/issues/182)). Sensitive clips are handled at capture, not at sync; no surveyed product offers a per-item "do not sync" flag, and none exposes a user-facing "exclude secrets from sync" toggle (a gap, not proof of absence). Inference: Pesto's default of excluding secrets with an opt-in is stricter than Paste and consistent with Raycast.

**Per-Mac opt-in and "settings don't sync" have precedent.** Obsidian states sync settings do not sync across devices, and offers Pause/Resume; Bear lets you temporarily disable sync on one device ([Obsidian](https://obsidian.md/help/sync/settings), [Bear](https://bear.app/faq/sync-troubleshooting/)). Signal backups and Apple's Advanced Data Protection are opt-in ([Signal](https://signal.org/blog/introducing-secure-backups/), [Apple](https://support.apple.com/en-us/102651)). I found no product that silently enables cloud sync. Apple's HIG also advises against per-document choices and for a first-run all-or-nothing choice; a clipboard of secrets is a sharper case, so categories (not items) are the compatible shape. That reconciliation is my inference.

**Status vocabulary is small and plain.** Dropbox uses "Your files are up to date", "Syncing", paused (with what stops), and a specific error ([Dropbox icons](https://help.dropbox.com/sync/macos-sync-icons)). Bear, Obsidian and Things show last-sync time. Raycast shows per-category counts ("Catching up") with Retry and warns not to toggle off and on to force a sync, since deleted items may reappear ([Raycast](https://manual.raycast.com/cloud-sync.md)). Apple's HIG says to unobtrusively tell people that changes will not reach other devices while iCloud is unavailable. A single-source design blog argues "connected" differs from "your change arrived" and warns against indiscriminate recovery buttons ([ScreensDesign](https://screensdesign.com/articles/mobile-cloud-sync-status-recovery-ux/)); treat it as opinion. Not found in any product: "Keep it up to date automatically" as a label.

## Recommended structure and wording

Use one page, two sections, in this order: a one-line summary at the top, then Backup, then Sync. The summary reads "Your clips stay on this Mac. Backup: Off. Sync: Off." (Inference: it tells a new user the default state without opening anything.) Each Off section has one button, **Set Up…**, which opens a short guided sheet; there is no first-run modal.

| Item | Suggested wording |
|---|---|
| Backup toggle | **Save a Backup Automatically** — "Writes one encrypted file for this Mac after you copy. Your other Macs never read it." |
| Backup "is not" | "A backup is a copy you can restore from. It never changes another Mac." |
| Sync toggle | **Sync Clips with iCloud Drive** — "Keeps the Macs where you turn this on matching." |
| Sync "is not" | "Sync keeps your Macs matching, so deleting a clip on one deletes it on all. It is not a backup." (adapted from Dropbox and Apple; verify against the sync design (Proposed) that deletes do propagate) |
| Backup states | Off · Up to Date · Saving… · Folder Missing · Waiting for the Folder (name the cause) |
| Sync states | Off · Up to Date · Receiving N of M · Nothing New Since 14:32 · Waiting for the Folder · Folder Missing · iCloud Keychain Is Off · Not Signed In to iCloud · Refused |
| Actions | **Pause** while on; **Leave Sync** (this Mac only, clips stay); **Reset Sync** (destructive, states that other Macs stop until set up again) |

State text should show the last completed exchange, never connectivity alone, and pair every error with one next step (Inference, from the Dropbox, Bear and ScreensDesign material). Use shape plus text, not color alone. Show no list of Macs, which matches Obsidian and Cryptomator, where vault-style designs have no device list and recover by starting over ([Obsidian security](https://obsidian.md/help/sync/security)). Reset Sync should say plainly: "Other Macs stop syncing until you set up sync on them again." Do not copy Raycast's per-device list.

## What goes where

The model is a small matrix in the sheet and in Settings, with categories (never items), applied separately to Backup and Sync.

| Category | Backup | Sync |
|---|---|---|
| Clips (text, links, images, files) | On | On |
| Pinned clips and collections | On | On |
| Snippets | On | On |
| Hidden or secret clips | Off, opt in: "Include hidden clips" | Off, opt in, same wording |
| This Mac's settings, shortcuts, ignored apps | On (restore only) | Never, like Obsidian and Alfred |

All rows except the last are Inference; only the "history is sensitive" and "settings stay per Mac" stances are precedented. The decision on secrets in Backup is the owner's: an encrypted file restored by the same person is lower risk than a shared sync folder, but one consistent wording is simpler. Whatever is chosen, say it in the section: "Hidden clips are not included." The sync key lives in iCloud Keychain, so the first-run sheet needs no recovery-key ritual. Day One, Signal, 1Password and Apple all show the user a key because they cannot hold it for them. The only key states Pesto shows are iCloud Keychain Is Off and Not Signed In to iCloud, each with a pointer to System Settings.

## First run, restore and what to avoid

**First run.** Both sections are Off on every Mac and nothing is uploaded. Offer Set Up… once in onboarding as a skippable step with plain consequences, then leave it in Settings → Data. This follows the HIG's single all-or-nothing choice and Paste's per-device switch. Nothing found tests whether a first-run prompt raises adoption.

**Restore.** Make restore a Backup action, "Restore from Backup…", with a file picker, so it is never confused with sync. Default to adding to this Mac's clips (the Things merge prompt recommends "Keep all", [Cultured Code](https://culturedcode.com/things/support/articles/2803590/)), with "Replace" as an explicit second choice; Bear's import replaces everything, which is the thing to avoid by default. Show counts first, such as "42 clips will be added, 310 are already here". No source documents a count-based preview; Dropbox Rewind's "fine tune" list is the nearest ([Dropbox](https://help.dropbox.com/delete-restore/rewind)), so treat this as my suggestion. Pair deletes with a soft-delete window if Pesto has one; Apple, 1Password and Google Drive use 30 days ([Apple](https://support.apple.com/guide/icloud/mm2f42f05cb9/icloud), [1Password](https://support.1password.com/archive-delete-items)).

**Avoid.** Do not put an auto-update toggle on Backup; do not call anything "synced" or "up to date" without a completed exchange; do not offer per-clip sync choices or a Macs list; do not use "(s)" counts or unexplained red errors; do not make Reset Sync look routine, since Bitwarden frames its equivalent as an emergency action ([Bitwarden](https://bitwarden.com/help/account-encryption-key/)) and Paste's last-resort reset deletes the only copy ([Paste](https://pasteapp.io/help/icloud-sync-doesn-t-work)); do not tell users to toggle off and on to force a sync.

## Conclusion

The research does not settle combined versus two. It settles the failure mode: any control that makes a backup update continuously reads as sync, and sync's defining consequence is that deletes spread. The strongest design therefore chooses structure by consequence: two sections, because they have different delete consequences, joined by one page summary so the experience stays easy.

Open items before building: confirm Pesto's sync propagates deletes before using the "is not" sentences, decide secrets-in-Backup, and treat the status strings above as drafts, since no external source tested them with users.
