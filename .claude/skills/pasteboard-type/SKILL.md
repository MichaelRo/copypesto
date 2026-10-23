---
name: pasteboard-type
description: Recipe for adding a new clipboard/pasteboard content type to Pesto — ClipboardType enum, PasteboardTypeDetector priority, ContentClassifier, ClipboardCard rendering, StorageService type mapping, thumbnails, drag types and the capture test. Use when adding or changing support for a pasteboard type or UTI (e.g. "support HEIC", "handle a new file type", "add a card type").
---

# Adding a New Pasteboard Type

Touch exactly these files, in this order. Anything more and you've over-engineered.

1. **`Sources/Core/Model/ClipboardType.swift`** — add a case to the `ClipboardType` enum if needed. Schema changes are migration events; don't add fields lightly (a refinement of an existing type, like SVG source, is `type == .code` plus `detectedLanguage`, not a new case).

2. **`Sources/Core/Pasteboard/PasteboardTypeDetector.swift`** — add the `NSPasteboard.PasteboardType` to `priorityOrder` in the correct position (higher = more specific). PDF and SVG stay last on purpose.

3. **`Sources/Core/Pasteboard/ContentClassifier.swift`** — add the detection logic that maps raw pasteboard data (text) to the new type.

4. **`Sources/Core/Storage/Models/StorageService.swift`** — add the type mapping to the local `clipboardType()` function; it was missed for GIF and caused a silent fallback to `.string`.

5. **`Sources/Features/Grid/ClipboardCard.swift`** — add a body variant (`case .newType:`) in `cardContent`, and say in `hasFullWidthBody` whether it fills the card.

6. **If the card draws a picture:** `Sources/Core/Storage/Models/ThumbnailService.swift` makes the thumbnail (ImageIO first, then `SVGThumbnail`, which must run on the main actor and refuses over 2 MB), and `ClipboardCard+Loading.swift` decides which items ask for one.

7. **If it can be dragged out:** `Sources/Core/Paste/DragTypes.swift` lists the types offered directly (the stored type first, PNG as the fallback), and `ClipboardCard+Drag.swift` supplies the bytes.

8. **Tests:** a capture round trip in `Tests/PestoTests/CaptureRoundTripTests.swift` (copy it, tick the watcher, check the stored type, the thumbnail and that it pastes back), plus `PasteboardTypeDetectorTests`, `ContentClassifierTests` and `DragTypesTests` for the Core parts.
