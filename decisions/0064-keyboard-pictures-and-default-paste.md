# 0064. The iOS keyboard copies pictures on tap, inserts recognized text on request, and covers during capture

Status: Proposed

Amends ADR 0046 (which left out a keyboard extension) and extends the sealed-snapshot and screen-capture rules of ADR 0052, ADR 0054, and ADR 0034.

## Context
A custom iOS keyboard extension lets a person reach their recent clips from any text field without leaving the current app. When picture clips are included in the keyboard's sealed snapshot, tapping a picture card needs a predictable default action:

- `UITextDocumentProxy.insertText(_:)` can only insert plain text, not image data.
- A picture may have no recognized text (OCR), or the person may want the image itself in a messaging or notes field rather than its extracted text.
- Writing an image to `UIPasteboard` from a keyboard extension requires **Allow Full Access** (`hasFullAccess == true`). When a picture is placed on the system pasteboard, it must not linger indefinitely or sync to other devices via Universal Clipboard.
- At the same time, pictures that do have secret-scanned recognized text benefit from a direct text-insertion path without replacing the image copy default.
- The keyboard strip must uphold Pesto's existing privacy guarantees: files (`.file`), adult content (`item.isNSFW`), and secrets (including secrets detected in recognized text via `SensitiveContentDetector`) must never enter the keyboard snapshot, and active screen capture or recording must cover the strip just as the main iOS app does (ADR 0054).

## Decision
1. **Default tap on a picture card copies the picture.**
   - Tapping a picture card in the keyboard writes the picture to `UIPasteboard.general` with `localOnly: true` and an expiration date of 120 seconds (`Date().addingTimeInterval(120)`).
   - This applies to every picture card in the keyboard snapshot, including pictures without recognized text.
   - Writing to `UIPasteboard` requires Full Access (`hasFullAccess`); when Full Access is off, the keyboard surfaces the Full Access requirement instead of silently failing.
   - After copying, the keyboard shows `"Copied — tap field to Paste"` feedback so the person knows the image is ready to paste into the target field.

2. **Secondary action inserts secret-scanned recognized text.**
   - When a picture has recognized text (scanned for secrets under ADR 0034 before entering the snapshot), the card displays a `text.viewfinder` badge.
   - A long-press `.contextMenu` on the picture card offers **Insert Recognized Text**, which inserts the scanned text directly at the cursor via `textDocumentProxy.insertText(_:)`.

3. **Snapshot exclusions remain strict.**
   - File clips (`.file`), adult clips (`item.isNSFW`), expiring clips, pending-analysis clips, and secrets (including pictures whose recognized text matches `SensitiveContentDetector`) are excluded from the keyboard snapshot (`ShortcutClipSearch.isOfferedOutsidePesto` and `WidgetSnapshotSelection`).

4. **Screen capture covers the keyboard strip.**
   - When `traitCollection.sceneCaptureState == .active`, the keyboard covers/blurs its strip so clips are not exposed in screenshots, screen recordings, or AirPlay, matching ADR 0054.

## Consequences
- Picture clips become usable from the iOS keyboard even when they contain no text, without changing `insertText` semantics for text, link, or color clips.
- Users without Full Access enabled can still browse and insert text clips via `textDocumentProxy.insertText(_:)`, while copying a picture requires Full Access and prompts accordingly.
- Because copied pictures use `localOnly: true` and a 120-second expiration, they stay off Universal Clipboard and expire automatically from the system pasteboard.
- Excluding `.file`, `item.isNSFW`, and secret-bearing OCR text keeps the sealed keyboard snapshot aligned with the widget and AutoFill privacy boundaries.

## Docs affected
- `decisions/README.md` (index entry)
- `docs/design/ios-library.md` (when the keyboard is documented)
- `docs/guide/privacy-and-security.md` (keyboard Full Access, 120s local-only pasteboard, and screen-capture cover notes, once accepted and shipped)
