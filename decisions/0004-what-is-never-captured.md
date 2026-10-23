# 0004. Built-in exclusions are permanent, a timed allowance keeps hidden copies, and other devices' copies are opt-in

Status: Accepted

## Context
Pesto never captures from password managers and keychain tools, and drops any copy carrying a concealed or transient
pasteboard marker. The built-in list is append-only so nobody removes a password manager for good and regrets it. But a
person who wants to copy a note out of a password manager for a few minutes cannot, and managers mark every copy
(usernames included) as concealed, so lifting the app exclusion alone captures nothing. Managers clear their own
clipboard
copy after 10 to 90 seconds, so a day in Pesto's history is far longer than such a copy was meant to live.

Universal Clipboard puts copies from an iPhone, iPad or another Mac on this Mac's pasteboard. Kept unconditionally they
fill the history with things not copied here. Reading one starts a transfer from the other device, so a watcher that
read
the bytes before looking for the remote marker would pull every phone copy over the air only to discard it.

## Decision
**The list.** No built-in bundle ID is ever removed from `ExclusionRules.defaultExcludedBundleIDs`; removing one needs a
new
decision and reviewer approval. People can add their own apps and remove those at any time. Concealed and transient
markers
(`ExclusionRules.concealedTypeMarkers`) always drop a copy. Drops are counted by reason (excluded app, concealed marker,
other device) for the Privacy pane, never what was copied.

**The allowance.** The only way past a built-in entry. In Settings → Privacy → App exclusions the person chooses
**Allow**
on the row, then **15 minutes, 1 hour, 4 hours or until Pesto quits** (`ExclusionAllowances.Length`). It asks for
authentication first (ADR 0003). End times live in `ExclusionAllowances` in memory only, never in preferences (any
process of
the same user can write those). `ExclusionRules.isExcluded(_:now:)` is evaluated at each copy, so an allowance ends with
no
timer; one for an app that is not built in is ignored; the person can Stop early; all are cleared when Pesto launches.

**What an allowance lets through.** A copy from that app, including one the app marked concealed, only for that app and
only
while the allowance lasts. Any other app's concealed copy is still dropped. The check covers every app that may have
made the
copy (the frontmost one and those in front a moment before).

**Kept copies are credentials.** A kept concealed copy is stored hidden: category `credential`, badge "Credential",
preview
"Hidden by <app name>", shown only with Show (ADR 0003), pasting like any clip. If the text also looks like a secret,
that
category and mask apply instead. It expires when its allowance ends and never later than 24 hours after it was copied
(`StorageService.concealedExpiry`; "until quit" has no end, so the cap applies). With several possible allowed sources
the
earliest end wins (`ExclusionRules.concealedKeepEnd`). An allowance that runs out or is stopped removes that app's kept
copies
at once (`StorageService.removeKeptConcealedCopies`, from `AppDelegate.reviewAllowances`), and launch removes every kept
copy
still in the history. Pinned clips stay: pinning is the person's choice. A kept copy is a clip from a built-in app that
is a
credential or carries an expiry; a burn-after-paste mark is not an expiry, and a plain unconcealed copy from an allowed
app
is an ordinary clip.

**Copies from other devices.** `Setting.keepsRemoteCopies` is off by default (Settings → Privacy → Other devices; also
in
onboarding). A copy is remote when its types include `com.apple.is-remote-clipboard`. Off, the watcher drops it
(`ExclusionRules.blockReason` returns `.remoteCopy`), counts it in `PrivacyStats.remoteBlocks` and stores nothing. The
decision is made before any content is read: `PasteboardWatcher.tick()` reads the type list and `dropsRemoteCopy` judges
by
markers alone, so a dropped copy is never transferred. A remote copy ignores the frontmost apps (an excluded app in
front does
not drop a phone copy, and an allowance cannot mark it concealed); concealed and transient markers still drop it. It has
no
`sourceBundleID` and shows a phone glyph. Turning the setting on keeps copies from then on; kept clips stay when it is
turned
off. Remote copies mix into the history by time (macOS gives no public way to tell which device), found with the **Other
Devices** chip (`AppState.searchRemoteOnly`; shown while the setting is on, any remote clip exists, or it is active) and
the
smart-collection rule `PredicateRule.Field.isRemote`. Copying the same content again takes the origin of the latest
copy; a
backup carries `isRemote` as an optional field. `PasteboardWatcher.boardHoldsUnrecordedCopy` is true from a dropped copy
until
the next captured one, and Quick Paste Last (`QuickPasteLast.index`) then pastes the newest history entry, otherwise the
second.

A file copied on another device sits in Universal Clipboard's own folder
(`~/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/`), which macOS protects from
other apps (reading its bytes fails with "operation not permitted", measured 2026-10) and empties within seconds of the
pasteboard changing, so a path to it is dead at once and its bytes are out of reach. A remote file is therefore not kept
(a photo included): the watcher counts it as left out (`.remoteCopy`, `RemoteFileClip` reads a single picture only where
the system allows it). Local file copies are unchanged: they keep a path.

## Consequences
- For the length of an allowance (at most a day) a kept credential is in the history behind Show; the History Lock, the
  cover (ADR 0003) and the short choices are the mitigations. Settings states this beside the control.
- Removals are retention deletions: no tombstone, and they lower the backup baseline like any sweep. The sweep runs
  every six
  hours, so an expired stored copy can linger; the shelf hides it as soon as it recomputes.
- Someone who relied on remote clips appearing turns the setting on once; changing the default is a change to
  `Setting.keepsRemoteCopies`.
- Tests: `ExclusionRulesTests`, `CredentialClipLifetimeTests`, `RemoteCopyPolicyTests`, `RemoteCopyTests`,
  `ShelfActionsTests`,
  `OtherDevicesTests` (UI).

## Docs affected
`AGENTS.md` (invariant 3), `docs/guide/settings.md`, `docs/guide/privacy-and-security.md`,
`Sources/Features/Settings/ExclusionSettings.swift` (the Allow footer), `Sources/Core/Pasteboard/CLAUDE.md`.
