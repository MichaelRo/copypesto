# 0055. The iOS widget says Locked, and one setting lets widgets and AutoFill keep their clips

Status: Accepted (owner decision, 2026-11-18)

Extends ADR 0054 (History Lock on iPhone and iPad), which it amends where that ADR says the widget and AutoFill "hold
nothing while the lock is on". Extends ADR 0051 (AutoFill) and ADR 0052 (widget).

## Context
With the lock on, ADR 0054 removed the widget's snapshot and emptied the AutoFill set, so the widget looked broken
("Open Pesto to show your clips") and AutoFill listed nothing. iOS gives Pesto no moment to empty either file when the
timeout passes, so anything left there is readable by whoever holds an unlocked device. Some people want the
convenience anyway.

## Decision
- The default stays: with the lock on, the widget holds no clips and the AutoFill set is empty. The widget now says
  "Locked" and, on one line, "Open Pesto to see your clips", from a sealed snapshot that carries `isLocked` and no clip
  (`WidgetSnapshot.locked`, `WidgetContent.State.locked`), instead of a missing file that read as an error.
- One more setting, `Setting.showsClipsOutsideWhileLocked`, off by default, "Show clips in widgets and AutoFill",
  under the History Lock row in Settings → Privacy and enabled only while the lock is on. On, the snapshot and the
  AutoFill set are written as they are without the lock; their own rules (no secrets, no hidden clips, the bounds)
  still apply, and the footer says anyone holding the device can then read them.
- Turning the toggle or the lock moves both files at once (`showsClipsOutsideSettingChanged`).
- Nothing else changes: the app itself, Shortcuts, sync and the inbox stay locked as in ADR 0054.

## Consequences
- `MobileHistoryLockTests` pins both states; `WidgetContentTests` pins the Locked state and that an older snapshot
  without the field opens as unlocked.
- `isLocked` is optional in the sealed format, so no format version changes.

## Docs affected
`docs/design/ios-library.md`, `decisions/README.md`. The README and the guide say nothing about the iPhone app until it
is released (ADR 0046).
