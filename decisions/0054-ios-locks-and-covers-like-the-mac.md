# 0054. iPhone and iPad lock the history and cover cards as the Mac does

Status: Accepted (owner request, 2026-11-18)

Extends ADR 0003 (secrets, one authentication window, the screen-share cover), ADR 0008 (undo), ADR 0046 (Pesto on
iPhone and iPad), ADR 0047 (the inbox), ADR 0051 (the AutoFill set) and ADR 0052 (the widget). Supersedes ADR 0052's
sentence "The iOS app has no History Lock and no Hide Clip Contents today".

## Context
The Mac locks its history behind Touch ID or the password (`HistoryLockPolicy`, one `AuthenticationGrace` window) and
covers cards during a screen share or by hand (`ContentCover`, `CardConcealment`). The iOS app had neither, ADR 0051 and
0052 asked that a lock added later empty their files, and `resumePendingAnalysis` ran only on the Mac, so a picture or
long text whose judging an iOS kill interrupted stayed pending (hidden from the widget, AutoFill and Shortcuts) for good.

iOS gives an app no time when a timeout passes while it is suspended, and reports a recording, mirroring or AirPlay of
a scene through the `sceneCaptureState` trait (iOS 17; `UIScreen.isCaptured` is deprecated).

## Decision
**History Lock.** The same setting as the Mac, `Setting.biometricLockEnabled`, off by default as on the Mac, in Settings
→ Privacy ("Lock history with Face ID", Touch ID, Optic ID or "your passcode"). It is switched on only where the device
can authenticate and switched off only after a fresh prompt (`HistoryLockPolicy`). The timeout is the one window, "Ask
for Face ID again after" (`AuthenticationGrace`); there is no second timer. Pesto is locked at launch and when it comes
back after being out of the foreground for that long (`MobileHistoryLock`, decided by `HistoryLockPolicy.isLocked` with
the moment it left as the last unlock). The library is replaced by a lock screen, so no card is drawn under it; it asks
once by itself each time it is shown, and its button stays. Where nothing can authenticate it offers Turn Off History
Lock, as the Mac's policy allows.

While locked, as `AppState.lockHistory` does on the Mac: the search index text and `PreviewTextCache` are dropped and
the history is not read until the unlock; Undo and its offer are cleared (ADR 0008); shown secrets and cards shown under
the cover hide; Shortcuts search and entity queries return nothing; sync pauses (`SyncController.Environment.isLocked`);
the share extension's inbox, the clipboard on open and a widget link wait for the unlock. What is open (a detail, the
editor and its draft, Settings, a search) is closed.

**The widget and the AutoFill set hold nothing while the lock is on**, not only while locked: the snapshot is removed
(the widget says to open Pesto) and the AutoFill set is written empty, when the lock is turned on and whenever they
would be written. iOS cannot run Pesto at the moment the timeout passes, so emptying them "on lock" would leave them
readable until the next launch; this matches the Mac, which writes no last-item file while the lock is on.

**Cover.** `Setting.screenSharingPrivacy`, off by default as on the Mac, is "Hide clips while the screen is recorded or
shared"; with it on, a scene whose `sceneCaptureState` is active covers every card through `ContentCover` and
`CardConcealment(screenShareBlur:)`. "Hide clip contents now" in Settings → Privacy is the Mac's Hide Clip Contents:
not saved, it lasts until turned off or Pesto quits. A covered card says only its kind and offers Show, which uncovers
that card without asking, until the cover lifts and returns or Pesto leaves the foreground; a secret then keeps its own
mask and Show. Covered is not locked: a tap still copies.

**App Switcher.** While a scene is not active, a window of its own above every sheet covers it with a plain ground, so
the App Switcher's picture holds no card, whatever the settings.

**Resuming judgment.** The iOS boot calls `resumePendingAnalysis` after the launch migrations, on the storage actor, as
the Mac does at launch.

## Consequences
- `MobileHistoryLockTests`, `MobileContentCoverTests`, `MobileSyncTests` (sync paused while locked),
  `MobileAppStateTests` (a pending picture judged at launch) and `PrivacyUITests` (the lock screen draws no card; Hide
  Clip Contents covers) pin it.
- With the lock on, the widget and AutoFill are of no use; the Settings footer says so.
- A background refresh with the lock on finds the history locked and does not exchange, as a locked Mac does not.
- The cover window also shows while the Face ID prompt or Control Center makes Pesto inactive.
- In the iOS 27.2 simulator `simctl io recordVideo` did not change the capture trait, so a real recording, mirroring
  and AirPlay are hand checks on a device, as are Face ID itself and the App Switcher picture.
- A covered iOS card keeps its foot line (source and age); the Mac's covered card shows only its number, kind and age
  (ADR 0028).

## Docs affected
`AGENTS.md` (the Mobile paragraph), `docs/testing.md` ("The iPhone and iPad app"), `docs/design/ios-library.md`,
`decisions/README.md`, the status line of ADR 0052. The README and the guide say nothing about the iPhone app until it is
released (ADR 0046).
