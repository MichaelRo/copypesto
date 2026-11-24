# 0064. The iOS keyboard copies pictures on tap, inserts recognized text on request, and covers during capture

Status: Proposed

Amends ADR 0046 (which left out a keyboard extension) and extends the quick-insert set and screen-capture rules of ADR 0051, ADR 0054, ADR 0061, and ADR 0034.

## Context
A custom iOS keyboard extension (`PestoKeyboard`) reads from `QuickInsertFile` (`QuickInsertSet` / `QuickInsertSelection`) with **Allow Full Access** (ADRs 0061–0063) and never accesses the main history store or widget snapshots. When picture clips are supported on the keyboard, tapping a picture card needs a predictable default action:

- `UITextDocumentProxy.insertText(_:)` can only insert plain text, not image data.
- A picture may have no recognized text (OCR), or the person may want the image itself in a messaging or notes field rather than its extracted text.
- Opening `QuickInsertFile` and writing an image to `UIPasteboard` from the keyboard extension both require **Allow Full Access** (`hasFullAccess == true`). When Full Access is off, the keyboard offers only its built-in numbers-and-punctuation pad (ADR 0061). When a picture is placed on the system pasteboard, it must not linger indefinitely or sync via Universal Clipboard.
- Pictures that hold secret-scanned recognized text benefit from a secondary text-insertion path without replacing the image copy default.
- The keyboard strip must uphold Pesto's existing privacy guarantees: files (`.file`), adult content (`item.isNSFW`), expiring/pending clips, and secrets (including secrets detected in recognized text via `SensitiveContentDetector`) must never enter `QuickInsertSet`, and active screen capture or recording must cover the keyboard strip (ADR 0054).

## Decision
1. **Pictures join `QuickInsertSet` (`QuickInsertSelection` / `QuickInsertFile`) under strict bounds, never `WidgetSnapshot`.**
   - `PestoKeyboard` reads only `QuickInsertFile` (under the shared quick-insert Keychain group) with Full Access enabled (`hasFullAccess == true`).
   - Thumbnail/image payloads carried for keyboard display stay bounded within the quick-insert set's budget and exclude `.file`, `item.isNSFW`, expiring, pending-analysis, and secret clips (including OCR text matching `SensitiveContentDetector`).

2. **Default tap on a picture card copies the picture thumbnail (requires Full Access).**
   - Tapping a picture card writes its bounded JPEG thumbnail (`entry.thumbnail`, capped in `QuickInsertSelection`) to `UIPasteboard.general` with `localOnly: true` and a 120-second expiration (`Date().addingTimeInterval(120)`).
   - After copying, the keyboard shows `"Copied, paste it"` feedback so the person knows the image is ready to paste into the target field.

3. **Secondary action inserts secret-scanned recognized text.**
   - When a picture has recognized text scanned clean for secrets (ADR 0034), the card shows a `text.viewfinder` badge.
   - Tapping the `text.viewfinder` badge directly, choosing **Insert Text** in the picture card's long-press `.contextMenu`, or invoking the VoiceOver `.accessibilityAction` inserts the scanned text via `textDocumentProxy.insertText(_:)`.

4. **Screen capture covers the keyboard strip.**
   - When `traitCollection.sceneCaptureState == .active`, the keyboard blurs all states and displays cover copy when the menu is ready so clips are not exposed in screenshots, screen recordings, or AirPlay (ADR 0054).

## Consequences
- Picture clips become usable from the iOS keyboard while keeping the keyboard strictly isolated to `QuickInsertFile` and Full Access (no widget key/file coupling).
- Copied pictures stay local to the device (`localOnly: true`) and expire automatically after 120 seconds.
- Users without Full Access see only the numbers-and-punctuation pad and never trigger broken image copies or pasteboard prompts.

## Docs affected
- `decisions/README.md` (index entry)
- `docs/design/ios-keyboard.md` (when implemented)
- `docs/guide/privacy-and-security.md` (Full Access, 120s local-only pasteboard, and screen-capture cover notes, once accepted and shipped)
