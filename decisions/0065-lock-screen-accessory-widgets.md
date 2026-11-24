# 0065. Lock Screen accessory widgets require explicit per-widget opt-in and never show secrets

Status: Accepted (owner request, 2026-11-24)

Amends the "No Lock Screen families" rule of ADR 0052 and extends the snapshot, History Lock, and collection-widget rules of ADR 0054, ADR 0055, and ADR 0060.

## Context
Users may want quick glanceable access to their latest clip, a pinned clip, or a collection on the iPhone Lock Screen (or StandBy), using WidgetKit's accessory families (`accessoryCircular`, `accessoryRectangular`, and `accessoryInline`). Unlike Home Screen widgets, a Lock Screen widget is visible before the phone unlocks whenever iOS's system Lock Screen Widget visibility is enabled.

Adding accessory families directly to `RecentClipsWidget` (`Sources/Widget/`, shared with macOS `PestoControls`) would expose a Lock Screen opt-in toggle in Home Screen widget configuration and couple macOS desktop widgets to iOS Lock Screen families. Furthermore, the sealed widget snapshot (`widget-snapshot.pestowidget`) uses `.completeFileProtection`, so an interactive `CopyClipIntent` cannot read the snapshot while the device is locked, and `accessoryInline` only supports `.widgetURL`.

## Decision
1. **Separate iOS-only widget (`LockScreenClipsWidget`, `AppIdentity.lockScreenWidgetKind`).**
   - `PestoWidgetBundle` registers `LockScreenClipsWidget` alongside `RecentClipsWidget`, supporting `.accessoryCircular`, `.accessoryRectangular`, and `.accessoryInline`.
   - `RecentClipsWidget` and macOS `PestoControls` remain untouched and keep `.systemSmall`, `.systemMedium`, and `.systemLarge`.
   - `WidgetTarget` checks and reloads both `AppIdentity.widgetKind` and `AppIdentity.lockScreenWidgetKind`.

2. **Off-by-default per-widget opt-in (`showsClipsOnLockScreen = false`).**
   - `LockScreenClipsConfiguration` exposes `Show Clips on Lock Screen` (default `false`), `Show` (`Recent`, `Pinned`, `Collection`), and conditional `Collection`.
   - When `showsClipsOnLockScreen` is `false`, `LockScreenWidgetContent` always resolves to `.optInRequired` and renders no clip text, preview, host, color, or thumbnail (nor even History Lock status), showing only a non-leaking prompt to edit the widget.
   - When `showsClipsOnLockScreen` is `true`, clip views also apply `.privacySensitive()` so iOS's system-wide Lock Screen privacy redaction remains effective as defense-in-depth.

3. **Secrets never appear; History Lock still applies.**
   - `WidgetSnapshotSelection` already excludes every secret, pending, expiring, and explicit clip before writing `widget-snapshot.pestowidget`.
   - While History Lock is active and `Setting.showsClipsOutsideWhileLocked` is off, `MobileAppState` writes `WidgetSnapshot.locked`; `LockScreenWidgetContent` renders `.locked` with `AppLink.url(for: .unlock)`.

4. **Navigation uses `.widgetURL` only.**
   - Choosing a clip routes through `WidgetLink.url(for: clip.id, action: .show)`, letting iOS prompt Face ID or passcode before opening Pesto to that clip's detail view instead of overwriting the clipboard from a locked screen or failing against `.completeFileProtection`.

## Consequences
- No clip content can appear on the Lock Screen unless the user explicitly edits that Lock Screen widget and turns on **Show Clips on Lock Screen**.
- Home Screen and macOS widget configurations stay uncluttered and free of Lock Screen options.
- Adding or removing a Lock Screen widget keeps `widget-snapshot.pestowidget` managed under the existing `WidgetTarget` lifecycle (`WidgetCenter.currentConfigurations()`).

## Docs affected
- `decisions/README.md` (index entry)
- `docs/design/ios-library.md` (Lock Screen accessory widgets section)
- `docs/testing.md` (iOS Lock Screen widget verification checklist)
